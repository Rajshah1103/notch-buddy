import AppKit
import ApplicationServices
import CoreServices
import WindowEngine

enum PermissionKind: CaseIterable, Identifiable {
    case accessibility, automation, screenRecording
    var id: Self { self }

    var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .automation: return "Browser tabs"
        case .screenRecording: return "Screen Recording"
        }
    }

    var benefit: String {
        switch self {
        case .accessibility: return "Jump to the exact window you pick, including minimized ones."
        case .automation: return "See every tab in Chrome, Brave, Edge or Arc, and jump straight to one."
        case .screenRecording: return "Show live window previews and Chrome profile names. Nothing is recorded or stored."
        }
    }
}

enum PermissionState: Equatable {
    case granted
    case notGranted
    /// macOS has not asked yet; requesting will show its prompt.
    case notDetermined
    /// Cannot be checked right now (for automation: no supported browser is open).
    case unknown(String)

    var isGranted: Bool { self == .granted }
}

enum Permissions {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    static func state(of kind: PermissionKind) -> PermissionState {
        switch kind {
        case .accessibility: return accessibilityGranted ? .granted : .notGranted
        case .screenRecording: return screenRecordingGranted ? .granted : .notGranted
        case .automation: return automationState(prompting: false)
        }
    }

    /// Automation is granted per target app, and only a running app can be asked about. Checks the
    /// first supported browser that is open, without showing a prompt.
    static func automationState(prompting: Bool) -> PermissionState {
        guard let bundleID = BrowserTabsProvider.supportedBundleIDs.sorted().first(where: {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
        }) else { return .unknown("Open Chrome, Brave, Edge or Arc to check") }

        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let descriptor = target.aeDesc else { return .unknown("Could not check") }
        let status = AEDeterminePermissionToAutomateTarget(descriptor, OSType(typeWildCard), OSType(typeWildCard), prompting)
        switch Int(status) {
        case Int(noErr): return .granted
        case -1744: return .notDetermined          // errAEEventWouldRequireUserConsent
        case -1743: return .notGranted             // errAEEventNotPermitted
        default: return .unknown("Status \(status)")
        }
    }

    /// Shows macOS's own prompt when it can, otherwise opens the right System Settings pane.
    static func request(_ kind: PermissionKind) {
        switch kind {
        case .accessibility:
            if !AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) {
                openSettings("Privacy_Accessibility")
            }
        case .screenRecording:
            if !CGRequestScreenCaptureAccess() { openSettings("Privacy_ScreenCapture") }
        case .automation:
            DispatchQueue.global().async {
                let state = automationState(prompting: true)
                if state == .notGranted { DispatchQueue.main.async { openSettings("Privacy_Automation") } }
            }
        }
    }

    static func requestAccessibility() { request(.accessibility) }
    static func requestScreenRecording() { request(.screenRecording) }
    static func openAutomationSettings() { request(.automation) }

    /// Removes this app's saved permission entries (they can go stale when the app is rebuilt or moved),
    /// so macOS asks again from scratch. Returns a sentence for the user.
    static func resetAll() -> String {
        guard let id = Bundle.main.bundleIdentifier else { return "Couldn't find this app's identifier." }
        var failed = false
        for service in ["Accessibility", "ScreenCapture", "AppleEvents"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", service, id]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            if (try? process.run()) == nil { failed = true; continue }
            process.waitUntilExit()
            if process.terminationStatus != 0 { failed = true }
        }
        return failed
            ? "Some entries couldn't be cleared from here. In System Settings, select Notch Hub and press the minus button, then press Allow again."
            : "Cleared. Press Allow on each item above, then restart Notch Hub."
    }

    /// Starts a fresh copy of the app and quits this one (needed after Screen Recording is allowed).
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private static func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Live permission status for the windows that show it: re-checks while they are open, because the
/// user flips these switches in System Settings, outside this app.
@MainActor
final class PermissionsModel: ObservableObject {
    @Published private(set) var states: [PermissionKind: PermissionState] = [:]
    private var timer: Timer?

    init() { refresh() }

    func startPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopPolling() { timer?.invalidate(); timer = nil }

    func refresh() {
        for kind in PermissionKind.allCases {
            let new = Permissions.state(of: kind)
            if states[kind] != new { states[kind] = new }
        }
    }

    var allGranted: Bool { PermissionKind.allCases.allSatisfy { states[$0]?.isGranted == true } }
}
