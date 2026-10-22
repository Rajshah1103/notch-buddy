import CoreGraphics

/// A browser's scripting interface numbers windows its own way. To know which Desktop a browser
/// window is on, pair it with the system window that has the same frame. Both lists are front to
/// back, so windows with identical frames (maximized on different Desktops) pair up in order.
public enum BrowserWindowMatcher {
    public static func match(_ browserWindows: [BrowserWindow], to candidates: [WindowRecord],
                             tolerance: CGFloat = 2) -> [Int: WindowRecord] {
        var remaining = candidates
        var result: [Int: WindowRecord] = [:]
        for window in browserWindows {
            guard let i = remaining.firstIndex(where: { sameFrame($0.bounds, window.bounds, tolerance) }) else { continue }
            result[window.id] = remaining.remove(at: i)
        }
        return result
    }

    private static func sameFrame(_ a: CGRect, _ b: CGRect, _ tolerance: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
