import ClaudeUsage
import Foundation

@MainActor
final class ClaudeModel: ObservableObject {
    @Published private(set) var snapshot = ClaudeSnapshot.idle
    /// Chats waiting on you (approval, or a finished turn) that you have not opened since.
    @Published private(set) var needsYou: [ClaudeSession] = []
    private var seen: [String: Date] = [:]

    /// Called when Claude starts or stops working, so the notch can show or hide its live ears.
    var onWorkingChange: ((Bool) -> Void)?

    private let monitor = ClaudeUsageMonitor()

    func start() {
        monitor.onChange = { [weak self] snapshot in
            MainActor.assumeIsolated { self?.apply(snapshot) }
        }
        monitor.start()
    }

    /// Turned off in Settings: stop watching and clear the live activity.
    func stop() {
        monitor.stop()
        monitor.onChange = nil
        apply(.idle)
    }

    private func apply(_ new: ClaudeSnapshot) {
        let wasWorking = snapshot.isWorking
        snapshot = new
        refreshNeedsYou()
        if wasWorking != new.isWorking { onWorkingChange?(new.isWorking) }
    }

    /// You looked at this chat: stop asking until it does something new.
    func markSeen(_ session: ClaudeSession) {
        seen[session.id] = Date()
        refreshNeedsYou()
    }

    private func refreshNeedsYou() {
        let list = snapshot.sessions.filter { $0.attention != nil && (seen[$0.id] ?? .distantPast) < $0.lastActivity }
        if list != needsYou { needsYou = list }
    }

    /// For the snapshot tool.
    func loadForPreview(_ snapshot: ClaudeSnapshot) {
        self.snapshot = snapshot
        refreshNeedsYou()
    }
}
