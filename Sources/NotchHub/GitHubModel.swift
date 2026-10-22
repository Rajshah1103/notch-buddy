import GitHubKit
import SwiftUI

@MainActor
final class GitHubModel: ObservableObject {
    /// The last good read; kept while a refresh fails so the panel never goes blank.
    @Published private(set) var snapshot: GitHubSnapshot?
    @Published private(set) var error: GitHubError?
    @Published private(set) var needsToken = false
    @Published private(set) var source: GitHubToken.Source?

    private let monitor = GitHubMonitor()

    func start(useCommandLine: Bool) {
        monitor.allowCommandLine = useCommandLine
        monitor.onChange = { [weak self] state in
            MainActor.assumeIsolated { self?.apply(state) }
        }
        monitor.start()
    }

    func stop() {
        monitor.stop()
        monitor.onChange = nil
        snapshot = nil; error = nil; needsToken = false
    }

    func refresh() { monitor.refresh() }

    func connect(token: String, useCommandLine: Bool) {
        GitHubToken.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
        monitor.stop()
        start(useCommandLine: useCommandLine)
    }

    func disconnect(useCommandLine: Bool) {
        GitHubToken.clear()
        monitor.stop()
        snapshot = nil
        start(useCommandLine: useCommandLine)
    }

    private func apply(_ state: GitHubMonitor.State) {
        switch state {
        case .idle: break
        case .needsToken: needsToken = true; error = nil; snapshot = nil
        case .ready(let new, let tokenSource): needsToken = false; error = nil; snapshot = new; source = tokenSource
        case .failed(let failure): needsToken = false; error = failure
        }
    }

    /// For the snapshot tool.
    func loadForPreview(_ snapshot: GitHubSnapshot?, needsToken: Bool = false) {
        self.snapshot = snapshot
        self.needsToken = needsToken
    }
}
