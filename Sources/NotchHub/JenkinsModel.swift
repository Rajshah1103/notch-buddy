import Foundation
import JenkinsKit

@MainActor
final class JenkinsModel: ObservableObject {
    /// The last good read; kept while the server is unreachable so the panel never goes blank.
    @Published private(set) var snapshot: JenkinsSnapshot?
    @Published private(set) var error: JenkinsError?
    @Published private(set) var isConfigured = false

    private let monitor = JenkinsMonitor()

    /// The settings, as a config, or nil when something is missing. Reads the Keychain, so call it
    /// off the main thread (a Keychain read can block).
    nonisolated static func config(address: String, user: String, filter: String) -> JenkinsConfig? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespaces)),
              url.scheme?.hasPrefix("http") == true, url.host != nil,
              !user.isEmpty, let token = JenkinsToken.stored()
        else { return nil }
        let filters = filter.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return JenkinsConfig(baseURL: url, username: user, token: token, filters: filters)
    }

    func start(settings: AppSettings) {
        let (address, user, filter) = (settings.jenkinsURL, settings.jenkinsUser, settings.jenkinsFilter)
        monitor.onChange = { [weak self] state in
            Task { @MainActor in self?.apply(state) }
        }
        let model = self      // held only for the length of this one short task
        Task.detached {
            let config = Self.config(address: address, user: user, filter: filter)
            await model.finishStart(config)
        }
    }

    private func finishStart(_ config: JenkinsConfig?) {
        isConfigured = config != nil
        monitor.configure(config)
    }

    func stop() {
        monitor.configure(nil)
        monitor.onChange = nil
        snapshot = nil; error = nil; isConfigured = false
    }

    func refresh() { monitor.refresh() }

    private func apply(_ state: JenkinsMonitor.State) {
        switch state {
        case .idle: break
        case .ready(let new): snapshot = new; error = nil
        case .failed(let failure): error = failure
        }
    }

    /// For the snapshot tool.
    func loadForPreview(_ snapshot: JenkinsSnapshot?) { self.snapshot = snapshot; isConfigured = true }
}
