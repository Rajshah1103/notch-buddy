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
/// else a running Jenkins build. More sources can slot in here later.
@MainActor
final class LiveActivityModel: ObservableObject {
    enum Activity: Equatable {
        case claude(since: Date?, sessions: Int)
        case build(name: String, progress: Double?, count: Int)
        case none
    }

    @Published private(set) var current = Activity.none
    var onActiveChange: ((Bool) -> Void)?

    private var subscriptions = Set<AnyCancellable>()
    private var claudeActivity = Activity.none
    private var buildActivity = Activity.none

    init(claude: ClaudeModel, jenkins: JenkinsModel) {
        claude.$snapshot
            .sink { [weak self] snapshot in
                self?.claudeActivity = snapshot.isWorking ? .claude(since: snapshot.workingSince, sessions: snapshot.working.count) : .none
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

    private func recompute() {
        let new: Activity = claudeActivity != .none ? claudeActivity : buildActivity
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
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
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
        case .build(_, let progress, let count):
            Text(count > 1 ? "×\(count)" : (progress.map { "\(Int($0 * 100))%" } ?? "…"))
        case .none:
            EmptyView()
        }
    }

    private var accessibilityText: String {
        switch model.current {
        case .claude: return "Claude is working"
        case .build(let name, let progress, _): return "Build \(name) running" + (progress.map { ", \(Int($0 * 100)) percent" } ?? "")
        case .none: return ""
        }
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
