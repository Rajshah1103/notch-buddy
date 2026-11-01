import AppKit
import CalendarKit
import Combine

@MainActor
final class CalendarModel: ObservableObject {
    @Published private(set) var state = CalendarMonitor.State.idle

    private let monitor = CalendarMonitor()

    init() {
        monitor.onChange = { [weak self] state in
            DispatchQueue.main.async { self?.state = state }
        }
    }

    func loadForPreview(_ meetings: [Meeting]) { state = .ready(meetings) }

    func start() { monitor.start() }
    func stop() { monitor.stop() }
    func refresh() { if CalendarMonitor.hasAccess { monitor.reload() } }
    func requestAccess() { monitor.requestAccess() }

    func day(now: Date = Date()) -> Schedule.Day? {
        guard case .ready(let meetings) = state else { return nil }
        return Schedule.day(meetings, now: now)
    }

    func join(_ meeting: Meeting) {
        guard let url = meeting.joinURL else { return }
        LinkOpener.open(url, for: "calendar")
    }
}
