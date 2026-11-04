import ConnectorKit
import Foundation

/// Sessions of AI harnesses other than Claude Code (which is read from its own files), fed by `notchhub agent`.
/// Event driven: a timer is armed only for the next expiry.
@MainActor
final class AgentTracker: ObservableObject {
    @Published private(set) var board = AgentBoard()
    private var expiry: Timer?

    func apply(_ event: Message.AgentEvent) {
        if board.apply(event, now: Date()) { objectWillChange.send() }
        arm()
    }

    private func arm() {
        expiry?.invalidate(); expiry = nil
        guard let next = board.nextExpiry else { return }
        expiry = Timer.scheduledTimer(withTimeInterval: max(next.timeIntervalSinceNow, 1), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.board.prune(now: Date()) { self.objectWillChange.send() }
                self.arm()
            }
        }
    }

    /// "Codex", "Gemini": a harness id made readable.
    nonisolated static func title(_ harness: String) -> String {
        harness.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
            .split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
