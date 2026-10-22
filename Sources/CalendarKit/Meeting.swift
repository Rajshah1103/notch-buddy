import Foundation

public struct Meeting: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let calendarName: String
    /// The calendar's colour as red, green, blue in 0...1, for a small dot beside the title.
    public let calendarColor: [Double]
    public let joinURL: URL?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, calendarName: String,
                calendarColor: [Double] = [0.5, 0.5, 0.5], joinURL: URL? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarName = calendarName
        self.calendarColor = calendarColor
        self.joinURL = joinURL
    }
}

/// Finds the video-call link in an invite's location, notes or URL. Only well-known services are matched,
/// so an unrelated link in the notes is never mistaken for the call.
public enum MeetingLinks {
    private static let patterns = [
        #"https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}"#,
        #"https://meet\.google\.com/lookup/[A-Za-z0-9_-]+"#,
        #"https://[A-Za-z0-9.-]*zoom\.us/(?:j|my|w)/[^\s<>")\]]+"#,
        #"https://teams\.microsoft\.com/l/meetup-join/[^\s<>")\]]+"#,
        #"https://teams\.live\.com/meet/[^\s<>")\]]+"#,
        #"https://[A-Za-z0-9.-]*webex\.com/(?:meet|join|[A-Za-z0-9.-]+/j\.php)[^\s<>")\]]*"#,
        #"https://[A-Za-z0-9.-]*\.whereby\.com/[^\s<>")\]]+"#,
    ]

    /// The first call link found, searching the texts in the order given.
    public static func extract(from texts: [String?]) -> URL? {
        for text in texts.compactMap({ $0 }) {
            for pattern in patterns {
                if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                    let found = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
                    if let url = URL(string: found) { return url }
                }
            }
        }
        return nil
    }
}

public enum Schedule {
    public struct Day: Equatable, Sendable {
        /// In progress right now, soonest-started first.
        public var current: [Meeting]
        /// The next one to start.
        public var next: Meeting?
        /// Everything still ahead today and anything in progress, in start order.
        public var remaining: [Meeting]
        public var allDay: [Meeting]

        public init(current: [Meeting], next: Meeting?, remaining: [Meeting], allDay: [Meeting]) {
            self.current = current; self.next = next; self.remaining = remaining; self.allDay = allDay
        }
    }

    /// Sorts out what matters now. All-day events (birthdays, holidays) are kept apart: they are never
    /// "the next meeting".
    public static func day(_ meetings: [Meeting], now: Date, calendar: Calendar = .current) -> Day {
        let timed = meetings.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        let endOfDay = calendar.startOfDay(for: now).addingTimeInterval(24 * 3600)
        let current = timed.filter { $0.start <= now && $0.end > now }
        let ahead = timed.filter { $0.start > now }
        return Day(current: current,
                   next: ahead.first,
                   remaining: (current + ahead.filter { $0.start < endOfDay }),
                   allDay: meetings.filter(\.isAllDay))
    }

    /// "now", "in 4 min", "in 1 h 5 min": how far away a start time is.
    public static func countdown(to start: Date, from now: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        switch minutes {
        case ..<1: return "now"
        case 1..<60: return "in \(minutes) min"
        default:
            let hours = minutes / 60, rest = minutes % 60
            return rest == 0 ? "in \(hours) h" : "in \(hours) h \(rest) min"
        }
    }
}
