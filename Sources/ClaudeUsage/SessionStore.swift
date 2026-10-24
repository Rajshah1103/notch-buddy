import Foundation

/// Folds transcript lines into a snapshot. Pure state, no file access, so it is easy to test.
public final class SessionStore {
    private struct Message { var input: Int; var output: Int; var time: Date? }

    private struct File {
        var cwd: String?
        var title: String?
        var messages: [String: Message] = [:]   // by message id: streamed updates replace, never double count
        var lastWrite: Date
        var burstStart: Date
    }

    private var files: [String: File] = [:]
    private let workingWindow: TimeInterval
    private let now: () -> Date
    private let calendar: Calendar

    public init(workingWindow: TimeInterval = 30, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.workingWindow = workingWindow
        self.now = now
        self.calendar = calendar
    }

    /// `fileID` is the transcript's file name (the session id); `modified` is when it was last written.
    public func ingest(fileID: String, folder: String? = nil, title: String? = nil, lines: [TranscriptLine], modified: Date) {
        var file = files[fileID] ?? File(cwd: nil, title: nil, lastWrite: modified, burstStart: modified)

        // A new stretch of work begins when the transcript had been quiet for longer than the window.
        if modified.timeIntervalSince(file.lastWrite) > workingWindow { file.burstStart = modified }
        file.lastWrite = max(file.lastWrite, modified)

        if let folder { file.cwd = folder }
        if let title { file.title = title }
        for line in lines {
            if let cwd = line.cwd { file.cwd = cwd }
            if let id = line.messageID {
                file.messages[id] = Message(input: line.inputTokens, output: line.outputTokens, time: line.timestamp)
            }
        }
        files[fileID] = file
    }

    public func snapshot() -> ClaudeSnapshot {
        let current = now()
        let startOfToday = calendar.startOfDay(for: current)
        let dayAgo = current.addingTimeInterval(-24 * 3600)

        var sessions: [ClaudeSession] = []
        var working: [ClaudeSession] = []
        var burstStarts: [Date] = []
        var today = 0

        for (id, file) in files {
            // Everything shown is "today": transcripts are huge, and today is what people ask about.
            let todays = file.messages.values.filter { ($0.time ?? .distantPast) >= startOfToday }
            today += todays.reduce(0) { $0 + $1.input + $1.output }
            guard file.lastWrite >= dayAgo else { continue }
            let session = ClaudeSession(
                id: id,
                project: file.cwd.map { ($0 as NSString).lastPathComponent } ?? "Claude",
                lastActivity: file.lastWrite,
                inputTokens: todays.reduce(0) { $0 + $1.input },
                outputTokens: todays.reduce(0) { $0 + $1.output },
                title: file.title, cwd: file.cwd)
            sessions.append(session)
            if current.timeIntervalSince(file.lastWrite) < workingWindow {
                working.append(session)
                burstStarts.append(file.burstStart)
            }
        }

        let byRecency: (ClaudeSession, ClaudeSession) -> Bool = { $0.lastActivity > $1.lastActivity }
        return ClaudeSnapshot(sessions: sessions.sorted(by: byRecency), working: working.sorted(by: byRecency),
                              tokensToday: today, workingSince: burstStarts.min())
    }

    /// When the snapshot will next change on its own (a session going quiet), if it will.
    public func nextExpiry() -> Date? {
        let current = now()
        return files.values.map { $0.lastWrite.addingTimeInterval(workingWindow) }.filter { $0 > current }.min()
    }
}
