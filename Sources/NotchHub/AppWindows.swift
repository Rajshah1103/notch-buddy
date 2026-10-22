import AppKit
import Carbon.HIToolbox
import GitHubKit
import JenkinsKit
import SwiftUI
import WindowEngine

// MARK: - Shared pieces

/// One permission: what it unlocks, whether it is on, and a button to turn it on.
struct PermissionRow: View {
    let kind: PermissionKind
    let state: PermissionState
    let onGrant: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            statusIcon.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Read as one item ("Accessibility, not allowed"), while the button stays separately reachable.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(kind.title), \(stateWords)")
            .accessibilityValue(detail)
            Spacer(minLength: 12)
            if !state.isGranted {
                Button(buttonTitle, action: onGrant).controlSize(.small)
                    .accessibilityLabel("\(buttonTitle) \(kind.title)")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var stateWords: String {
        switch state {
        case .granted: return "allowed"
        case .notGranted: return "not allowed"
        case .notDetermined: return "not asked yet"
        case .unknown(let reason): return "unknown, \(reason)"
        }
    }

    private var detail: String {
        if case .unknown(let reason) = state { return "\(kind.benefit) \(reason)." }
        return kind.benefit
    }

    private var buttonTitle: String {
        // Pressing it asks macOS first (which is what adds the app to System Settings' list), then
        // opens the right Settings pane if the answer is not immediate.
        switch state {
        case .unknown: return "Check"
        default: return "Allow…"
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

/// Help for the case where the app is missing from a System Settings list, or listed but not working.
struct PermissionHelp: View {
    @State private var resetMessage: String?

    var body: some View {
        DisclosureGroup("Not in the list, or switched on but not working?") {
            VStack(alignment: .leading, spacing: 8) {
                Text("macOS only lists an app after it has asked. Press Allow above first. If it still isn't there, click the + in System Settings and choose Notch Hub from your Applications folder.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("An app that was rebuilt or moved can be listed and switched on yet ignored. Resetting removes the old entries so you can allow it fresh.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Show Notch Hub in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                    Button("Reset permissions") { resetMessage = Permissions.resetAll() }
                    Button("Restart Notch Hub") { Permissions.relaunch() }
                }
                .controlSize(.small)
                if let resetMessage { Text(resetMessage).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(.top, 4)
        }
        .font(.system(size: 12))
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

    @State private var githubStatus = "Checking…"
    @State private var hasGitHubToken = false

    /// Looks at the Keychain and runs `gh`, both of which can be slow, so never inside `body`.
    private func loadGitHubStatus() {
        let useCommandLine = settings.githubUsesCommandLine
        Task.detached {
            let saved = GitHubToken.stored() != nil
            let status: String
            if saved { status = "Using the token saved in your Keychain" }
            else if useCommandLine, GitHubToken.fromCommandLine() != nil { status = "Using your GitHub CLI login" }
            else { status = "Not connected" }
            await MainActor.run { githubStatus = status; hasGitHubToken = saved }
        }
    }

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            integrations.tabItem { Label("Integrations", systemImage: "puzzlepiece.extension") }
            permissionsTab.tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 540, height: 500)
        .onAppear { permissions.startPolling(); loadGitHubStatus() }
        .onChange(of: settings.githubUsesCommandLine) { loadGitHubStatus() }
        .onDisappear { permissions.stopPolling() }
    }

    private var general: some View {
        Form {
            Section("Notch") {
                Toggle("Open at login", isOn: Binding(get: { settings.launchesAtLogin },
                                                      set: { settings.setLaunchesAtLogin($0) }))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Hover pause")
                        Spacer()
                        Text(settings.hoverDelayMs == 0 ? "None" : "\(Int(settings.hoverDelayMs)) ms")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $settings.hoverDelayMs, in: 0...300, step: 10)
                    Text("Move to the notch at a normal pace and it opens at once. If you swoop in fast, it waits for you to stop for this long, so sweeping past it on the way to a menu bar icon doesn't open it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Search") {
                HStack {
                    Text("Shortcut")
                    Spacer()
                    ShortcutRecorder(binding: $settings.searchHotKey)
                }
                Picker("Search the web with", selection: $settings.searchEngine) {
                    ForEach(SearchEngine.allCases) { Text($0.name).tag($0) }
                }
                Text("Type a web address or any words into search to open them in a new browser tab. You choose the profile each time.")
                    .font(.caption).foregroundStyle(.secondary)
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
    }

    private var integrations: some View {
        Form {
            Section("Claude Code") {
                Toggle("Show activity in the notch", isOn: $settings.showClaudeActivity)
                Text("Reads Claude Code's local session files to show when it is working and how many tokens it used today. Nothing leaves your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("GitHub") {
                Toggle("Show pull requests", isOn: $settings.showGitHub)
                if settings.showGitHub {
                    Toggle("Use my GitHub CLI login when no token is saved", isOn: $settings.githubUsesCommandLine)
                    HStack {
                        Text(githubStatus).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if hasGitHubToken {
                            Button("Remove saved token") {
                                GitHubToken.clear()
                                hasGitHubToken = false
                                settings.objectWillChange.send()
                                loadGitHubStatus()
                            }.controlSize(.small)
                        }
                    }
                    Text("Connect from the GitHub chip in the notch, where you can paste a token.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Jenkins") {
                Toggle("Show builds", isOn: $settings.showJenkins)
                if settings.showJenkins { JenkinsSettings(settings: settings) }
            }
        }
        .formStyle(.grouped)
    }

    private var permissionsTab: some View {
        Form {
            Section {
                ForEach(PermissionKind.allCases) { kind in
                    PermissionRow(kind: kind, state: permissions.states[kind] ?? .notGranted) {
                        Permissions.request(kind)
                    }
                }
            } footer: {
                Text("macOS asks for these once. Notch Hub never records your screen or sends anything off your Mac. After allowing Screen Recording, restart Notch Hub so previews start working.")
            }
            Section { PermissionHelp() }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Jenkins

/// Address, username and token, with a button that checks them against the server right now.
private struct JenkinsSettings: View {
    @ObservedObject var settings: AppSettings
    @State private var token = ""
    @State private var hasToken = false
    @State private var testing = false
    @State private var result: (ok: Bool, text: String)?

    var body: some View {
        content
            .onAppear { Task.detached { let saved = JenkinsToken.stored() != nil; await MainActor.run { hasToken = saved } } }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Address", text: $settings.jenkinsURL, prompt: Text("https://jenkins.example.com"))
                .textContentType(.URL)
            TextField("Username", text: $settings.jenkinsUser)
            HStack {
                SecureField("API token", text: $token, prompt: Text(hasToken ? "Saved in your Keychain" : "Create one under your Jenkins user, Configure"))
                Button("Save") {
                    JenkinsToken.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
                    token = ""
                    hasToken = true
                    settings.objectWillChange.send()      // makes the running monitor pick it up
                }
                .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                if hasToken {
                    Button("Remove") { JenkinsToken.clear(); hasToken = false; settings.objectWillChange.send() }
                }
            }
            TextField("Only these jobs (optional)", text: $settings.jenkinsFilter, prompt: Text("deploy, payments"))
            HStack {
                Button(testing ? "Testing…" : "Test connection", action: test).disabled(testing)
                if let result {
                    Label(result.text, systemImage: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(result.ok ? .green : .orange).font(.caption)
                }
            }
            Text("If your server is behind a VPN, connect to it yourself. Notch Hub shows \"offline\" until you do, then recovers on its own.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func test() {
        let (address, user, filter) = (settings.jenkinsURL, settings.jenkinsUser, settings.jenkinsFilter)
        testing = true
        Task {
            let config = await Task.detached { JenkinsModel.config(address: address, user: user, filter: filter) }.value
            guard let config else {
                result = (false, "Fill in the address and username, and save a token")
                testing = false
                return
            }
            do {
                let snapshot = try await JenkinsClient().fetch(config)
                result = (true, "Connected: \(snapshot.jobs.count) job\(snapshot.jobs.count == 1 ? "" : "s"), \(snapshot.running.count) running")
            } catch {
                result = (false, (error as? JenkinsError)?.message ?? error.localizedDescription)
            }
            testing = false
        }
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

            PermissionHelp()

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
        .frame(width: 480)
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
