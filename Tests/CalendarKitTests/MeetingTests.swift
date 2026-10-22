import Foundation
import Testing
@testable import CalendarKit

struct MeetingLinkTests {
    private func link(_ texts: String?...) -> String? { MeetingLinks.extract(from: texts)?.absoluteString }

    @Test func findsTheCommonServices() {
        #expect(link("Join: https://meet.google.com/abc-defg-hij?authuser=0") == "https://meet.google.com/abc-defg-hij")
        #expect(link("https://acme.zoom.us/j/1234567890?pwd=AbC123") == "https://acme.zoom.us/j/1234567890?pwd=AbC123")
        #expect(link("<a href=\"https://us02web.zoom.us/j/99\">Join</a>") == "https://us02web.zoom.us/j/99")
        #expect(link("https://acme.webex.com/meet/raj") == "https://acme.webex.com/meet/raj")
        #expect(link("https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0?context=1")?.hasPrefix("https://teams.microsoft.com/l/meetup-join/") == true)
    }

    @Test func ignoresOrdinaryLinksAndLookAlikeHosts() {
        #expect(link(nil, "Room 4B", "see https://example.com/agenda.pdf") == nil)
        #expect(link("https://evil-zoom.us.example.com/j/1") == nil)
    }

    @Test func searchesEveryFieldAndTrimsPunctuation() {
        #expect(link("notes", "location: https://meet.google.com/xyz-abcd-efg.") == "https://meet.google.com/xyz-abcd-efg")
    }
}

struct ScheduleTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func meeting(_ id: String, _ startMinutes: Double, _ length: Double, allDay: Bool = false) -> Meeting {
        Meeting(id: id, title: id, start: now.addingTimeInterval(startMinutes * 60),
                end: now.addingTimeInterval((startMinutes + length) * 60), isAllDay: allDay, calendarName: "Work")
    }

    @Test func sortsOutWhatMattersNow() {
        let day = Schedule.day([meeting("later", 90, 30), meeting("birthday", -300, 1_440, allDay: true),
                                meeting("standup", 10, 15), meeting("running", -20, 60), meeting("past", -120, 30)],
                               now: now, calendar: Calendar(identifier: .gregorian))
        #expect(day.current.map(\.id) == ["running"])
        #expect(day.next?.id == "standup")
        #expect(day.allDay.map(\.id) == ["birthday"])
        #expect(day.remaining.map(\.id) == ["running", "standup", "later"])
    }

    @Test func countdownsReadNaturally() {
        #expect(Schedule.countdown(to: now.addingTimeInterval(30), from: now) == "in 1 min")
        #expect(Schedule.countdown(to: now.addingTimeInterval(240), from: now) == "in 4 min")
        #expect(Schedule.countdown(to: now.addingTimeInterval(65 * 60), from: now) == "in 1 h 5 min")
        #expect(Schedule.countdown(to: now.addingTimeInterval(7_200), from: now) == "in 2 h")
        #expect(Schedule.countdown(to: now.addingTimeInterval(-5), from: now) == "now")
    }
}
