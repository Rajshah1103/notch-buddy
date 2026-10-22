import AppKit
import ClaudeUsage
import GitHubKit
import JenkinsKit
import NotchCore
import SwiftUI
import WindowEngine

/// `NotchHub --snapshot out.png [--demo] [--app "Google Chrome"]` renders the notch UI offscreen to a PNG, so the design
/// can be checked without screen-recording permission. `--demo` fills in sample window titles.
@MainActor
enum Preview {
    static func render(to path: String, demo: Bool, app: String?, light: Bool, search: String?,
                       claudePanel: Bool = false, githubPanel: Bool = false, githubConnect: Bool = false,
                       jenkinsPanel: Bool = false, live: Bool = false, liveBuild: Bool = false) {
        _ = NSApplication.shared

        var snapshot = SystemWindowProvider().snapshot()
        if demo { snapshot = withSampleTitles(snapshot) }

        let size = CGSize(width: 1000, height: 440)
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let state = NotchState(geometry: NotchGeometry(screen: screen, expandedSize: size))

        state.isExpanded = true
        if let search { PreviewSeed.query = search; state.isSearching = true }

        let claude = ClaudeModel()
        claude.loadForPreview(liveBuild ? .idle : sampleClaude())
        let jenkins = JenkinsModel()
        jenkins.loadForPreview(sampleJenkins())
        AppSettings.shared.showJenkins = true      // off by default; renders show it
        let github = GitHubModel()
        github.loadForPreview(githubConnect ? nil : sampleGitHub(), needsToken: githubConnect)
        let hub = IntegrationHub(integrations: [ClaudeIntegration(model: claude), GitHubIntegration(model: github),
                                                JenkinsIntegration(model: jenkins)])
        PreviewSeed.integration = claudePanel ? "claude" : githubPanel ? "github" : jenkinsPanel ? "jenkins" : nil
        let model = WindowsModel()
        model.loadForPreview(snapshot, browsers: demo ? sampleBrowsers(snapshot) : [:], frontApp: app)

        if live || liveBuild { renderLive(to: path, activity: LiveActivityModel(claude: claude, jenkins: jenkins), state: state, light: light); return }

        let root = SwitcherView(model: model, hub: hub, notch: state)
            .frame(width: size.width, height: size.height)
            // Stand-in for the system material, which only exists inside a real window.
            .background(
                UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous)
                    .fill(light ? Color(white: 0.96, opacity: 0.94) : Color(white: 0.17, opacity: 0.94)))
            .padding(40)
            .background(LinearGradient(colors: light ? [Color(red: 0.62, green: 0.74, blue: 0.9), Color(red: 0.85, green: 0.8, blue: 0.9)]
                                                      : [Color(red: 0.12, green: 0.16, blue: 0.3), Color(red: 0.25, green: 0.12, blue: 0.3)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .environment(\.colorScheme, light ? .light : .dark)

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

    /// Renders the Settings or Welcome window content offscreen.
    static func renderWindow(_ name: String, to path: String, light: Bool) {
        _ = NSApplication.shared
        AppSettings.shared.showJenkins = true      // off by default; the render shows its fields
        let content: AnyView = name == "welcome"
            ? AnyView(WelcomeView(onDone: {}))
            : AnyView(SettingsView(settings: AppSettings.shared, showWelcome: {}))
        let host = NSHostingView(rootView: content
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, light ? .light : .dark))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("Wrote \(path) (\(Int(size.width))x\(Int(size.height)))")
    }

    /// The collapsed notch with Claude's live ears, drawn at 3x so the detail is visible.
    private static func renderLive(to path: String, activity: LiveActivityModel, state: NotchState, light: Bool) {
        let g = state.geometry
        let size = CGSize(width: g.collapsedSize.width + 2 * LiveLayout.extra, height: g.collapsedSize.height)
        let pill = LiveView(model: activity, notch: state)
            .frame(width: size.width, height: size.height)
            .background(UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9, style: .continuous)
                .fill(light ? Color(white: 0.96, opacity: 0.94) : Color(white: 0.17, opacity: 0.94)))
            .padding(.horizontal, 30).padding(.bottom, 20)
            .frame(width: size.width + 60, alignment: .top)
            .background(LinearGradient(colors: [Color(red: 0.12, green: 0.16, blue: 0.3), Color(red: 0.25, green: 0.12, blue: 0.3)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .environment(\.colorScheme, light ? .light : .dark)
        let renderer = ImageRenderer(content: pill)
        renderer.scale = 3
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("Wrote \(path)")
        }
    }

    /// Invented pull requests, so a render never shows real work.
    private static func sampleGitHub() -> GitHubSnapshot {
        let now = Date()
        func pr(_ n: Int, _ title: String, _ repo: String, _ author: String, _ checks: CheckState,
                draft: Bool = false, decision: String? = nil, ago: TimeInterval) -> PullRequest {
            PullRequest(id: "PR\(n)", number: n, title: title, url: URL(string: "https://github.com/\(repo)/pull/\(n)")!,
                        repository: repo, author: author, isDraft: draft, reviewDecision: decision, checks: checks,
                        updatedAt: now.addingTimeInterval(-ago))
        }
        let review = [
            pr(482, "Add retry with backoff to the payments client", "acme/api-gateway", "mira", .pending, ago: 1_500),
            pr(477, "Fix race in session cache eviction", "acme/api-gateway", "dev-k", .passing, ago: 9_000),
            pr(931, "Move onboarding copy into the CMS", "acme/web", "sana", .passing, ago: 30_000),
            pr(212, "Bump terraform provider to 5.4", "acme/infra", "li", .failing, ago: 86_400 * 2),
        ]
        let mine = [
            pr(488, "Notch Hub: search across windows and tabs", "raj/notch-hub", "raj", .passing, decision: "APPROVED", ago: 3_000),
            pr(490, "Draft: plugin framework", "raj/notch-hub", "raj", .none, draft: true, ago: 800),
            pr(61, "Reduce hover cost with core animation", "raj/notch-hub", "raj", .pending, ago: 400),
        ]
        return GitHubSnapshot(login: "raj", reviewRequested: review, mine: mine, fetchedAt: now)
    }

    /// Invented builds, so a render never shows a real pipeline.
    private static func sampleJenkins() -> JenkinsSnapshot {
        let now = Date()
        func job(_ full: String, _ state: BuildState, number: Int, startedAgo: TimeInterval, finishedAgo: TimeInterval? = nil) -> JenkinsJob {
            JenkinsJob(fullName: full, url: URL(string: "https://ci.acme.dev/job/\(full)/")!, state: state, buildNumber: number,
                       startedAt: now.addingTimeInterval(-startedAgo), finishedAt: finishedAgo.map { now.addingTimeInterval(-$0) })
        }
        return JenkinsSnapshot(jobs: [
            job("payments/deploy-prod", .running(progress: 0.62), number: 318, startedAgo: 140),
            job("web/e2e-tests", .running(progress: 0.18), number: 902, startedAgo: 45),
            job("payments/integration", .failed, number: 211, startedAgo: 5_400, finishedAgo: 5_100),
            job("infra/terraform-plan", .unstable, number: 77, startedAgo: 12_000, finishedAgo: 11_800),
            job("web/build", .succeeded, number: 1_204, startedAgo: 2_000, finishedAgo: 1_900),
            job("payments/build", .succeeded, number: 560, startedAgo: 9_000, finishedAgo: 8_800),
            job("mobile/release", .succeeded, number: 33, startedAgo: 40_000, finishedAgo: 39_500),
        ], fetchedAt: now)
    }

    private static func sampleClaude() -> ClaudeSnapshot {
        let now = Date()
        let sessions = [
            ClaudeSession(id: "1", project: "notch-hub", lastActivity: now, inputTokens: 91_000, outputTokens: 61_200),
            ClaudeSession(id: "2", project: "after-click", lastActivity: now.addingTimeInterval(-540), inputTokens: 40_100, outputTokens: 22_300),
            ClaudeSession(id: "3", project: "podyard", lastActivity: now.addingTimeInterval(-7_400), inputTokens: 18_000, outputTokens: 9_400),
        ]
        return ClaudeSnapshot(sessions: sessions, working: [sessions[0]], tokensToday: 682_490, workingSince: now.addingTimeInterval(-84))
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
        var chromeIndex = 0
        func retitled(_ w: WindowRecord) -> WindowRecord {
            defer { next += 1 }
            if w.appName == "Google Chrome" {
                // Chrome shows the profile in the window title when there are several.
                defer { chromeIndex += 1 }
                let profiles = ["Work", "Personal", "Side project"]
                return WindowRecord(id: w.id, pid: w.pid, appName: w.appName,
                                    title: "Page - Google Chrome - \(profiles[chromeIndex % 3])",
                                    spaceIDs: w.spaceIDs, bounds: w.bounds, order: w.order)
            }
            return WindowRecord(id: w.id, pid: w.pid, appName: w.appName,
                                title: titles[next % titles.count], spaceIDs: w.spaceIDs,
                                bounds: w.bounds, order: w.order)
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
