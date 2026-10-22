import CalendarKit
import NotchCore
import SwiftUI

struct CalendarChip: View {
    @ObservedObject var model: CalendarModel
    let isOpen: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(spacing: 5) {
                    Image(systemName: "calendar").font(.system(size: 10, weight: .bold))
                    if let text = label(at: context.date) {
                        Text(text).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    } else if isOpen {
                        Text("Calendar").font(.system(size: 11, weight: .medium))
                    }
                }
            }
            .foregroundStyle(isOpen ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(Capsule().fill(isOpen ? Theme.fillSelected : (hovering ? Theme.fillHover : Theme.fillQuiet)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerHover { hovering = $0 }
        .help("Upcoming meetings")
        .accessibilityLabel("Calendar")
        .accessibilityHint("Shows your next meetings with a button to join")
    }

    /// "Standup in 4 min" would not fit; the countdown alone does, and only when a meeting is near.
    private func label(at now: Date) -> String? {
        switch model.state {
        case .needsAccess, .denied: return isOpen ? nil : "Set up"
        default: break
        }
        guard let next = model.day(now: now)?.next, next.start.timeIntervalSince(now) < 3 * 3_600 else { return nil }
        return Schedule.countdown(to: next.start, from: now).replacingOccurrences(of: "in ", with: "")
    }
}

struct CalendarPanel: View {
    @ObservedObject var model: CalendarModel
    let dismiss: () -> Void

    var body: some View {
        switch model.state {
        case .idle:
            Text("Loading…").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity).padding(.top, 90)
        case .needsAccess:
            Message(symbol: "calendar", title: "Show your next meeting",
                    detail: "Notch Hub reads the events already in your Calendar app, including Google and iCloud accounts. Nothing leaves this Mac.",
                    button: "Allow Calendar Access") { model.requestAccess() }
        case .denied:
            Message(symbol: "calendar.badge.exclamationmark", title: "Calendar access is off",
                    detail: "Turn on Notch Hub under Privacy & Security, Calendars.",
                    button: "Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") { NSWorkspace.shared.open(url) }
            }
        case .ready:
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Agenda(day: model.day(now: context.date) ?? .init(current: [], next: nil, remaining: [], allDay: []),
                       now: context.date, join: { model.join($0); dismiss() })
            }
        }
    }
}

private struct Message: View {
    let symbol: String, title: String, detail: String, button: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(Theme.textSecondary)
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 440)
            Button(button, action: action).controlSize(.regular).padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }
}

private struct Agenda: View {
    let day: Schedule.Day
    let now: Date
    let join: (Meeting) -> Void

    /// What fits without scrolling: the rest is summarised.
    private let capacity = 7

    var body: some View {
        let rows = day.remaining
        VStack(alignment: .leading, spacing: 2) {
            if rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.system(size: 28, weight: .light)).foregroundStyle(Theme.textSecondary)
                    Text("No more meetings today").font(.system(size: 15, weight: .semibold))
                    if !day.allDay.isEmpty {
                        Text(day.allDay.map(\.title).joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity).padding(.top, 70)
            } else {
                ForEach(rows.prefix(capacity)) { MeetingRow(meeting: $0, now: now, isNext: $0.id == day.next?.id, join: join) }
                if rows.count > capacity {
                    Text("+\(rows.count - capacity) more").font(.system(size: 11)).foregroundStyle(Theme.textSecondary).padding(.leading, 12).padding(.top, 4)
                }
                if !day.allDay.isEmpty {
                    Text(day.allDay.map(\.title).joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).padding(.leading, 12).padding(.top, 6)
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct MeetingRow: View {
    let meeting: Meeting
    let now: Date
    let isNext: Bool
    let join: (Meeting) -> Void
    @State private var hovering = false

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    var body: some View {
        let live = meeting.start <= now && meeting.end > now
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title).font(.system(size: 13, weight: isNext || live ? .semibold : .regular)).lineLimit(1)
                Text("\(Self.time.string(from: meeting.start)) – \(Self.time.string(from: meeting.end)) · \(live ? "now" : Schedule.countdown(to: meeting.start, from: now))")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if meeting.joinURL != nil {
                Button("Join") { join(meeting) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .tint(isNext || live ? Theme.accent : .gray)
            }
        }
        .padding(.horizontal, 12).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Theme.fillHover : (isNext ? Theme.fillQuiet : .clear)))
        .pointerHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        guard meeting.calendarColor.count == 3 else { return .gray }
        return Color(red: meeting.calendarColor[0], green: meeting.calendarColor[1], blue: meeting.calendarColor[2])
    }
}
