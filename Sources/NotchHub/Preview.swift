import AppKit
import BuddyKit
import CalendarKit
import ClaudeUsage
import GmailKit
import GitHubKit
import JenkinsKit
import NotchCore
import SwiftUI
import WindowEngine

/// `NotchHub --snapshot out.png [--demo] [--app "Google Chrome"]` renders the notch UI offscreen to a PNG, so the design
/// can be checked without screen-recording permission. `--demo` fills in sample window titles.
@MainActor
enum Preview {
    static func render(to path: String, demo: Bool, app: String?, light: Bool, search: String?, manyApps: Int = 0,
                       claudePanel: Bool = false, githubPanel: Bool = false, githubConnect: Bool = false,
                       jenkinsPanel: Bool = false, calendarPanel: Bool = false, live: Bool = false, liveBuild: Bool = false, liveMeeting: Bool = false, tabShot: Bool = false,
                       gmailPanel: Bool = false, gmailSetup: Bool = false) {
        _ = NSApplication.shared

        var snapshot = SystemWindowProvider().snapshot()
        if demo { snapshot = withSampleTitles(snapshot) }
        for n in 0..<manyApps {      // invented apps, to see how the app row copes with a crowd
            snapshot.windowlessApps.append(AppRecord(pid: Int32(900_000 + n), name: "App \(n + 1)", bundleURL: nil))
        }

        let size = CGSize(width: 1000, height: 440)
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let state = NotchState(geometry: NotchGeometry(screen: screen, expandedSize: size))

        state.isExpanded = true
        if let search { PreviewSeed.query = search; state.isSearching = true }

        let claude = ClaudeModel()
        claude.loadForPreview(liveBuild || liveMeeting ? .idle : sampleClaude(), history: sampleHistory())
        let jenkins = JenkinsModel()
        jenkins.loadForPreview(sampleJenkins())
        AppSettings.shared.showJenkins = true      // off by default; renders show it
        let calendar = CalendarModel()
        calendar.loadForPreview(sampleMeetings())
        AppSettings.shared.showCalendar = true
        let web = WebBrowser()
        web.loadForPreview([
            BrowserProfile(directory: "Default", name: "Personal", email: "raj@example.com"),
            BrowserProfile(directory: "Profile 1", name: "Work", email: "raj@acme.dev"),
            BrowserProfile(directory: "Profile 2", name: "Client A", email: "raj@clienta.io"),
            BrowserProfile(directory: "Profile 3", name: "Side project", email: nil),
            BrowserProfile(directory: "Profile 4", name: "Testing", email: nil),
        ], lastUsed: "Profile 1")
        let github = GitHubModel()
        github.loadForPreview(githubConnect ? nil : sampleGitHub(), needsToken: githubConnect)
        let gmail = GmailModel()
        gmail.loadForPreview(gmailSetup ? nil : sampleGmail(), state: gmailSetup ? .needsSetup : .ready)
        AppSettings.shared.showGmail = true
        let hub = IntegrationHub(integrations: [ClaudeIntegration(model: claude), GitHubIntegration(model: github),
                                                JenkinsIntegration(model: jenkins), CalendarIntegration(model: calendar),
                                                GmailIntegration(model: gmail)])
        PreviewSeed.integration = gmailPanel || gmailSetup ? "gmail" : claudePanel ? "claude" : githubPanel ? "github" : jenkinsPanel ? "jenkins" : calendarPanel ? "calendar" : nil
        let model = WindowsModel()
        for n in 0..<manyApps {
            let symbols = ["safari", "message", "music.note", "photo", "calendar", "envelope", "map", "doc.text", "gearshape", "terminal"]
            let config = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
            if let image = NSImage(systemSymbolName: symbols[n % symbols.count], accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                model.setPreviewIcon(image, for: Int32(900_000 + n))
            }
        }
        model.loadForPreview(snapshot, browsers: demo ? sampleBrowsers(snapshot) : [:], frontApp: app)
        if tabShot {
            let title = "Inbox (12) — raj@acme.com"
            PreviewSeed.hoverTitle = title
            model.rememberForPreview(sampleTabImage(), tabTitle: title, minutesAgo: 3)
        }

        if live || liveBuild || liveMeeting { renderLive(to: path, activity: LiveActivityModel(claude: claude, jenkins: jenkins, calendar: calendar), state: state, light: light); return }

        let root = SwitcherView(model: model, hub: hub, web: web, learning: LearningStore(), notch: state)
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

    /// Every buddy mood on black, at 3x, with its label and tint.
    static func renderBuddySheet(to path: String) {
        _ = NSApplication.shared
        let tints: [Mood: Color] = [.sleepy: Color(white: 0.7), .working: Theme.claude, .thinking: Theme.claude, .needsYou: Theme.claude,
                                    .happy: .green, .proud: .green, .sad: .red, .excited: Color(red: 0.92, green: 0.3, blue: 0.25),
                                    .alert: .purple, .clockWatching: Theme.accent, .shocked: .red]
        let grid = HStack(alignment: .top, spacing: 18) {
            ForEach(Array(Mood.allCases.enumerated()), id: \.offset) { _, mood in
                VStack(spacing: 8) {
                    BuddyView(mood: mood, tint: tints[mood] ?? .orange, size: 64, fixedTime: 0.6)
                    BuddyView(mood: mood, tint: tints[mood] ?? .orange, size: 22, fixedTime: 0.6)
                    Text(mood.label).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(24).background(Color.black)
        let renderer = ImageRenderer(content: grid)
        renderer.scale = 3
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("Wrote \(path)")
        }
    }

    /// Renders the Settings or Welcome window content offscreen.
    static func renderWindow(_ name: String, to path: String, light: Bool) {
        _ = NSApplication.shared
        AppSettings.shared.showJenkins = true      // off by default; the render shows its fields
        let content: AnyView = name == "welcome"
            ? AnyView(WelcomeView(onDone: {}))
            : AnyView(SettingsView(settings: AppSettings.shared, learning: LearningStore(), showWelcome: {}, diagnostics: { "" }))
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
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))      // the model settles on the next turn of the run loop
        let g = state.geometry
        let size = CGSize(width: g.collapsedSize.width + 2 * LiveLayout.extra, height: g.collapsedSize.height)
        let pill = LiveView(model: activity, notch: state)
            .frame(width: size.width, height: size.height)
            .background(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12, style: .continuous)
                .fill(Color.black))
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

    /// 90 invented days with a weekly rhythm and a recent climb, so the insights card has something to draw.
    private static func sampleHistory() -> UsageHistory {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var daily: [Date: Int] = [:], chats: [Date: Int] = [:]
        for back in 0..<90 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let weekend = calendar.isDateInWeekend(day)
            let wave = 1.0 + 0.5 * sin(Double(back) * 0.7)
            let climb = 1.0 + Double(90 - back) / 90.0
            daily[day] = Int(1_600_000 * wave * climb * (weekend ? 0.45 : 1.0))
            chats[day] = 2 + (back * 7) % 6
        }
        var hours = Array(repeating: 200_000, count: 24)
        for hour in 9...18 { hours[hour] = 1_200_000 }
        return UsageHistory(daily: daily, hours: hours, chats: chats)
    }

    private static func sampleGmail() -> GmailSnapshot {
        let now = Date()
        return GmailSnapshot(email: "you@example.com", unread: 14, messages: [
            GmailMessage(id: "1", from: "Priya Nair", subject: "Re: Q3 launch checklist", date: now.addingTimeInterval(-240)),
            GmailMessage(id: "2", from: "Stripe", subject: "Your payout of $1,240.00 is on the way", date: now.addingTimeInterval(-3_100)),
            GmailMessage(id: "3", from: "GitHub", subject: "[notch-hub] Pull request #12 merged", date: now.addingTimeInterval(-7_900)),
            GmailMessage(id: "4", from: "Alex Chen", subject: "Intro: Notch Hub feedback call", date: now.addingTimeInterval(-18_000)),
        ])
    }

    private static func sampleClaude() -> ClaudeSnapshot {
        let now = Date()
        let sessions = [
            ClaudeSession(id: "1", project: "notch-hub", lastActivity: now, inputTokens: 91_000, outputTokens: 61_200, title: "Add chat names to the notch"),
            ClaudeSession(id: "2", project: "after-click", lastActivity: now.addingTimeInterval(-540), inputTokens: 40_100, outputTokens: 22_300, title: "Fix pricing page layout", attention: .approval),
            ClaudeSession(id: "3", project: "podyard", lastActivity: now.addingTimeInterval(-7_400), inputTokens: 18_000, outputTokens: 9_400, attention: .finished),
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


/// Invented meetings for preview renders; nothing here comes from a real calendar.
@MainActor
private func sampleMeetings() -> [Meeting] {
    let now = Date()
    func at(_ minutes: Double, _ length: Double, _ title: String, color: [Double], join: String? = nil) -> Meeting {
        Meeting(id: title, title: title, start: now.addingTimeInterval(minutes * 60), end: now.addingTimeInterval((minutes + length) * 60),
                isAllDay: false, calendarName: "Work", calendarColor: color, joinURL: join.flatMap(URL.init(string:)))
    }
    let blue = [0.2, 0.5, 0.95], green = [0.2, 0.75, 0.4], orange = [0.95, 0.6, 0.2]
    return [
        at(-10, 30, "Sprint planning", color: blue, join: "https://meet.google.com/abc-defg-hij"),
        at(4, 15, "Standup", color: blue, join: "https://meet.google.com/xyz-abcd-efg"),
        at(75, 45, "Design review", color: green, join: "https://acme.zoom.us/j/123456789"),
        at(150, 30, "1:1 with Priya", color: orange),
        at(260, 60, "Quarterly planning", color: blue, join: "https://teams.microsoft.com/l/meetup-join/abc"),
    ]
}


/// A stand-in page for design renders: a header bar and a few lines of "text".
private func sampleTabImage() -> CGImage {
    let w = 560, h = 350
    let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: w, height: h))
    context.setFillColor(CGColor(red: 0.85, green: 0.19, blue: 0.16, alpha: 1)); context.fill(CGRect(x: 0, y: h - 44, width: w, height: 44))
    context.setFillColor(CGColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1))
    for row in 0..<7 { context.fill(CGRect(x: 24, y: h - 90 - row * 38, width: row % 3 == 0 ? 300 : 460, height: 12)) }
    return context.makeImage()!
}
