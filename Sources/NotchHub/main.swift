import AppKit
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
        Preview.render(to: args[flag + 1], demo: args.contains("--demo"), app: app)
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
