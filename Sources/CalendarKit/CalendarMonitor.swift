import AppKit
import EventKit

/// Reads today's and tomorrow's events from the Calendar app's database, which already holds whatever
/// accounts are set up in System Settings (Google, iCloud, Exchange). Access is requested only when the
/// user presses the button for it, never on its own.
// All mutable state is touched only on the main queue, which is what makes sharing the object safe.
public final class CalendarMonitor: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case needsAccess
        case denied
        case ready([Meeting])
    }

    public var onChange: (@Sendable (State) -> Void)?

    private let store = EKEventStore()
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var last = State.idle

    public init() {}

    public static var hasAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .fullAccess || status == .authorized
    }

    public func start() {
        DispatchQueue.main.async { [self] in
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                self?.reload()
            }
            // Reloading is cheap, and picks up events added by other devices and meetings that ended.
            timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.reload() }
            reload()
        }
    }

    public func stop() {
        DispatchQueue.main.async { [self] in
            timer?.invalidate(); timer = nil
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            publish(.idle)
        }
    }

    /// Shows macOS's own permission prompt. Call it from a button the user pressed.
    public func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async { granted ? self?.reload() : self?.publish(.denied) }
        }
    }

    public func reload() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: publish(.needsAccess)
        case .fullAccess, .authorized: publish(.ready(fetch()))
        default: publish(.denied)                 // denied, restricted, or write-only
        }
    }

    private func fetch() -> [Meeting] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = start.addingTimeInterval(2 * 24 * 3600)           // today and tomorrow
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap { event -> Meeting? in
            // Skip what you have said no to.
            if let me = event.attendees?.first(where: \.isCurrentUser), me.participantStatus == .declined { return nil }
            let color = (event.calendar.color ?? .gray).usingColorSpace(.sRGB)
            return Meeting(
                id: "\(event.eventIdentifier ?? UUID().uuidString)@\(Int(event.startDate.timeIntervalSince1970))",
                title: event.title ?? "Untitled",
                start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                calendarName: event.calendar.title,
                calendarColor: [color?.redComponent ?? 0.5, color?.greenComponent ?? 0.5, color?.blueComponent ?? 0.5].map(Double.init),
                joinURL: MeetingLinks.extract(from: [event.url?.absoluteString, event.location, event.notes]))
        }
    }

    private func publish(_ new: State) {
        guard new != last else { return }
        last = new
        onChange?(new)
    }
}
