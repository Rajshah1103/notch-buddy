import JenkinsKit
import NotchCore
import SwiftUI

/// Lets a panel open Settings without knowing about the app delegate.
enum AppActions {
    nonisolated(unsafe) static var openSettings: () -> Void = {}
}

struct JenkinsChip: View {
    @ObservedObject var model: JenkinsModel
    let isOpen: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "hammer.fill").font(.system(size: 10, weight: .bold))
                if isOpen || !model.isConfigured { Text("Jenkins").font(.system(size: 11, weight: .medium)) }
                if !model.isConfigured {
                    Text("Set up").font(.system(size: 11)).foregroundStyle(Theme.accent)
                } else if let snapshot = model.snapshot {
                    if !snapshot.running.isEmpty {
                        Text("\(snapshot.running.count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                    if !snapshot.failing.isEmpty { Circle().fill(.red).frame(width: 6, height: 6) }
                    else if !snapshot.running.isEmpty { Circle().fill(.orange).frame(width: 6, height: 6) }
                    if model.error == .unreachable { Image(systemName: "wifi.slash").font(.system(size: 9)).foregroundStyle(.orange) }
                } else if model.error == .unreachable {
                    Text("offline").font(.system(size: 11)).foregroundStyle(.orange)
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
        .help("Jenkins builds")
        .accessibilityLabel(summary)
        .accessibilityHint("Shows running and failing Jenkins builds")
    }

    private var summary: String {
        guard model.isConfigured else { return "Jenkins, not set up" }
        guard let snapshot = model.snapshot else { return model.error.map { "Jenkins, \($0.message)" } ?? "Jenkins" }
        var text = "Jenkins, \(snapshot.running.count) running"
        if !snapshot.failing.isEmpty { text += ", \(snapshot.failing.count) failing" }
        if model.error == .unreachable { text += ", offline, showing the last results" }
        return text
    }
}

struct JenkinsPanel: View {
    @ObservedObject var model: JenkinsModel
    let dismiss: () -> Void

    var body: some View {
        if !model.isConfigured {
            SetupCard()
        } else if let snapshot = model.snapshot {
            Builds(snapshot: snapshot, error: model.error, dismiss: dismiss)
        } else if let error = model.error {
            VStack(spacing: 8) {
                Image(systemName: error == .unreachable ? "wifi.slash" : "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .light)).foregroundStyle(Theme.textSecondary)
                Text(error.message).font(.system(size: 14, weight: .semibold))
                Text(error == .unreachable ? "It will reconnect on its own once you are on the VPN." : "Check the details in Settings.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                if error != .unreachable { Button("Open Settings") { AppActions.openSettings() }.controlSize(.small) }
            }
            .frame(maxWidth: .infinity).padding(.top, 70)
        } else {
            Text("Loading builds…").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity).padding(.top, 90)
        }
    }
}

private struct SetupCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer.fill").font(.system(size: 28, weight: .light)).foregroundStyle(Theme.textSecondary)
            Text("Set up Jenkins").font(.system(size: 17, weight: .semibold))
            Text("Add your Jenkins address, username and API token in Settings. If your server is behind a VPN, connect to it first. Notch Hub never manages the VPN.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button("Open Settings") { AppActions.openSettings() }.controlSize(.regular)
        }
        .frame(maxWidth: .infinity).padding(.top, 50)
    }
}

private struct Builds: View {
    let snapshot: JenkinsSnapshot
    let error: JenkinsError?
    let dismiss: () -> Void
    private let visibleRows = 6

    var body: some View {
        let relevant = snapshot.relevant()
        let attention = relevant.filter { $0.state.isRunning || $0.state == .failed || $0.state == .unstable }
        let recent = relevant.filter { !(attention.contains($0)) }

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hammer.fill")
                Text("Jenkins").font(.system(size: 15, weight: .semibold))
                Text("\(snapshot.jobs.count) jobs watched").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                Spacer()
                if let error {
                    Label(error == .unreachable ? "Offline, showing the last results" : error.message,
                          systemImage: error == .unreachable ? "wifi.slash" : "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 4)

            HStack(alignment: .top, spacing: 14) {
                BuildColumn(title: "Running and failing", jobs: attention, emptyText: "Nothing running or broken", limit: visibleRows, dismiss: dismiss)
                BuildColumn(title: "Finished in the last day", jobs: recent, emptyText: "No recent builds", limit: visibleRows, dismiss: dismiss)
            }
        }
    }
}

private struct BuildColumn: View {
    let title: String
    let jobs: [JenkinsJob]
    let emptyText: String
    let limit: Int
    let dismiss: () -> Void

    var body: some View {
        let shown = Array(jobs.prefix(limit))
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(jobs.count)").font(.system(size: 11, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(Theme.textSecondary).padding(.horizontal, 10).padding(.bottom, 4)

            if jobs.isEmpty {
                Text(emptyText).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity).padding(.top, 36)
            }
            ForEach(shown) { job in BuildRow(job: job, dismiss: dismiss) }
            if jobs.count > shown.count {
                Text("\(jobs.count - shown.count) more").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary).padding(.horizontal, 10).frame(height: 28)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct BuildRow: View {
    let job: JenkinsJob
    let dismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(job.url)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                BuildIcon(state: job.state).frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if case .running(let progress) = job.state {
                        HStack(spacing: 8) {
                            ProgressBar(progress: progress)
                            Text(progress.map { "\(Int($0 * 100))%" } ?? "running")
                                .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                        }
                    } else {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(hovering ? Theme.fillHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .pointerHover { hovering = $0 }
        .accessibilityLabel("\(job.name), \(accessibilityState)")
        .accessibilityHint("Opens the job in your browser")
    }

    private var subtitle: String {
        var parts: [String] = []
        if let folder = job.folder { parts.append(folder) }
        if let number = job.buildNumber { parts.append("#\(number)") }
        switch job.state {
        case .failed: parts.append("failed")
        case .unstable: parts.append("unstable")
        case .succeeded: parts.append("passed")
        case .aborted: parts.append("aborted")
        default: break
        }
        if let finished = job.finishedAt { parts.append(RelativeTime.ago(finished)) }
        return parts.joined(separator: " · ")
    }

    private var accessibilityState: String {
        switch job.state {
        case .running(let p): return p.map { "running, \(Int($0 * 100)) percent" } ?? "running"
        case .failed: return "failed"
        case .unstable: return "unstable"
        case .succeeded: return "passed"
        default: return "idle"
        }
    }
}

struct BuildIcon: View {
    let state: BuildState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch state {
            case .running: Image(systemName: "circle.dotted").foregroundStyle(.orange)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .unstable: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.yellow)
            case .aborted: Image(systemName: "stop.circle").foregroundStyle(.secondary)
            default: Image(systemName: "circle").foregroundStyle(.secondary.opacity(0.6))
            }
        }
        .font(.system(size: 17))
    }
}

/// A thin determinate bar; without an estimate it shows a quiet sliver instead of a made-up number.
struct ProgressBar: View {
    let progress: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fillHover)
                Capsule().fill(Color.orange)
                    .frame(width: proxy.size.width * (progress ?? 0.12))
                    .animation(.easeOut(duration: 0.4), value: progress)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
