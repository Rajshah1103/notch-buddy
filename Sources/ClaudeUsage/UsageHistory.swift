import Foundation

/// Token use per day and per hour of day over the last 90 days, totalled from the session transcripts.
public struct UsageHistory: Equatable {
    /// Start of a (local) day → tokens, counted the same way as everywhere else (input + cache writes + output).
    public var daily: [Date: Int]
    /// Tokens by hour of day (0...23) over the whole window.
    public var hours: [Int]
    /// Start of a day → how many chats were active in it.
    public var chats: [Date: Int]

    public static let empty = UsageHistory(daily: [:], hours: Array(repeating: 0, count: 24), chats: [:])

    public init(daily: [Date: Int], hours: [Int], chats: [Date: Int]) {
        self.daily = daily; self.hours = hours; self.chats = chats
    }
}

/// Totals the last 90 days of transcripts without ever reading one twice. Per file it remembers how far
/// it has read and what that read added up to, in a small cache of numbers (no conversation text), so
/// after the first pass only newly appended bytes are read.
// All mutable state is touched only on `queue`, which is what makes sharing the object safe.
public final class UsageHistoryScanner: @unchecked Sendable {
    public static let windowDays = 90

    public var onChange: ((UsageHistory) -> Void)?

    private struct Tail: Codable { var id: String; var day: String; var hour: Int; var tokens: Int }
    private struct Entry: Codable {
        var offset: UInt64
        var days: [String: Int] = [:]
        var hours: [Int] = Array(repeating: 0, count: 24)
        /// The last message read. A streamed message can be rewritten after a pass ends; if it shows up
        /// again, its earlier count is taken back out first.
        var tail: Tail?
    }

    private let root: URL
    private let cacheURL: URL
    private let calendar: Calendar
    private let queue = DispatchQueue(label: "notchhub.claude-history", qos: .utility)
    private var entries: [String: Entry] = [:]
    private var timer: DispatchSourceTimer?
    private var lastScan = Date.distantPast
    private var scanning = false

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects"),
                cacheURL: URL? = nil, calendar: Calendar = .current) {
        self.root = root
        self.calendar = calendar
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notch Hub/claude-history.json")
    }

    public func start() {
        queue.async { [self] in
            loadCache()
            publish()                       // whatever the cache already knows, at once
            scan()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 600, repeating: 600)
            timer.setEventHandler { [weak self] in self?.scan() }
            timer.resume()
            self.timer = timer
        }
    }

    public func stop() {
        queue.async { [self] in timer?.cancel(); timer = nil }
    }

    /// Reads what was appended since the last pass, if that was a while ago.
    public func refresh(maxAge: TimeInterval = 60) {
        queue.async { [self] in
            guard Date().timeIntervalSince(lastScan) > maxAge else { return }
            scan()
        }
    }

    // MARK: - Scanning

    private func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func scan() {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false; lastScan = Date() }

        let cutoff = calendar.date(byAdding: .day, value: -(Self.windowDays - 1), to: calendar.startOfDay(for: Date())) ?? Date()
        var live: Set<String> = []
        let projects = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for project in projects {
            let files = (try? FileManager.default.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where file.pathExtension == "jsonl" {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                guard modified >= cutoff else { continue }
                live.insert(file.path)
                autoreleasepool { read(file, cutoff: cutoff) }
            }
        }
        entries = entries.filter { live.contains($0.key) }
        saveCache()
        publish()
        malloc_zone_pressure_relief(nil, 0)
    }

    private func read(_ file: URL, cutoff: Date) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        var entry = entries[file.path]
        if let known = entry, known.offset == size { return }           // nothing new
        if entry == nil || size < entry!.offset {                        // first sight, or rewritten
            entry = Entry(offset: TranscriptSeeker.offset(of: cutoff, in: handle, size: size))
        }
        guard var entry else { return }
        try? handle.seek(toOffset: entry.offset)

        // A streamed message appears several times in a row; the last copy wins. Only the most recent few
        // are held back for that, the rest are added up at once (a whole quarter of ids in memory was ~400 MB).
        typealias Counted = (day: String, hour: Int, tokens: Int)
        var pending: [String: Counted] = [:]
        var order: [String] = []
        var tailToTakeBack = entry.tail
        var last: (id: String, counted: Counted)?

        func commit(_ counted: Counted) {
            entry.days[counted.day, default: 0] += counted.tokens
            entry.hours[counted.hour] += counted.tokens
        }

        var position = entry.offset
        var carry = Data()
        var skipping = false          // inside a line too big to be a message (an image or a huge tool result)
        var reading = true
        while reading {
            // The read itself must sit inside the pool: its buffer is autoreleased, and a transcript can be hundreds of MB.
            autoreleasepool {
                guard let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty else { reading = false; return }
                var data = chunk
                if skipping {
                    guard let newline = data.firstIndex(of: 0x0A) else { position += UInt64(data.count); return }
                    position += UInt64(newline - data.startIndex + 1)
                    data = Data(data.suffix(from: newline + 1))
                    skipping = false
                }
                let buffer = carry + data
                guard let newline = buffer.lastIndex(of: 0x0A) else {
                    if buffer.count > 8 << 20 { skipping = true; position += UInt64(buffer.count); carry = Data() } else { carry = buffer }
                    return
                }
                let complete = buffer.prefix(through: newline)
                carry = Data(buffer.suffix(from: newline + 1))
                position += UInt64(complete.count)
                for line in TranscriptLines.parse(complete) {
                    guard let id = line.messageID, let time = line.timestamp, time >= cutoff else { continue }
                    // The previous pass's last message was counted already; if it was rewritten, take that back.
                    if let tail = tailToTakeBack, tail.id == id {
                        entry.days[tail.day, default: 0] -= tail.tokens
                        entry.hours[tail.hour] -= tail.tokens
                        tailToTakeBack = nil
                    }
                    let counted: Counted = (dayKey(time), calendar.component(.hour, from: time), line.inputTokens + line.outputTokens)
                    if pending.updateValue(counted, forKey: id) == nil { order.append(id) }
                    last = (id, counted)
                    while order.count > 64 {
                        let oldest = order.removeFirst()
                        if let done = pending.removeValue(forKey: oldest) { commit(done) }
                    }
                }
            }
        }
        for id in order { if let done = pending[id] { commit(done) } }
        if let last { entry.tail = Tail(id: last.id, day: last.counted.day, hour: last.counted.hour, tokens: last.counted.tokens) }
        entry.offset = position
        entries[file.path] = entry
    }

    // MARK: - Result

    private func publish() {
        let cutoff = calendar.date(byAdding: .day, value: -(Self.windowDays - 1), to: calendar.startOfDay(for: Date())) ?? Date()
        var daily: [Date: Int] = [:], chats: [Date: Int] = [:]
        var hours = Array(repeating: 0, count: 24)
        let parser = DateFormatter()
        parser.calendar = calendar; parser.timeZone = calendar.timeZone; parser.dateFormat = "yyyy-MM-dd"
        for entry in entries.values {
            for (key, tokens) in entry.days where tokens > 0 {
                guard let day = parser.date(from: key), day >= cutoff else { continue }
                daily[day, default: 0] += tokens
                chats[day, default: 0] += 1
            }
            for hour in 0..<24 { hours[hour] += max(0, entry.hours[hour]) }
        }
        let result = UsageHistory(daily: daily, hours: hours, chats: chats)
        onChange?(result)
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let stored = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        entries = stored
    }

    private func saveCache() {
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: cacheURL, options: .atomic) }
    }
}
