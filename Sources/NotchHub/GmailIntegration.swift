import NotchCore
import SwiftUI

@MainActor
final class GmailIntegration: NotchIntegration {
    let id = "gmail"
    let name = "Gmail"
    let model: GmailModel
    private let settings: AppSettings

    init(model: GmailModel, settings: AppSettings? = nil) {
        self.model = model
        self.settings = settings ?? .shared
    }

    var isEnabled: Bool { settings.showGmail }

    func start() { model.start() }
    func stop() { model.stop() }
    func refresh() { model.refresh() }

    func chip(isOpen: Bool, action: @escaping () -> Void) -> AnyView {
        AnyView(GmailChip(model: model, isOpen: isOpen, action: action))
    }

    func panel(notch: NotchState) -> AnyView {
        AnyView(GmailPanel(model: model, notch: notch))
    }
}
