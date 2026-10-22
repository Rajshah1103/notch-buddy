import ClaudeUsage
import NotchCore
import SwiftUI

/// Claude's brand orange. It marks Claude activity everywhere it appears.
extension Theme {
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)    // #D97757
}

enum LiveLayout {
    /// How far the collapsed notch widens on each side while Claude is working.
    static let extra: CGFloat = 72
}

/// What shows in the ears beside the collapsed notch while Claude works: a pulsing mark on the
/// left, how long it has been going on the right.
struct ClaudeLiveView: View {
    @ObservedObject var model: ClaudeModel
    let notch: NotchState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let g = notch.geometry
        HStack(spacing: 0) {
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.claude)
                .symbolEffect(.pulse, options: .repeating, isActive: model.snapshot.isWorking && !reduceMotion)
                .frame(width: LiveLayout.extra)

            Color.clear.frame(width: g.collapsedSize.width)

            Group {
                if model.snapshot.working.count > 1 {
                    Text("×\(model.snapshot.working.count)")
                } else if let since = model.snapshot.workingSince {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Self.clock(context.date.timeIntervalSince(since)))
                    }
                }
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
            .frame(width: LiveLayout.extra)
        }
        .frame(width: g.collapsedSize.width + 2 * LiveLayout.extra, height: g.collapsedSize.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Claude is working")
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Status chip in the expanded header; click to open the sessions panel.
struct ClaudeChip: View {
    @ObservedObject var model: ClaudeModel
    let isOpen: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "sparkle").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.claude)
                Text(model.snapshot.isWorking ? "Claude working" : "Claude")
                    .font(.system(size: 11, weight: .medium))
                Text(TokenFormat.short(model.snapshot.tokensToday))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(isOpen ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(Capsule().fill(isOpen ? Theme.fillSelected : (hovering ? Theme.fillHover : Theme.fillQuiet)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Claude usage, \(model.snapshot.isWorking ? "working now" : "idle"), \(TokenFormat.short(model.snapshot.tokensToday)) tokens today")
        .accessibilityHint("Shows Claude Code sessions and tokens used today")
    }
}

/// Claude Code sessions from the last day: what is working now and how much each used today.
struct ClaudePanel: View {
    @ObservedObject var model: ClaudeModel
    private let visibleRows = 8

    var body: some View {
        let sessions = model.snapshot.sessions
        let shown = Array(sessions.prefix(visibleRows))

        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle").foregroundStyle(Theme.claude)
                    Text("Claude Code").font(.system(size: 15, weight: .semibold))
                    Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s") in the last day")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 4)

                VStack(spacing: 2) {
                    if shown.isEmpty {
                        Text("No Claude Code sessions found yet")
                            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    ForEach(shown) { session in
                        SessionRow(session: session, isWorking: model.snapshot.working.contains(session))
                    }
                    if sessions.count > shown.count {
                        Text("\(sessions.count - shown.count) more")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 28)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(width: 590)

            Summary(model: model).frame(width: 300)
        }
    }
}

private struct SessionRow: View {
    let session: ClaudeSession
    let isWorking: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isWorking ? Theme.claude : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
                .symbolEffect(.pulse, isActive: false)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.project).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(isWorking ? "Working now" : "Active \(RelativeTime.ago(session.lastActivity))")
                    .font(.system(size: 11))
                    .foregroundStyle(isWorking ? Theme.claude : Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Text(TokenFormat.short(session.totalTokens))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .accessibilityElement(children: .combine)
    }
}

private struct Summary: View {
    @ObservedObject var model: ClaudeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            Text(TokenFormat.short(model.snapshot.tokensToday))
                .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
            Text("tokens across all sessions")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            Divider().padding(.vertical, 6)
            Label(model.snapshot.isWorking
                  ? "\(model.snapshot.working.count) working now"
                  : "Idle", systemImage: model.snapshot.isWorking ? "bolt.fill" : "moon.zzz")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(model.snapshot.isWorking ? Theme.claude : Theme.textSecondary)
            Text("Counts new input and output. Cache re-reads are not included. Plan limits aren't stored on this Mac, so they can't be shown.")
                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.fillQuiet))
    }
}
