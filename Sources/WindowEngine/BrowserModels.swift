import CoreGraphics
import Foundation

public struct BrowserTab: Identifiable, Hashable {
    public let id: String
    public let windowID: Int
    /// 1-based position within its window, as the browser's scripting interface numbers tabs.
    public let index: Int
    public let title: String
    public let url: String
    public let isActive: Bool

    public init(windowID: Int, index: Int, title: String, url: String, isActive: Bool) {
        self.id = "\(windowID)-\(index)"
        self.windowID = windowID
        self.index = index
        self.title = title
        self.url = url
        self.isActive = isActive
    }

    /// "github.com" for "https://www.github.com/x", empty for non-web URLs.
    public var host: String {
        guard let host = URL(string: url)?.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

public struct BrowserWindow: Identifiable, Hashable {
    public let id: Int
    public let bounds: CGRect
    public let tabs: [BrowserTab]

    public init(id: Int, bounds: CGRect, tabs: [BrowserTab]) {
        self.id = id
        self.bounds = bounds
        self.tabs = tabs
    }

    public var activeTab: BrowserTab? { tabs.first(where: \.isActive) ?? tabs.first }
}

public enum BrowserError: Error, Equatable {
    case notRunning
    /// The user has not allowed this app to control the browser (System Settings → Automation).
    case notAuthorized
    case failed(String)
}
