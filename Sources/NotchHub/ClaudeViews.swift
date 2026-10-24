import ClaudeUsage
import NotchCore
import SwiftUI

/// Claude's brand orange. It marks Claude activity everywhere it appears.
extension Theme {
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)    // #D97757
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
                // The header is crowded; the badge takes the token count's place while chats wait on you.
                if model.needsYou.isEmpty {
                    Text(TokenFormat.short(model.snapshot.tokensToday))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                if !model.needsYou.isEmpty {
                    Text("\(model.needsYou.count)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Circle().fill(Theme.claude))
                } else if model.snapshot.isWorking { Circle().fill(Theme.claude).frame(width: 6, height: 6) }
            }
            .foregroundStyle(isOpen ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(Capsule().fill(isOpen ? Theme.fillSelected : (hovering ? Theme.fillHover : Theme.fillQuiet)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerHover { hovering = $0 }
        .help("Claude Code")
        .accessibilityLabel("Claude usage, \(model.needsYou.isEmpty ? (model.snapshot.isWorking ? "working now" : "idle") : "\(model.needsYou.count) need you"), \(TokenFormat.short(model.snapshot.tokensToday)) tokens today")
        .accessibilityHint("Shows Claude Code sessions and tokens used today")
    }
}

/// Claude Code sessions from the last day: what is working now and how much each used today.
struct ClaudePanel: View {
    @ObservedObject var model: ClaudeModel

    var body: some View {
        let sessions = model.snapshot.sessions

        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle").foregroundStyle(Theme.claude)
                    Text("Claude Code").font(.system(size: 15, weight: .semibold))
                    Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s") in the last day")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 4)

                // The one list in the notch that scrolls: a day of chats can run past what fits.
                ScrollView(.vertical) {
                    VStack(spacing: 2) {
                        if sessions.isEmpty {
                            Text("No Claude Code sessions found yet")
                                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity).padding(.top, 40)
                        }
                        ForEach(sessions) { session in
                            SessionRow(session: session, isWorking: model.snapshot.working.contains(session),
                                       needsYou: model.needsYou.contains(session)) {
                                model.markSeen(session)
                                ClaudeLauncher.open(session)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            }
            .frame(width: 590)

            Insights(model: model).frame(width: 300)
        }
    }
}

private struct SessionRow: View {
    let session: ClaudeSession
    let isWorking: Bool
    let needsYou: Bool
    let onOpen: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var status: (text: String, color: Color) {
        switch (needsYou, session.attention) {
        case (true, .approval): return ("Waiting for you", Theme.claude)
        case (true, .finished): return ("Finished", .green)
        default: return (isWorking ? "Working now" : "Active \(RelativeTime.ago(session.lastActivity))",
                         isWorking ? Theme.claude : Theme.textSecondary)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(needsYou ? status.color : isWorking ? Theme.claude : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
                .symbolEffect(.pulse, isActive: false)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text((session.title == nil ? "" : "\(session.project) · ")
                     + status.text)
                    .font(.system(size: 11, weight: needsYou ? .semibold : .regular))
                    .foregroundStyle(status.color)
            }
            Spacer(minLength: 0)
            if hovering {
                Label("Open", systemImage: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.claude)
                    .transition(.opacity)
            }
            Text(TokenFormat.short(session.totalTokens))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(hovering ? Theme.fillHover : .clear))
        .contentShape(Rectangle())
        .pointerHover { hovering = $0 }
        .animation(.easeOut(duration: 0.08), value: hovering)
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens this chat in Ghostty")
    }
}
