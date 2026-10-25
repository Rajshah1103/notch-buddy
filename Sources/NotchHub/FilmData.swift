import AppKit
import WindowEngine

/// Invented desktop for the launch film: app names and icons are real brands, every window title is made up.
@MainActor
enum FilmData {
    private struct App { let pid: Int32; let name: String; let path: String; let titles: [String] }

    private static let apps: [App] = [
        App(pid: 910_001, name: "Visual Studio Code", path: "/Applications/Visual Studio Code.app",
            titles: ["webhooks.ts \u{2014} api-gateway", "retry.test.ts \u{2014} api-gateway"]),
        App(pid: 910_002, name: "Google Chrome", path: "/Applications/Google Chrome.app",
            titles: ["Pull request #482 \u{00B7} api-gateway", "Dynamic Island \u{2014} Human Interface Guidelines", "#eng-releases | Acme Slack"]),
        App(pid: 910_003, name: "Ghostty", path: "/Applications/Ghostty.app",
            titles: ["claude \u{2014} api-gateway", "~/api-gateway \u{2014} zsh"]),
        App(pid: 910_004, name: "Slack", path: "/Applications/Slack.app", titles: ["#eng-releases | Acme"]),
        App(pid: 910_005, name: "Notion", path: "/Applications/Notion.app", titles: ["Roadmap Q4"]),
        App(pid: 910_006, name: "Finder", path: "/System/Library/CoreServices/Finder.app", titles: ["Downloads"]),
    ]

    static func snapshot() -> Snapshot {
        var windows: [WindowRecord] = []
        var id: UInt32 = 5_000
        for app in apps {
            for (n, title) in app.titles.enumerated() {
                id += 1
                windows.append(WindowRecord(id: id, pid: app.pid, appName: app.name, title: title, spaceIDs: [1],
                                            bounds: CGRect(x: 80 + n * 40, y: 80 + n * 30, width: 1100, height: 700), order: Int(id - 5_000)))
            }
        }
        let space = SpaceInfo(id: 1, index: 1, displayID: "film", isCurrent: true, windows: windows)
        var snapshot = Snapshot.empty
        snapshot.spaces = [space]
        return snapshot
    }

    static let bundleIDs: [Int32: String] = [910_002: "com.google.Chrome", 910_001: "com.microsoft.VSCode", 910_003: "com.mitchellh.ghostty",
                                              910_004: "com.tinyspeck.slackmacgap", 910_005: "notion.id", 910_006: "com.apple.finder"]

    static func icons() -> [(Int32, NSImage)] {
        apps.map { ($0.pid, NSWorkspace.shared.icon(forFile: $0.path)) }
    }
}
