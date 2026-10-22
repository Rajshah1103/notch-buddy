import NotchCore
import SwiftUI

@MainActor
final class GitHubIntegration: NotchIntegration {
    let id = "github"
    let name = "GitHub"
    let model: GitHubModel
    private let settings: AppSettings

    init(model: GitHubModel, settings: AppSettings? = nil) {
        self.model = model
        self.settings = settings ?? .shared
    }

    var isEnabled: Bool { settings.showGitHub }

    private var startedWithCommandLine: Bool?

    func start() {
        startedWithCommandLine = settings.githubUsesCommandLine
        model.start(useCommandLine: settings.githubUsesCommandLine)
    }

    /// Switching the command line fallback on or off needs a fresh start to pick a new token source.
    func settingsChanged() {
        guard startedWithCommandLine != settings.githubUsesCommandLine else { return }
        model.stop()
        start()
    }
    func stop() { model.stop() }
    func refresh() { model.refresh() }

    func chip(isOpen: Bool, action: @escaping () -> Void) -> AnyView {
        AnyView(GitHubChip(model: model, isOpen: isOpen, action: action))
    }

    func panel(notch: NotchState) -> AnyView {
        AnyView(GitHubPanel(model: model, settings: settings, notch: notch))
    }
}
