import ClaudeUsage
import Foundation

@MainActor
final class ClaudeModel: ObservableObject {
    @Published private(set) var snapshot = ClaudeSnapshot.idle
    /// Chats waiting on you (approval, or a finished turn) that you have not opened since.
    @Published private(set) var needsYou: [ClaudeSession] = []
    private var seen: [String: Date] = [:]
    /// Daily and hourly token use over the last 90 days, and what it says about you.
    @Published private(set) var stats = UsageStats(history: .empty)

    /// Called when Claude starts or stops working, so the notch can show or hide its live ears.
    var onWorkingChange: ((Bool) -> Void)?

    private let monitor = ClaudeUsageMonitor()
    private let history = UsageHistoryScanner()

    func start() {
        monitor.onChange = { [weak self] snapshot in
            MainActor.assumeIsolated { self?.apply(snapshot) }
        }
        monitor.start()
        history.onChange = { [weak self] history in
            DispatchQueue.main.async { self?.stats = UsageStats(history: history) }
        }
        // The first pass reads a quarter's transcripts; let the launch settle before it starts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [history] in history.start() }
    }

    /// The panel opened: pick up anything written since the last pass.
    func refreshHistory() { history.refresh() }

    /// Turned off in Settings: stop watching and clear the live activity.
    func stop() {
        monitor.stop()
        history.stop()
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
    func loadForPreview(_ snapshot: ClaudeSnapshot, history: UsageHistory = .empty) {
        self.snapshot = snapshot
        self.stats = UsageStats(history: history)
        refreshNeedsYou()
    }
}
