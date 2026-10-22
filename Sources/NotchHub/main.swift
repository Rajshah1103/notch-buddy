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

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
