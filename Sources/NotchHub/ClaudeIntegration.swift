import NotchCore
import SwiftUI

/// Claude Code activity as a notch integration. Its live ears are special to Claude (they widen
/// the collapsed notch), so the app delegate still wires those directly.
@MainActor
final class ClaudeIntegration: NotchIntegration {
    let id = "claude"
    let name = "Claude Code"
    let model: ClaudeModel
    private let settings: AppSettings

    init(model: ClaudeModel, settings: AppSettings? = nil) {
        self.model = model
        self.settings = settings ?? .shared
    }

    var isEnabled: Bool { settings.showClaudeActivity }

    func start() { model.start() }
    func stop() { model.stop() }
    func refresh() {}                 // event driven: nothing to ask for

    func chip(isOpen: Bool, action: @escaping () -> Void) -> AnyView {
        AnyView(ClaudeChip(model: model, isOpen: isOpen, action: action))
    }

    func panel(notch: NotchState) -> AnyView {
        AnyView(ClaudePanel(model: model))
    }
}
