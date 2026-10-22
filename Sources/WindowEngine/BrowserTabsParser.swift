import CoreGraphics
import Foundation

/// Parses the tab-separated report produced by `BrowserTabsProvider`'s script:
///
///     W <windowID> <left> <top> <right> <bottom>
///     T <windowID> <tabIndex> <isActive 0|1> <title> <url>
public enum BrowserTabsParser {
    public static func parse(_ report: String) -> [BrowserWindow] {
        var windows: [BrowserWindow] = []
        var current: (id: Int, bounds: CGRect, tabs: [BrowserTab])?

        func flush() {
            if let current { windows.append(BrowserWindow(id: current.id, bounds: current.bounds, tabs: current.tabs)) }
        }

        for line in report.split(whereSeparator: \.isNewline) {
            let f = line.split(separator: "\t", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
            switch f.first {
            case "W" where f.count >= 6:
                flush()
                guard let id = Int(f[1]), let l = Double(f[2]), let t = Double(f[3]),
                      let r = Double(f[4]), let b = Double(f[5]) else { current = nil; continue }
                current = (id, CGRect(x: l, y: t, width: r - l, height: b - t), [])
            case "T" where f.count >= 6:
                guard let id = Int(f[1]), let index = Int(f[2]), current?.id == id else { continue }
                current?.tabs.append(BrowserTab(windowID: id, index: index, title: f[4], url: f[5], isActive: f[3] == "1"))
            default:
                continue
            }
        }
        flush()
        return windows
    }
}
