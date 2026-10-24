import CalendarKit
import ClaudeUsage
import Combine
import JenkinsKit
import NotchCore
import SwiftUI

enum LiveLayout {
    /// How far the collapsed notch widens on each side while something is live.
    static let extra: CGFloat = 72
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

/// The ears beside the collapsed notch: a mark on the left, a short status on the right.
struct LiveView: View {
    @ObservedObject var model: LiveActivityModel
    let notch: NotchState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let g = notch.geometry
        HStack(spacing: 0) {
            leading.frame(width: LiveLayout.extra)
            Color.clear.frame(width: g.collapsedSize.width)
            trailing
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(width: LiveLayout.extra)
        }
        .frame(width: g.collapsedSize.width + 2 * LiveLayout.extra, height: g.collapsedSize.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var leading: some View {
        switch model.current {
        case .claude:
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.claude)
        case .waiting(_, let approval):
            Image(systemName: approval ? "hand.raised.fill" : "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(approval ? Theme.claude : Color.green)
        case .meeting:
            Image(systemName: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
        case .build(_, let progress, _):
            ProgressRing(progress: progress).frame(width: 16, height: 16)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch model.current {
        case .claude(let since, let sessions):
            if sessions > 1 {
                Text("×\(sessions)")
            } else if let since {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Self.clock(context.date.timeIntervalSince(since)))
                }
            }
        case .waiting(let count, let approval):
            Text(count > 1 ? "×\(count)" : (approval ? "Approve" : "Done"))
        case .meeting(_, let start):
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(Self.until(start, now: context.date))
            }
        case .build(_, let progress, let count):
            Text(count > 1 ? "×\(count)" : (progress.map { "\(Int($0 * 100))%" } ?? "…"))
        case .none:
            EmptyView()
        }
    }

    private var accessibilityText: String {
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
