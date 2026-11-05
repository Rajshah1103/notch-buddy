import Combine
import NotchCore
import SwiftUI

/// Something that shows up in the notch beyond windows: a status chip in the open notch's header,
/// and a panel that replaces the app list when the chip is opened. Claude and GitHub are the first
/// two; anything else (CI, chat, mail) is another conformance, with no change to the notch itself.
@MainActor
protocol NotchIntegration: AnyObject {
    /// Stable identifier, used for settings and to remember which panel is open.
    var id: String { get }
    var name: String { get }
    /// Whether the user has it turned on in Settings.
    var isEnabled: Bool { get }

    /// Begin background work. Called when the integration is (re)enabled.
    func start()
    /// Stop all background work. Called when it is turned off.
    func stop()
    /// The notch is opening; refresh if the data is old.
    func refresh()

    /// A setting changed while this is running (for example an address or token). Default: nothing.
    func settingsChanged()

    func chip(isOpen: Bool, action: @escaping () -> Void) -> AnyView
    /// `notch` lets a panel close the notch (rows that open something elsewhere) or ask for the
    /// keyboard (`setTyping`) when it has a text field.
    func panel(notch: NotchState) -> AnyView
}

extension NotchIntegration {
    func settingsChanged() {}
}

/// The set of integrations, kept in step with Settings.
@MainActor
final class IntegrationHub: ObservableObject {
    private(set) var integrations: [any NotchIntegration]
    private var running: Set<String> = []
    private var settingsSubscription: AnyCancellable?

    init(integrations: [any NotchIntegration], settings: AppSettings? = nil) {
        let settings = settings ?? .shared
        self.integrations = integrations
        // Settings changes (turning one off, changing a token) re-evaluate what runs and what shows.
        settingsSubscription = settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.apply() }
        }
    }

    var visible: [any NotchIntegration] { integrations.filter(\.isEnabled) }

    /// Adds integrations found while running (a connector folder that was just added). The "+" stays last.
    func append(_ more: [any NotchIntegration]) {
        let known = Set(integrations.map(\.id))
        let fresh = more.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return }
        let last = integrations.firstIndex { $0.id == ConnectIntegration.id } ?? integrations.endIndex
        integrations.insert(contentsOf: fresh, at: last)
        apply()
    }

    func integration(_ id: String) -> (any NotchIntegration)? { visible.first { $0.id == id } }

    /// Starts what is enabled and stops what is not.
    func apply() {
        for integration in integrations {
            if integration.isEnabled, !running.contains(integration.id) {
                running.insert(integration.id)
                integration.start()
            } else if !integration.isEnabled, running.contains(integration.id) {
                running.remove(integration.id)
                integration.stop()
            } else if integration.isEnabled {
                integration.settingsChanged()
            }
        }
        objectWillChange.send()
    }

    func refresh() { visible.forEach { $0.refresh() } }
}

enum RelativeTime {
    /// "just now", "5m ago", "3h ago", "2d ago".
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3_600: return "\(seconds / 60)m ago"
        case ..<86_400: return "\(seconds / 3_600)h ago"
        default: return "\(seconds / 86_400)d ago"
        }
    }
}
