import ClaudeUsage
import Foundation

@MainActor
final class ClaudeModel: ObservableObject {
    @Published private(set) var snapshot = ClaudeSnapshot.idle

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
        if wasWorking != new.isWorking { onWorkingChange?(new.isWorking) }
    }

    /// For the snapshot tool.
    func loadForPreview(_ snapshot: ClaudeSnapshot) { self.snapshot = snapshot }
}
