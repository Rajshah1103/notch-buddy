import NotchCore
import SwiftUI

@MainActor
final class CalendarIntegration: NotchIntegration {
    let id = "calendar"
    let name = "Calendar"
    let model: CalendarModel
    private let settings: AppSettings

    init(model: CalendarModel, settings: AppSettings? = nil) {
        self.model = model
        self.settings = settings ?? .shared
    }

    var isEnabled: Bool { settings.showCalendar }

    func start() { model.start() }
    func stop() { model.stop() }
    func refresh() { model.refresh() }

    func chip(isOpen: Bool, action: @escaping () -> Void) -> AnyView {
        AnyView(CalendarChip(model: model, isOpen: isOpen, action: action))
    }

    func panel(notch: NotchState) -> AnyView {
        AnyView(CalendarPanel(model: model, dismiss: { notch.collapse() }))
    }
}
