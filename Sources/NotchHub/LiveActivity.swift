import BuddyKit
import CalendarKit
import ClaudeUsage
import Combine
import JenkinsKit
import NotchCore
import SwiftUI

enum LiveLayout {
    /// How far the collapsed notch widens on each side while something is live.
    static let extra: CGFloat = 56
}

/// What the collapsed notch shows, if anything. One thing at a time, by priority: Claude working,
/// else a meeting about to start, else a running Jenkins build. More sources can slot in here later.
@MainActor
final class LiveActivityModel: ObservableObject {
    enum Activity: Equatable {
        case claude(since: Date?, sessions: Int)
        case waiting(count: Int, approval: Bool)
        case meeting(title: String, start: Date)
        case build(name: String, progress: Double?, count: Int)
        case none
    }

    @Published private(set) var current = Activity.none
    var onActiveChange: ((Bool) -> Void)?

    private var subscriptions = Set<AnyCancellable>()
    private var claudeActivity = Activity.none
    private var waitingActivity = Activity.none
    private var buildActivity = Activity.none
    private var meetingActivity = Activity.none
    private var meetings: [Meeting] = []
    private var tick: Timer?
    /// How early a meeting claims the collapsed notch, and how long after its start it stays.
    private static let lead: TimeInterval = 5 * 60, linger: TimeInterval = 60

    init(claude: ClaudeModel, jenkins: JenkinsModel, calendar: CalendarModel) {
        calendar.$state
            .sink { [weak self] state in
                if case .ready(let list) = state { self?.meetings = list.filter { !$0.isAllDay } } else { self?.meetings = [] }
                self?.recompute()
            }
            .store(in: &subscriptions)
        // The window around a meeting opens and closes with the clock, not with any data change.
        tick = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        }

        claude.$snapshot
            .sink { [weak self] snapshot in
                self?.claudeActivity = snapshot.isWorking ? .claude(since: snapshot.workingSince, sessions: snapshot.working.count) : .none
                self?.recompute()
            }
            .store(in: &subscriptions)
        claude.$needsYou
            .sink { [weak self] list in
                self?.waitingActivity = list.isEmpty ? .none
                    : .waiting(count: list.count, approval: list.contains { $0.attention == .approval })
                self?.recompute()
            }
            .store(in: &subscriptions)
        jenkins.$snapshot
            .sink { [weak self] snapshot in
                let running = snapshot?.running ?? []
                // Show the furthest-along build: it is the next one to finish.
                let lead = running.max { progress($0) < progress($1) }
                self?.buildActivity = lead.map { job in
                    guard case .running(let p) = job.state else { return .none }
                    return .build(name: job.name, progress: p, count: running.count)
                } ?? .none
                self?.recompute()
            }
            .store(in: &subscriptions)
    }

    /// Several sources can change in one turn of the run loop (Claude's snapshot, then who needs you); settle
    /// once afterwards so the ears never flash empty in between.
    private var recomputePending = false
    private func recompute() {
        guard !recomputePending else { return }
        recomputePending = true
        DispatchQueue.main.async { [weak self] in
            self?.recomputePending = false
            self?.settle()
        }
    }

    private func settle() {
        let now = Date()
        let soon = meetings.filter { $0.start.addingTimeInterval(Self.linger) > now && $0.start.timeIntervalSince(now) <= Self.lead }
                           .min { $0.start < $1.start }
        meetingActivity = soon.map { .meeting(title: $0.title, start: $0.start) } ?? .none
        let new: Activity = claudeActivity != .none ? claudeActivity : waitingActivity != .none ? waitingActivity : (meetingActivity != .none ? meetingActivity : buildActivity)
        let wasActive = current != .none
        guard new != current else { return }
        current = new
        if wasActive != (new != .none) { onActiveChange?(new != .none) }
    }
}

private func progress(_ job: JenkinsJob) -> Double {
    if case .running(let p) = job.state { return p ?? 0 }
    return 0
}

/// The ears beside the collapsed notch: the buddy on the left, a short status on the right, and, when an
/// event is announced, a bubble that drops from the notch below them.
struct LiveView: View {
    @ObservedObject var model: LiveActivityModel
    @ObservedObject var center: MomentCenter
    let notch: NotchState

    var body: some View {
        let g = notch.geometry
        let earsWidth = g.collapsedSize.width + 2 * LiveLayout.extra
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                face.frame(width: LiveLayout.extra)
                Color.clear.frame(width: g.collapsedSize.width)
                status
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: LiveLayout.extra)
            }
            .frame(width: earsWidth, height: g.collapsedSize.height)

            if let moment = center.showing {
                Bubble(moment: moment, center: center)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
            }
        }
        .frame(width: max(earsWidth, center.showing == nil ? 0 : MomentCenter.bubbleSize.width), alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Buddy

    /// What the buddy feels and the colour it wears, from the event on show or else what is live.
    private var look: (mood: Mood, tint: Color)? {
        if let moment = center.showing { return (moment.mood, Self.tint(for: moment)) }
        return Self.look(for: model.current)
    }

    static func look(for activity: LiveActivityModel.Activity) -> (mood: Mood, tint: Color)? {
        switch activity {
        case .claude: return (.working, Theme.claude)
        case .waiting(_, let approval): return approval ? (.needsYou, Theme.claude) : (.happy, .green)
        case .meeting: return (.clockWatching, Theme.accent)
        case .build: return (.working, .orange)
        case .none: return nil
        }
    }

    static func tint(for moment: Moment) -> Color {
        switch moment.mood {
        case .proud, .happy: return .green
        case .sad, .shocked: return Color(red: 0.95, green: 0.3, blue: 0.28)
        default: break
        }
        switch moment.source {
        case .claude: return Theme.claude
        case .gmail: return Color(red: 0.92, green: 0.3, blue: 0.26)
        case .github: return Color(red: 0.62, green: 0.4, blue: 0.95)
        case .calendar: return Theme.accent
        case .build: return .orange
        case .slack: return Color(red: 0.88, green: 0.3, blue: 0.6)
        }
    }

    @ViewBuilder
    private var face: some View {
        if let look {
            BuddyView(mood: look.mood, tint: look.tint, size: 24)
        }
    }

    // MARK: Status words

    @ViewBuilder
    private var status: some View {
        if let moment = center.showing {
            Image(systemName: moment.symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(Self.tint(for: moment))
        } else {
            switch model.current {
            case .claude(let since, let sessions):
                if sessions > 1 {
                    Text("\u{00D7}\(sessions)")
                } else if let since {
                    // The timer and a playful word take turns: the word is the personality, the timer the fact.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let phase = Int(context.date.timeIntervalSinceReferenceDate / 4) % 2
                        Text(phase == 0 ? Self.clock(context.date.timeIntervalSince(since)) : "cooking")
                            .id(phase).transition(.opacity)
                            .animation(.easeInOut(duration: 0.25), value: phase)
                    }
                } else {
                    Text("cooking")
                }
            case .waiting(let count, let approval):
                Text(count > 1 ? "\u{00D7}\(count)" : (approval ? "ur ok?" : "ate that"))
            case .meeting(_, let start):
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text(Self.until(start, now: context.date))
                }
            case .build(_, let progress, let count):
                Text(count > 1 ? "\u{00D7}\(count)" : (progress.map { "\(Int($0 * 100))%" } ?? "\u{2026}"))
            case .none:
                EmptyView()
            }
        }
    }

    private var accessibilityText: String {
        if let moment = center.showing { return [moment.headline, moment.detail].compactMap { $0 }.joined(separator: ", ") }
        switch model.current {
        case .claude: return "Claude is working"
        case .waiting(let count, let approval):
            return count > 1 ? "\(count) Claude chats need you" : (approval ? "Claude needs your approval" : "Claude finished")
        case .meeting(let title, let start): return "\(title), \(Schedule.countdown(to: start, from: Date()))"
        case .build(let name, let progress, _): return "Build \(name) running" + (progress.map { ", \(Int($0 * 100)) percent" } ?? "")
        case .none: return ""
        }
    }

    /// "4m", or "now" once it has started.
    static func until(_ start: Date, now: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        return minutes <= 0 ? "now" : "\(minutes)m"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The bubble under the notch: what happened, in two short lines, and a way to act on it.
private struct Bubble: View {
    let moment: Moment
    @ObservedObject var center: MomentCenter

    var body: some View {
        let tint = LiveView.tint(for: moment)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(moment.headline)
                    .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .lineLimit(1)
                if let detail = moment.detail {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.62)).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let action = moment.actionTitle {
                Button { center.activate(action: true) } label: {
                    Text(action)
                        .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.black)
                        .padding(.horizontal, 14).frame(height: 26)
                        .background(Capsule().fill(tint))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 24)
        .frame(width: MomentCenter.bubbleSize.width, height: MomentCenter.bubbleSize.height)
        .contentShape(Rectangle())
        .onTapGesture { center.activate(action: false) }
        .accessibilityAddTraits(.isButton)
    }
}

/// The glyph in an ear: a soft tinted disc with the symbol on it, small enough to read as part of the notch.
private struct Badge: View {
    let symbol: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.2))
            Image(systemName: symbol).font(.system(size: 10.5, weight: .bold)).foregroundStyle(tint)
        }
        .frame(width: 21, height: 21)
    }
}

/// A small circular progress indicator; without an estimate it draws a fixed arc.
struct ProgressRing: View {
    let progress: Double?

    var body: some View {
        ZStack {
            Circle().stroke(Theme.fillHover, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress ?? 0.25)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)
        }
    }
}
