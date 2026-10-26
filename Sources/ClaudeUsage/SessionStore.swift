import Foundation

/// Folds transcript lines into a snapshot. Pure state, no file access, so it is easy to test.
public final class SessionStore {
    private struct Message { var input: Int; var output: Int; var time: Date? }

    private struct File {
        var cwd: String?
        var title: String?
        var turn: Turn?
        var turnAt: Date?
        var messages: [String: Message] = [:]   // by message id: streamed updates replace, never double count
        var lastWrite: Date
        var burstStart: Date
    }

    private var files: [String: File] = [:]
    /// Sessions that Claude Code itself reports as idle (or whose process is gone). A transcript can still be
    /// touched while a chat sits open, so a recent write alone must not read as "working" for these.
    private var idleSessions: Set<String> = []
    private let workingWindow: TimeInterval
    private let now: () -> Date
    private let calendar: Calendar

    /// A tool call left unanswered this long is probably a permission prompt rather than a slow tool.
    private let approvalDelay: TimeInterval = 20
    private let finishedDelay: TimeInterval = 2
    /// How long a finished chat, or an unanswered tool call, keeps asking for attention.
    private let finishedLinger: TimeInterval = 10 * 60, approvalLinger: TimeInterval = 60 * 60

    public init(workingWindow: TimeInterval = 30, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.workingWindow = workingWindow
        self.now = now
        self.calendar = calendar
    }

    public func setQuiet(_ ids: Set<String>) { idleSessions = ids }

    /// `fileID` is the transcript's file name (the session id); `modified` is when it was last written.
    public func ingest(fileID: String, folder: String? = nil, title: String? = nil, lines: [TranscriptLine], modified: Date) {
        var file = files[fileID] ?? File(cwd: nil, title: nil, turn: nil, turnAt: nil, lastWrite: modified, burstStart: modified)

        // A new stretch of work begins when the transcript had been quiet for longer than the window.
        if modified.timeIntervalSince(file.lastWrite) > workingWindow { file.burstStart = modified }
        file.lastWrite = max(file.lastWrite, modified)

        if let folder { file.cwd = folder }
        if let title { file.title = title }
        for line in lines {
            if let cwd = line.cwd { file.cwd = cwd }
            if let turn = line.turn, turn != .other || file.turn == nil { file.turn = turn; file.turnAt = modified }
            if let id = line.messageID {
                file.messages[id] = Message(input: line.inputTokens, output: line.outputTokens, time: line.timestamp)
            }
        }
        files[fileID] = file
    }

    /// How long a silent transcript still counts as working. Claude writes nothing while it generates a long
    /// answer or a big tool call, so after a prompt or tool result the quiet can last minutes.
    private func activeWindow(after turn: Turn?) -> TimeInterval {
        switch turn {
        case .user: return max(workingWindow, 180)
        case .other: return max(workingWindow, 120)
        case .toolUse: return max(workingWindow, approvalDelay)
        case .ended, nil: return workingWindow
        }
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
            let quiet = current.timeIntervalSince(file.turnAt ?? file.lastWrite)
            let attention: Attention? =
                file.turn == .toolUse && quiet >= approvalDelay && quiet < approvalLinger ? .approval
                : file.turn == .ended && quiet >= finishedDelay && quiet < finishedLinger ? .finished : nil
            let session = ClaudeSession(
                id: id,
                project: file.cwd.map { ($0 as NSString).lastPathComponent } ?? "Claude",
                lastActivity: file.lastWrite,
                inputTokens: todays.reduce(0) { $0 + $1.input },
                outputTokens: todays.reduce(0) { $0 + $1.output },
                title: file.title, cwd: file.cwd, attention: attention)
            sessions.append(session)
            if attention == nil, !idleSessions.contains(id), current.timeIntervalSince(file.lastWrite) < activeWindow(after: file.turn) {
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
        var moments: [Date] = []
        for file in files.values {
            moments.append(file.lastWrite.addingTimeInterval(activeWindow(after: file.turn)))
            guard let turnAt = file.turnAt else { continue }
            moments += [finishedDelay, approvalDelay, finishedLinger, approvalLinger].map { turnAt.addingTimeInterval($0) }
        }
        return moments.filter { $0 > current }.min()
    }
}
