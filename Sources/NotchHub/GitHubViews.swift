import GitHubKit
import NotchCore
import SwiftUI

/// Header chip: how many pull requests wait for you, with a red dot if one of yours is failing.
struct GitHubChip: View {
    @ObservedObject var model: GitHubModel
    let isOpen: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.pull").font(.system(size: 10, weight: .bold))
                if let snapshot = model.snapshot {
                    Text("\(snapshot.reviewRequested.count)")
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    if snapshot.failingChecks > 0 {
                        Circle().fill(.red).frame(width: 6, height: 6)
                    } else if snapshot.runningChecks > 0 {
                        Circle().fill(.orange).frame(width: 6, height: 6)
                    }
                } else if model.needsToken {
                    Text("Connect").font(.system(size: 11)).foregroundStyle(Theme.accent)
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
        .help("GitHub pull requests")
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Shows pull requests waiting for your review and the state of yours")
    }
}

private extension GitHubChip {
    var accessibilitySummary: String {
        guard let snapshot = model.snapshot else {
            return model.needsToken ? "GitHub pull requests, not connected" : "GitHub pull requests"
        }
        var text = "GitHub pull requests, \(snapshot.reviewRequested.count) waiting for your review"
        if snapshot.failingChecks > 0 { text += ", \(snapshot.failingChecks) of yours failing" }
        else if snapshot.runningChecks > 0 { text += ", \(snapshot.runningChecks) of yours running checks" }
        return text
    }
}

struct GitHubPanel: View {
    @ObservedObject var model: GitHubModel
    @ObservedObject var settings: AppSettings
    let notch: NotchState

    var body: some View {
        if let snapshot = model.snapshot {
            Lists(snapshot: snapshot, error: model.error, dismiss: { notch.collapse() })
        } else if model.needsToken {
            Connect(model: model, settings: settings, notch: notch)
        } else if let error = model.error {
            Message(symbol: "wifi.exclamationmark", title: error.message,
                    detail: error == .unauthorized ? "Open Settings to connect again." : "It will retry on its own.")
        } else {
            Message(symbol: "arrow.triangle.pull", title: "Loading pull requests…", detail: nil)
        }
    }
}

// MARK: - Lists

private struct Lists: View {
    let snapshot: GitHubSnapshot
    let error: GitHubError?
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.pull")
                Text("Pull requests").font(.system(size: 15, weight: .semibold))
                Text("signed in as \(snapshot.login)").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                Spacer()
                if let error {
                    Label(error.message, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 4)

            HStack(alignment: .top, spacing: 14) {
                Column(title: "Review requested", prs: snapshot.reviewRequested, showsAuthor: true, dismiss: dismiss)
                Column(title: "Your pull requests", prs: snapshot.mine, showsAuthor: false, dismiss: dismiss)
            }
        }
    }
}

private struct Column: View {
    let title: String
    let prs: [PullRequest]
    let showsAuthor: Bool
    let dismiss: () -> Void
    private let visibleRows = 6

    var body: some View {
        let shown = Array(prs.prefix(visibleRows))
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(prs.count)").font(.system(size: 11, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10).padding(.bottom, 4)

            if prs.isEmpty {
                Text(showsAuthor ? "Nothing waiting for you" : "No open pull requests")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity).padding(.top, 36)
            }
            ForEach(shown) { pr in
                PullRequestRow(pr: pr, showsAuthor: showsAuthor, dismiss: dismiss)
            }
            if prs.count > shown.count {
                Text("\(prs.count - shown.count) more on GitHub")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10).frame(height: 28)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct PullRequestRow: View {
    let pr: PullRequest
    let showsAuthor: Bool
    let dismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            LinkOpener.open(pr.url, for: "github")
            dismiss()
        } label: {
            HStack(spacing: 10) {
                CheckIcon(pr: pr).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pr.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(hovering ? Theme.fillHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .pointerHover { hovering = $0 }
        .accessibilityLabel("\(pr.title), \(pr.shortReference)")
        .accessibilityHint("Opens the pull request on GitHub")
    }

    private var subtitle: String {
        var parts = [pr.shortReference]
        if showsAuthor { parts.append(pr.author) }
        switch pr.reviewDecision {
        case "APPROVED": parts.append("Approved")
        case "CHANGES_REQUESTED": parts.append("Changes requested")
        default: break
        }
        parts.append(RelativeTime.ago(pr.updatedAt))
        return parts.joined(separator: " · ")
    }
}

private struct CheckIcon: View {
    let pr: PullRequest
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if pr.isDraft {
                Image(systemName: "pencil.circle").foregroundStyle(.secondary)
            } else {
                switch pr.checks {
                case .passing: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failing: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                case .pending:
                    Image(systemName: "circle.dotted").foregroundStyle(.orange)
                        .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                case .none: Image(systemName: "circle").foregroundStyle(.secondary.opacity(0.6))
                }
            }
        }
        .font(.system(size: 17))
        .accessibilityLabel(label)
    }

    private var label: String {
        if pr.isDraft { return "Draft" }
        switch pr.checks {
        case .passing: return "Checks passing"
        case .failing: return "Checks failing"
        case .pending: return "Checks running"
        case .none: return "No checks"
        }
    }
}

// MARK: - Not connected / messages

private struct Connect: View {
    @ObservedObject var model: GitHubModel
    @ObservedObject var settings: AppSettings
    let notch: NotchState
    @State private var token = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.triangle.pull").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.textSecondary)
            Text("Connect GitHub").font(.system(size: 17, weight: .semibold))
            Text("See pull requests waiting for your review, and whether yours are passing. Paste a personal access token with read access to pull requests and commit statuses. It stays in your Keychain.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            HStack(spacing: 8) {
                SecureField("Personal access token", text: $token)
                    .textFieldStyle(.roundedBorder).frame(width: 300)
                    .focused($focused)
                    .onSubmit(connect)
                Button("Connect", action: connect)
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Button("Create a token on GitHub") {
                if let url = URL(string: "https://github.com/settings/personal-access-tokens/new") { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(.link).font(.system(size: 12))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
        // Asking for a token is this panel's whole job, so take the keyboard as it opens and give it
        // back when it closes. Esc leaves.
        .onAppear {
            notch.setTyping(true)
            DispatchQueue.main.async { focused = true }
        }
        .onDisappear { notch.setTyping(false) }
        .onKeyPress(.escape) { notch.collapse(); return .handled }
    }

    private func connect() {
        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.connect(token: token, useCommandLine: settings.githubUsesCommandLine)
        token = ""
    }
}

private struct Message: View {
    let symbol: String
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(Theme.textSecondary)
            Text(title).font(.system(size: 14, weight: .semibold))
            if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(Theme.textSecondary) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }
}
