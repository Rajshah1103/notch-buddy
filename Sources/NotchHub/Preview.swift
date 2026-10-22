import AppKit
import NotchCore
import SwiftUI
import WindowEngine

/// `NotchHub --snapshot out.png [--demo] [--app "Google Chrome"]` renders the notch UI offscreen to a PNG, so the design
/// can be checked without screen-recording permission. `--demo` fills in sample window titles.
@MainActor
enum Preview {
    static func render(to path: String, demo: Bool, app: String?) {
        _ = NSApplication.shared

        var snapshot = SystemWindowProvider().snapshot()
        if demo { snapshot = withSampleTitles(snapshot) }

        let size = CGSize(width: 1000, height: 430)
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let state = NotchState(geometry: NotchGeometry(screen: screen, expandedSize: size))

        state.isExpanded = true

        let model = WindowsModel()
        model.loadForPreview(snapshot, browsers: demo ? sampleBrowsers(snapshot) : [:], frontApp: app)

        let root = SwitcherView(model: model, notch: state)
            .frame(width: size.width, height: size.height)
            .background(
                UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous)
                    .fill(.black))
            .padding(40)
            .background(Color(white: 0.16))

        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: size.width + 80, height: size.height + 80)
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI settle state set in onAppear before capturing.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("Wrote \(path)")
    }

    /// Invented tabs on top of the real Chrome window frames, so a render never reads real tabs.
    private static func sampleBrowsers(_ snapshot: Snapshot) -> [String: [BrowserWindow]] {
        let chrome = (snapshot.spaces.flatMap(\.windows) + snapshot.minimized)
            .filter { $0.appName == "Google Chrome" }.sorted { $0.order < $1.order }
        let sets: [[(String, String)]] = [
            [("Pull request #482 · api-gateway", "https://github.com/acme/api/pull/482"),
             ("Inbox (12) — raj@acme.com", "https://mail.google.com/mail/u/0/"),
             ("Grafana · p99 latency", "https://grafana.acme.dev/d/latency"),
             ("Jenkins · deploy-prod #318", "https://jenkins.acme.dev/job/deploy-prod/318"),
             ("Roadmap — Notion", "https://www.notion.so/roadmap")],
            [("Swift concurrency — Apple Developer", "https://developer.apple.com/swift"),
             ("Dynamic Island — Human Interface Guidelines", "https://developer.apple.com/design"),
             ("Stack Overflow — AXUIElement windows", "https://stackoverflow.com/questions/1"),
             ("YouTube", "https://www.youtube.com/")],
            [("Sprint board · ENG", "https://acme.atlassian.net/jira/software"),
             ("#eng-releases | Acme Slack", "https://app.slack.com/client/T01"),
             ("Figma — Notch Hub", "https://www.figma.com/file/abc")],
        ]
        var windows: [BrowserWindow] = []
        for (i, tabs) in sets.enumerated() where i < chrome.count {
            let id = 100 + i
            windows.append(BrowserWindow(id: id, bounds: chrome[i].bounds, tabs: tabs.enumerated().map { n, tab in
                BrowserTab(windowID: id, index: n + 1, title: tab.0, url: tab.1, isActive: n == (i == 0 ? 0 : 1))
            }))
        }
        return ["com.google.Chrome": windows]
    }

    private static func withSampleTitles(_ snapshot: Snapshot) -> Snapshot {
        let titles = ["Pull request #482 · api", "Inbox (12)", "~/notch-hub — zsh", "Roadmap — Notion",
                      "Grafana · latency", "Jenkins · deploy-prod", "AppDelegate.swift", "Slack | #eng"]
        var next = 0
        func retitled(_ w: WindowRecord) -> WindowRecord {
            defer { next += 1 }
            return WindowRecord(id: w.id, pid: w.pid, appName: w.appName,
                                title: titles[next % titles.count], spaceIDs: w.spaceIDs)
        }
        var copy = snapshot
        copy.spaces = snapshot.spaces.map { space in
            var s = space
            s.windows = space.windows.map(retitled)
            return s
        }
        copy.minimized = snapshot.minimized.map(retitled)
        return copy
    }
}
