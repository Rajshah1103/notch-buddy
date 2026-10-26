import CoreServices
import Foundation

/// Watches Claude Code's session transcripts (`~/.claude/projects/*/*.jsonl`) and reports live
/// activity and token counts. Event driven: it costs nothing while nothing is being written.
// All mutable state is touched only on `queue`, which is what makes sharing the object safe.
public final class ClaudeUsageMonitor: @unchecked Sendable {
    public var onChange: ((ClaudeSnapshot) -> Void)?

    private let root: URL
    /// Claude Code keeps one small file per running session here, with its own status (busy or idle).
    private let sessionsRoot: URL
    private let store: SessionStore
    private let queue = DispatchQueue(label: "notchhub.claude-usage", qos: .utility)
    private var offsets: [String: UInt64] = [:]
    private var stream: FSEventStreamRef?
    private var expiryTimer: DispatchSourceTimer?
    private var last = ClaudeSnapshot.idle

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects"),
                sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions"),
                workingWindow: TimeInterval = 30) {
        self.root = root
        self.sessionsRoot = sessionsRoot
        self.store = SessionStore(workingWindow: workingWindow)
    }

    public func start() {
        queue.async { [self] in
            refreshQuiet()
            scanExisting()
            startWatching()
            publish()
        }
    }

    public func stop() {
        queue.async { [self] in
            if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
            stream = nil
            expiryTimer?.cancel()
        }
    }

    // MARK: - Reading

    /// Catch up at launch without a long wait: sessions are registered from file timestamps at once
    /// (so "working" is right immediately), then today's lines are read, newest transcript first.
    private func scanExisting() {
        let dayAgo = Date().addingTimeInterval(-24 * 3600)
        var recent: [(url: URL, modified: Date)] = []
        let projects = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for project in projects {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: project, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where file.pathExtension == "jsonl" {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modified, modified > dayAgo { recent.append((file, modified)) }
            }
        }
        recent.sort { $0.modified > $1.modified }

        for item in recent { register(item.url, modified: item.modified) }
        publish()

        let startOfToday = Calendar.current.startOfDay(for: Date())
        for item in recent {
            read(item.url, modified: item.modified, since: startOfToday)
            publish()
        }
        // The catch-up scan is the only time this module holds much memory; hand it back.
        malloc_zone_pressure_relief(nil, 0)
    }

    private func register(_ file: URL, modified: Date) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        store.ingest(fileID: file.deletingPathExtension().lastPathComponent,
                     folder: TranscriptSeeker.folder(inHeadOf: handle),
                     title: TranscriptSeeker.title(inTailOf: handle, size: size), lines: [], modified: modified)
    }

    /// Reads what was appended since last time; on a first read, starts at the beginning of `since`.
    private func read(_ file: URL, modified: Date, since: Date? = nil) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        let id = file.deletingPathExtension().lastPathComponent
        let size = (try? handle.seekToEnd()) ?? 0

        var offset = offsets[file.path]
        if offset == nil || size < offset! {                  // first read, or the file was rewritten
            offset = since.map { TranscriptSeeker.offset(of: $0, in: handle, size: size) } ?? 0
        }
        try? handle.seek(toOffset: offset!)

        // Read in bounded chunks: a day of one session can be hundreds of megabytes, and holding it
        // all (plus the parsed JSON) would bloat the app. Foundation's temporaries are drained per chunk.
        var position = offset!
        var carry = Data()                       // an unfinished last line, completed by the next chunk
        var lines: [TranscriptLine] = []
        var reading = true
        while reading {
            // The read itself sits inside the pool: its buffer is autoreleased, and a day can be hundreds of MB.
            autoreleasepool {
                guard let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty else { reading = false; return }
                let buffer = carry + chunk
                guard let newline = buffer.lastIndex(of: 0x0A) else { carry = buffer; return }
                let complete = buffer.prefix(through: newline)
                carry = Data(buffer.suffix(from: newline + 1))
                position += UInt64(complete.count)
                lines += TranscriptLines.parse(complete)
            }
        }
        let grew = position > (offsets[file.path] ?? 0)
        offsets[file.path] = position
        // Titles are rewritten each turn, so a smaller tail than at launch is enough to stay current.
        let title = grew ? TranscriptSeeker.title(inTailOf: handle, size: size, tail: 256 << 10) : nil
        store.ingest(fileID: id, title: title, lines: lines, modified: modified)
    }

    // MARK: - Watching

    private func startWatching() {
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<ClaudeUsageMonitor>.fromOpaque(info).takeUnretainedValue()
            let changed = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            monitor.changed(Array(changed.prefix(count)))
        }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, [root.path, sessionsRoot.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.4, flags)
        else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    /// Reads each running session's own status. Only "idle" and a vanished process count as quiet; anything
    /// else (busy, or a status this code does not know) falls back to watching the transcript.
    private func refreshQuiet() {
        let files = (try? FileManager.default.contentsOfDirectory(at: sessionsRoot, includingPropertiesForKeys: nil)) ?? []
        var quiet: Set<String> = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let id = info["sessionId"] as? String else { continue }
            let alive = (info["pid"] as? Int).map { kill(pid_t($0), 0) == 0 || errno == EPERM } ?? true
            if !alive || info["status"] as? String == "idle" { quiet.insert(id) }
        }
        store.setQuiet(quiet)
    }

    private func changed(_ paths: [String]) {
        if paths.contains(where: { $0.hasPrefix(sessionsRoot.path) }) { refreshQuiet() }
        for path in Set(paths) where path.hasSuffix(".jsonl") {
            let url = URL(fileURLWithPath: path)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            read(url, modified: modified)
        }
        publish()
    }

    // MARK: - Publishing

    private func publish() {
        let snapshot = store.snapshot()
        if snapshot != last {
            last = snapshot
            DispatchQueue.main.async { [onChange] in onChange?(snapshot) }
        }
        // When a session goes quiet nothing is written, so schedule the "idle again" update.
        expiryTimer?.cancel()
        if let expiry = store.nextExpiry() {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + max(expiry.timeIntervalSinceNow, 0) + 0.2)
            timer.setEventHandler { [weak self] in self?.publish() }
            timer.resume()
            expiryTimer = timer
        }
    }
}

/// Splits a buffer of newline-separated lines and parses each in place, without copying them.
enum TranscriptLines {
    static func parse(_ buffer: Data) -> [TranscriptLine] {
        buffer.withUnsafeBytes { raw -> [TranscriptLine] in
            guard let base = raw.baseAddress else { return [] }
            var result: [TranscriptLine] = []
            var start = 0
            while start < raw.count {
                let end = memchr(base + start, 0x0A, raw.count - start).map { base.distance(to: $0) } ?? raw.count
                if let line = TranscriptParser.parse(UnsafeRawBufferPointer(rebasing: raw[start..<end])) { result.append(line) }
                start = end + 1
            }
            return result
        }
    }
}
