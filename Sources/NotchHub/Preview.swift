import AppKit
import NotchCore
import SwiftUI
import WindowEngine

/// `NotchHub --snapshot out.png [--demo]` renders the notch UI offscreen to a PNG, so the design
/// can be checked without screen-recording permission. `--demo` fills in sample window titles.
@MainActor
enum Preview {
    static func render(to path: String, demo: Bool) {
        _ = NSApplication.shared
        Theme.skipReveal = true

        var snapshot = SystemWindowProvider().snapshot()
        if demo { snapshot = withSampleTitles(snapshot) }

        let size = CGSize(width: 1000, height: 340)
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let state = NotchState(geometry: NotchGeometry(screen: screen, expandedSize: size))

        let model = WindowsModel()
        model.loadForPreview(snapshot, thumbnails: [:])

        let root = WindowsView(model: model, notch: state)
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
