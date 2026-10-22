import AppKit
import ClaudeUsage
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

if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"), flag + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated {
        let args = CommandLine.arguments
        let app = args.firstIndex(of: "--app").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        Preview.render(to: args[flag + 1], demo: args.contains("--demo"), app: app, light: args.contains("--light"),
                       search: args.firstIndex(of: "--search").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil },
                       claudePanel: args.contains("--claude-panel"), live: args.contains("--live"))
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
