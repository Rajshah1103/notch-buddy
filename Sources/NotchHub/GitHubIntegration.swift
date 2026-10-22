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

    func start() { model.start(useCommandLine: settings.githubUsesCommandLine) }
    func stop() { model.stop() }
    func refresh() { model.refresh() }

    func chip(isOpen: Bool, action: @escaping () -> Void) -> AnyView {
        AnyView(GitHubChip(model: model, isOpen: isOpen, action: action))
    }

    func panel(notch: NotchState) -> AnyView {
        AnyView(GitHubPanel(model: model, settings: settings, notch: notch))
    }
}
