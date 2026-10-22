import AppKit
import Carbon.HIToolbox
import GitHubKit
import SwiftUI

// MARK: - Shared pieces

/// One permission: what it unlocks, whether it is on, and a button to turn it on.
struct PermissionRow: View {
    let kind: PermissionKind
    let state: PermissionState
    let onGrant: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if !state.isGranted {
                Button(buttonTitle, action: onGrant).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if case .unknown(let reason) = state { return "\(kind.benefit) \(reason)." }
        return kind.benefit
    }

    private var buttonTitle: String {
        switch state {
        case .notGranted: return "Open Settings"
        case .unknown: return "Check"
        default: return "Allow"
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .granted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 20))
        case .notGranted, .notDetermined:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary).font(.system(size: 20))
        case .unknown:
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary).font(.system(size: 20))
        }
    }
}

/// Click, then press a shortcut. Needs at least one of Control, Option or Command so it cannot
/// swallow ordinary typing. Esc cancels.
struct ShortcutRecorder: View {
    @Binding var binding: HotKeyBinding
    @State private var recording = false

    var body: some View {
        Button {
            recording.toggle()
        } label: {
            Text(recording ? "Press a shortcut…" : binding.display)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .frame(minWidth: 120)
        }
        .controlSize(.small)
        .background(Recorder(isRecording: $recording, binding: $binding).frame(width: 0, height: 0))
        .accessibilityLabel("Search shortcut, \(binding.display)")
    }

    private struct Recorder: NSViewRepresentable {
        @Binding var isRecording: Bool
        @Binding var binding: HotKeyBinding

        func makeNSView(context: Context) -> CaptureView { CaptureView() }

        func updateNSView(_ view: CaptureView, context: Context) {
            view.onKey = { event in
                if event.keyCode == UInt16(kVK_Escape) { isRecording = false; return }
                let mods = HotKeyBinding.carbonModifiers(event.modifierFlags)
                guard mods & (controlKey | optionKey | cmdKey) != 0 else { NSSound.beep(); return }
                binding = HotKeyBinding(keyCode: Int(event.keyCode), modifiers: mods)
                isRecording = false
            }
            if isRecording { DispatchQueue.main.async { view.window?.makeFirstResponder(view) } }
            else if view.window?.firstResponder === view { view.window?.makeFirstResponder(nil) }
        }
    }

    final class CaptureView: NSView {
        var onKey: ((NSEvent) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) { onKey?(event) }
        override func performKeyEquivalent(with event: NSEvent) -> Bool { onKey?(event); return true }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var permissions = PermissionsModel()
    let showWelcome: () -> Void

    private var githubStatus: String {
        if GitHubToken.stored() != nil { return "Using the token saved in your Keychain" }
        if settings.githubUsesCommandLine, GitHubToken.fromCommandLine() != nil { return "Using your GitHub CLI login" }
        return "Not connected"
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { settings.launchesAtLogin },
                                                      set: { settings.setLaunchesAtLogin($0) }))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Hover to open")
                        Spacer()
                        Text(settings.hoverDelayMs == 0 ? "Instant" : "\(Int(settings.hoverDelayMs)) ms")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $settings.hoverDelayMs, in: 0...300, step: 10)
                    Text("How long the pointer rests on the notch before it opens. A short pause stops it opening when you brush past on the way to a menu bar icon.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Search") {
                HStack {
                    Text("Shortcut")
                    Spacer()
                    ShortcutRecorder(binding: $settings.searchHotKey)
                }
            }

            Section("Integrations") {
                Toggle("Claude Code activity", isOn: $settings.showClaudeActivity)
                Text("Reads Claude Code's local session files to show when it is working and how many tokens it used today. Nothing leaves your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("GitHub pull requests", isOn: $settings.showGitHub)
                if settings.showGitHub {
                    Toggle("Use my GitHub CLI login when no token is saved", isOn: $settings.githubUsesCommandLine)
                    HStack {
                        Text(githubStatus).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if GitHubToken.stored() != nil {
                            Button("Remove saved token") {
                                GitHubToken.clear()
                                settings.objectWillChange.send()
                            }.controlSize(.small)
                        }
                    }
                    Text("Connect from the GitHub chip in the notch, where you can paste a token.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Permissions") {
                ForEach(PermissionKind.allCases) { kind in
                    PermissionRow(kind: kind, state: permissions.states[kind] ?? .notGranted) {
                        Permissions.request(kind)
                    }
                }
            }

            Section {
                HStack {
                    Text("Notch Hub \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show welcome again", action: showWelcome).controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 820)
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @StateObject private var permissions = PermissionsModel()
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tint)
                Text("Welcome to Notch Hub").font(.system(size: 24, weight: .semibold))
                Text("Hover over the notch to see your apps, windows and browser tabs, then click to jump straight there. No more swiping between Spaces.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Three permissions make it work")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(PermissionKind.allCases) { kind in
                    PermissionRow(kind: kind, state: permissions.states[kind] ?? .notGranted) {
                        Permissions.request(kind)
                    }
                    if kind != PermissionKind.allCases.last { Divider() }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))

            VStack(spacing: 8) {
                Button(action: onDone) {
                    Text(permissions.allGranted ? "Start using Notch Hub" : "Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                Text(permissions.allGranted
                     ? "Move your pointer to the notch, or press \(AppSettings.shared.searchHotKey.display) to search."
                     : "You can allow these later in Settings. Some features stay off until you do.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(width: 460)
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
    }
}

// MARK: - Window management

/// Keeps one window per purpose and brings it to the front. The app has no Dock icon, so a window
/// has to activate the app itself to be seen.
@MainActor
final class WindowPresenter {
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(_ id: String, title: String, @ViewBuilder content: () -> Content) {
        if let existing = windows[id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: content())
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close(_ id: String) { windows[id]?.close() }
}
