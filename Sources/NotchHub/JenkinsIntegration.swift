import NotchCore
import SwiftUI

@MainActor
final class JenkinsIntegration: NotchIntegration {
    let id = "jenkins"
    let name = "Jenkins"
    let model: JenkinsModel
    private let settings: AppSettings

    init(model: JenkinsModel, settings: AppSettings? = nil) {
        self.model = model
        self.settings = settings ?? .shared
    }

    var isEnabled: Bool { settings.showJenkins }

    /// Also called when settings change, so a new address or token takes effect straight away.
    func start() { model.start(settings: settings) }
    func stop() { model.stop() }
    func settingsChanged() { model.start(settings: settings) }   // no-op unless the address, user, token or filter changed
    func refresh() { model.refresh() }

    func chip(isOpen: Bool, action: @escaping () -> Void) -> AnyView {
        AnyView(JenkinsChip(model: model, isOpen: isOpen, action: action))
    }

    func panel(notch: NotchState) -> AnyView {
        AnyView(JenkinsPanel(model: model, dismiss: { notch.collapse() }))
    }
}
