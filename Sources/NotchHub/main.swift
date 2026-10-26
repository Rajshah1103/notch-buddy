import AppKit
import ClaudeUsage
import GitHubKit
import JenkinsKit
import WindowEngine

// `NotchHub --dump` prints what the window engine sees and exits (handy for debugging).
if CommandLine.arguments.contains("--dump") {
    let snapshot = SystemWindowProvider().snapshot()
    for space in snapshot.spaces {
        print("Space \(space.index) id=\(space.id)\(space.isCurrent ? " (current)" : "")")
        for w in space.windows { print("  [\(w.id)] \(w.appName) — \(w.title)") }
    }
    print("Minimized:")
    for w in snapshot.minimized { print("  [\(w.id)] \(w.appName) — \(w.title)") }
    print("No window:")
    for a in snapshot.windowlessApps { print("  \(a.name)") }
    exit(0)
}

// `NotchHub --go-home` does what the Desktop button does and reports where it started and ended up.
if CommandLine.arguments.contains("--go-home") {
    let provider = SystemWindowProvider()
    let before = provider.snapshot().spaces
    let current = before.first(where: \.isCurrent)
    let home = before.filter { $0.displayID == current?.displayID && $0.kind == .desktop }.min { $0.index < $1.index }
    print("spaces:", before.map { "\($0.index)\($0.kind == .desktop ? "d" : "f")\($0.isCurrent ? "*" : "")" }.joined(separator: " "), "home:", home?.index as Any)
    // `--go-home away` first visits the last Space, to prove the jump works from a full-screen one.
    if CommandLine.arguments.contains("away"), let away = before.last(where: { !$0.isCurrent }) {
        provider.switchTo(away); Thread.sleep(forTimeInterval: 1.2)
        print("away at:", provider.snapshot().spaces.first(where: \.isCurrent)?.index as Any)
    }
    if let home {
        let target = SpaceInfo(id: home.id, index: home.index, displayID: home.displayID, isCurrent: false, kind: home.kind, windows: home.windows)
        if let window = home.windows.filter({ $0.bounds.width > 300 && $0.bounds.height > 300 }).min(by: { $0.order < $1.order }) {
            let done = DispatchSemaphore(value: 0)
            Task { await provider.focus(window, in: target); done.signal() }
            done.wait()
        } else { provider.switchTo(home); provider.bringFinderForward() }
    }
    Thread.sleep(forTimeInterval: 1)
    print("now:", provider.snapshot().spaces.first(where: \.isCurrent)?.index as Any,
          "front:", NSWorkspace.shared.frontmostApplication?.localizedName as Any)
    exit(0)
}

// `NotchHub --focus "App"` jumps to the app's main window and reports what ended up in front,
// then returns to where it started. Exercises the same path as clicking an app in the notch.
if let flag = CommandLine.arguments.firstIndex(of: "--focus"), flag + 1 < CommandLine.arguments.count {
    let target = CommandLine.arguments[flag + 1]
    let provider = SystemWindowProvider()

    func primaryEntry(named name: String) -> Entry? {
        let snapshot = provider.snapshot()
        let bundleIDs = Dictionary(uniqueKeysWithValues: NSWorkspace.shared.runningApplications.compactMap { app in
            app.bundleIdentifier.map { (app.processIdentifier, $0) }
        })
        return AppGroupBuilder.build(snapshot: snapshot, browsers: [:], bundleIDs: bundleIDs, recents: [],
                                     frontmostPID: nil)
            .first { $0.name == name }?.primary
    }
    func perform(_ entry: Entry, then wait: Double) {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            switch entry.target {
            case .window(let window, let space): await provider.focus(window, in: space)
            case .launch(let app): provider.open(app)
            case .tab: break
            }
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            done.signal()
        }
        done.wait()
    }
    func frontmost() -> String { NSWorkspace.shared.frontmostApplication?.localizedName ?? "?" }
    func currentSpace() -> Int {
        let snap = provider.snapshot()
        return snap.spaces.first(where: \.isCurrent)?.id ?? -1
    }
    /// Prints every change in the front app or Space over `seconds`.
    func watch(_ seconds: Double) {
        var lastFront = frontmost(), lastSpace = currentSpace()
        let began = Date()
        print(String(format: "  t=%4d ms  front=%@  space=%d", 0, lastFront, lastSpace))
        while Date().timeIntervalSince(began) < seconds {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            let f = frontmost(), sp = currentSpace()
            if f != lastFront || sp != lastSpace {
                print(String(format: "  t=%4d ms  front=%@  space=%d", Int(Date().timeIntervalSince(began) * 1000), f, sp))
                lastFront = f; lastSpace = sp
            }
        }
    }

    let start = frontmost()
    print("front before:", start, "| ax trusted:", AXIsProcessTrusted())
    guard let entry = primaryEntry(named: target) else { print("no app named \(target)"); exit(1) }
    let began = Date()
    _ = began
    print("asked for:", target, entry.place.label.isEmpty ? "" : "(\(entry.place.label))")
    Task.detached {
        switch entry.target {
        case .window(let window, let space): await provider.focus(window, in: space)
        case .launch(let app): provider.open(app)
        case .tab: break
        }
    }
    watch(2.0)
    print("front after:", frontmost(), frontmost() == target ? "OK" : "FAILED")
    exit(frontmost() == target ? 0 : 1)
}

// `NotchHub --claude` watches Claude Code activity for a few seconds and prints counts only.
if CommandLine.arguments.contains("--claude") {
    let monitor = ClaudeUsageMonitor()
    var latest = ClaudeSnapshot.idle
    monitor.onChange = { latest = $0 }
    monitor.start()
    for second in 1...12 {
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        if second == 2 || second == 12 {
            print("t=\(second)s  sessions(24h): \(latest.sessions.count)  working now: \(latest.working.count)  tokens today: \(TokenFormat.short(latest.tokensToday))")
        }
    }
    exit(0)
}

// `NotchHub --history` totals the last 90 days of Claude transcripts once (into a throwaway cache) and prints numbers only.
if CommandLine.arguments.contains("--history") {
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent("notchhub-history-\(getpid()).json")
    let scanner = UsageHistoryScanner(cacheURL: cache)
    var latest = UsageHistory.empty
    var updates = 0
    scanner.onChange = { latest = $0; updates += 1 }
    let began = Date()
    scanner.start()
    while updates < 2, Date().timeIntervalSince(began) < 300 { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
    let stats = UsageStats(history: latest)
    print(String(format: "first pass: %.1fs, days with use: %d", Date().timeIntervalSince(began), latest.daily.count))
    print("7d \(TokenFormat.short(stats.total(days: 7)))  30d \(TokenFormat.short(stats.total(days: 30)))  90d \(TokenFormat.short(stats.total(days: 90)))  streak \(stats.streak)  persona: \(stats.persona.name)")
    print("month forecast: \(TokenFormat.short(stats.monthForecast.projected)) (so far \(TokenFormat.short(stats.monthForecast.soFar)), \(stats.monthForecast.daysLeft) days left)")
    let again = Date()
    scanner.refresh(maxAge: 0)
    RunLoop.main.run(until: Date().addingTimeInterval(3))
    print(String(format: "cache size: %d KB", ((try? FileManager.default.attributesOfItem(atPath: cache.path)[.size] as? Int) ?? 0) / 1024))
    _ = again
    try? FileManager.default.removeItem(at: cache)
    exit(0)
}

// `NotchHub --github` fetches pull requests once and prints counts only.
if CommandLine.arguments.contains("--github") {
    let done = DispatchSemaphore(value: 0)
    Task {
        guard let credentials = GitHubToken.resolve(allowCommandLine: true) else { print("no token (paste one, or log in with gh)"); done.signal(); return }
        print("token source:", credentials.source == .commandLine ? "GitHub CLI login" : "pasted token")
        let began = Date()
        do {
            let snapshot = try await GitHubClient().fetch(token: credentials.token)
            print("fetched in \(Int(Date().timeIntervalSince(began) * 1000)) ms")
            print("review requested: \(snapshot.reviewRequested.count)   mine: \(snapshot.mine.count)")
            let states = Dictionary(grouping: snapshot.mine, by: \.checks).mapValues(\.count)
            print("my checks: passing \(states[.passing] ?? 0), pending \(states[.pending] ?? 0), failing \(states[.failing] ?? 0), none \(states[.none] ?? 0)")
            print("drafts: \(snapshot.mine.filter(\.isDraft).count)")
        } catch { print("error:", (error as? GitHubError)?.message ?? "\(error)") }
        done.signal()
    }
    done.wait()
    exit(0)
}

// `NotchHub --jenkins-save-token T` / `--jenkins-clear-token`: manage the Keychain item from the
// same signed binary the app uses, so the app can read it without a prompt. Used for testing.
if let flag = CommandLine.arguments.firstIndex(of: "--jenkins-save-token"), flag + 1 < CommandLine.arguments.count {
    JenkinsToken.save(CommandLine.arguments[flag + 1]); print("saved"); exit(0)
}
if CommandLine.arguments.contains("--jenkins-clear-token") { JenkinsToken.clear(); print("cleared"); exit(0) }

// `NotchHub --close-test-tab` closes any tab whose address contains "localhost:8089/nhtest", through the
// same code the notch uses. For testing only.
if CommandLine.arguments.contains("--close-test-tab") {
    let provider = BrowserTabsProvider()
    let done = DispatchSemaphore(value: 0)
    Task {
        if case .success(let windows) = await provider.windows(bundleID: "com.google.Chrome") {
            let targets = windows.flatMap(\.tabs).filter { $0.url.contains("localhost:8089/nhtest") }
            print("found \(targets.count) test tab(s)")
            for tab in targets.reversed() { provider.close(tab, bundleID: "com.google.Chrome"); try? await Task.sleep(nanoseconds: 300_000_000) }
        }
        done.signal()
    }
    done.wait()
    Thread.sleep(forTimeInterval: 0.5)     // let the last script finish
    exit(0)
}

// `NotchHub --diagnostics` prints the block "Copy diagnostics" puts on the clipboard.
if CommandLine.arguments.contains("--diagnostics") {
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        let model = WindowsModel()
        model.loadForPreview(SystemWindowProvider().snapshot(), browsers: [:], frontApp: nil)
        print(Diagnostics.report(model: model, settings: AppSettings.shared))
    }
    exit(0)
}

// `NotchHub --tabs` reports how many browser windows and tabs the scripting bridge can see.
if CommandLine.arguments.contains("--tabs") {
    let provider = BrowserTabsProvider()
    let done = DispatchSemaphore(value: 0)
    Task {
        for id in BrowserTabsProvider.supportedBundleIDs.sorted() {
            switch await provider.windows(bundleID: id) {
            case .success(let windows):
                let tabs = windows.reduce(0) { $0 + $1.tabs.count }
                let withHost = windows.flatMap(\.tabs).filter { !$0.host.isEmpty }.count
                print("\(id): \(windows.count) windows, \(tabs) tabs (\(withHost) with a host), active tabs: \(windows.compactMap(\.activeTab).count)")
            case .failure(let error):
                print("\(id): \(error)")
            }
        }
        done.signal()
    }
    done.wait()
    exit(0)
}

// `NotchHub --window settings|welcome out.png [--light]` renders those windows offscreen.
if let flag = CommandLine.arguments.firstIndex(of: "--window"), flag + 2 < CommandLine.arguments.count {
    MainActor.assumeIsolated {
        Preview.renderWindow(CommandLine.arguments[flag + 1], to: CommandLine.arguments[flag + 2],
                             light: CommandLine.arguments.contains("--light"))
    }
    exit(0)
}

if let flag = CommandLine.arguments.firstIndex(of: "--idle-sheet"), flag + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated { Preview.renderIdleSheet(to: CommandLine.arguments[flag + 1]) }
    exit(0)
}
if let flag = CommandLine.arguments.firstIndex(of: "--buddy-sheet"), flag + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated { Preview.renderBuddySheet(to: CommandLine.arguments[flag + 1]) }
    exit(0)
}

// `NotchHub --film-still <name> out.png` renders one transparent still for the launch film (see Film.swift).
if let flag = CommandLine.arguments.firstIndex(of: "--film-still"), flag + 2 < CommandLine.arguments.count {
    MainActor.assumeIsolated { Film.renderStill(CommandLine.arguments[flag + 1], to: CommandLine.arguments[flag + 2]) }
    exit(0)
}

// `NotchHub --film-frames <stills> <out> <scene|all> <16x9|1x1> [fps]` composes the film frames from the stills.
if let flag = CommandLine.arguments.firstIndex(of: "--film-frames"), flag + 4 < CommandLine.arguments.count {
    let a = CommandLine.arguments
    MainActor.assumeIsolated { FilmComposer.render(stills: a[flag + 1], out: a[flag + 2], scene: a[flag + 3], aspect: a[flag + 4], fps: flag + 5 < a.count ? Int(a[flag + 5]) ?? 30 : 30) }
    exit(0)
}

if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"), flag + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated {
        let args = CommandLine.arguments
        let app = args.firstIndex(of: "--app").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        Preview.render(to: args[flag + 1], demo: args.contains("--demo"), app: app, light: args.contains("--light"),
                       search: args.firstIndex(of: "--search").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil },
                       manyApps: args.firstIndex(of: "--many-apps").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil } ?? 0,
                       claudePanel: args.contains("--claude-panel"), githubPanel: args.contains("--github-panel"),
                       githubConnect: args.contains("--github-connect"), jenkinsPanel: args.contains("--jenkins-panel"), calendarPanel: args.contains("--calendar-panel"),
                       live: args.contains("--live"), liveBuild: args.contains("--live-build"), liveMeeting: args.contains("--live-meeting"), tabShot: args.contains("--tab-shot"),
                       gmailPanel: args.contains("--gmail-panel"), gmailSetup: args.contains("--gmail-setup"),
                       demoMoment: args.firstIndex(of: "--moment").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil })
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
