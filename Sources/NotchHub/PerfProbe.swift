import Foundation

/// Debug-only timing, enabled with `NOTCHHUB_PERF=1`. Logs main-thread stalls (frames the user
/// would feel as jank) and how long the slow background reads take.
enum PerfProbe {
    static let enabled = ProcessInfo.processInfo.environment["NOTCHHUB_PERF"] != nil

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let stamp = String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000))
        FileHandle.standardError.write(Data("[\(stamp)] \(message())\n".utf8))
    }

    /// A 10 ms main-thread timer; a late fire means something blocked the main thread.
    @MainActor static func startStallWatchdog() {
        guard enabled else { return }
        var last = Date()
        Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
            let gap = Date().timeIntervalSince(last)
            if gap > 0.035 { log("main thread stalled \(Int(gap * 1000)) ms") }
            last = Date()
        }
    }

    static func measure<T>(_ label: String, _ work: () -> T) -> T {
        guard enabled else { return work() }
        let start = Date()
        defer { log("\(label) took \(Int(Date().timeIntervalSince(start) * 1000)) ms") }
        return work()
    }
}
