import AppKit
import Foundation
import WindowEngine

/// A block of text a customer can paste into a support request. It holds versions, permission states and
/// counts, and deliberately nothing personal: no window titles, addresses, names, tokens or file paths.
@MainActor
enum Diagnostics {
    static func report(model: WindowsModel, settings: AppSettings) -> String {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        let os = ProcessInfo.processInfo.operatingSystemVersionString

        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &machine, &size, nil, 0)
        let hardware = String(cString: machine)

        let screens = NSScreen.screens.map { $0.safeAreaInsets.top > 0 ? "notch" : "no notch" }.joined(separator: ", ")
        let permissions = PermissionKind.allCases.map { kind -> String in
            switch Permissions.state(of: kind) {
            case .granted: return "\(kind.title): allowed"
            case .notGranted: return "\(kind.title): not allowed"
            case .notDetermined: return "\(kind.title): not asked"
            case .unknown(let reason): return "\(kind.title): unknown (\(reason))"
            }
        }.joined(separator: "; ")

        let snapshot = model.snapshot
        let desktops = snapshot.spaces.filter { $0.kind == .desktop }.count
        let fullScreen = snapshot.spaces.filter { $0.kind == .fullScreen }.count
        let windows = snapshot.spaces.reduce(0) { $0 + $1.windows.count } + snapshot.minimized.count
        let tabs = model.groups.filter(\.isBrowserWithTabs).reduce(0) { $0 + $1.entries.count }

        return """
        Notch Hub \(version)
        macOS \(os) on \(hardware)
        Screens: \(screens)
        Permissions: \(permissions)
        Spaces: \(desktops) desktop(s), \(fullScreen) full-screen
        Seen right now: \(model.groups.count) apps, \(windows) windows, \(tabs) browser tabs
        Integrations on: claude \(settings.showClaudeActivity), github \(settings.showGitHub), jenkins \(settings.showJenkins)
        Settings: hover pause \(Int(settings.hoverDelayMs)) ms, search engine \(settings.searchEngine.name), learning \(settings.learnFromUse), hidden apps \(settings.hiddenApps.count)
        """
    }
}
