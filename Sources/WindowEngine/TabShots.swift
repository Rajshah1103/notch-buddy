import CoreGraphics
import Foundation
import ImageIO

/// A browser can only draw the tab you are looking at, so a background tab cannot be captured. Instead the
/// picture of each tab is kept from the last time it was in front, and shown with how old it is.
public enum TabShotKey {
    /// "Inbox - Google Chrome - Work" becomes "inbox"; a tab title from the browser's scripting interface
    /// carries no suffix and is only tidied. Empty when there is nothing to key on.
    public static func key(windowTitle: String, appName: String) -> String {
        var title = windowTitle
        if let range = title.range(of: " - \(appName)", options: .backwards) { title = String(title[..<range.lowerBound]) }
        return key(tabTitle: title)
    }

    /// Private windows are never captured, so nothing from them is kept even in memory.
    public static func isPrivateWindow(title: String) -> Bool {
        title.localizedCaseInsensitiveContains("incognito") || title.localizedCaseInsensitiveContains("private browsing")
            || title.localizedCaseInsensitiveContains("inprivate")
    }

    public static func key(tabTitle: String) -> String {
        tabTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Recent tab pictures held as compressed JPEG, in memory only (never written to disk).
public final class TabShotCache {
    public struct Shot {
        public let data: Data
        public let taken: Date
    }

    private var shots: [String: Shot] = [:]
    private var order: [String] = []
    private let capacity: Int

    public init(capacity: Int = 48) { self.capacity = capacity }

    public var count: Int { shots.count }

    public func shot(for key: String) -> Shot? { shots[key] }

    /// Returns false when the picture could not be stored (empty key or encoding failed).
    @discardableResult
    public func store(_ image: CGImage, key: String, at date: Date = Date()) -> Bool {
        guard !key.isEmpty, let data = Self.jpeg(image) else { return false }
        shots[key] = Shot(data: data, taken: date)
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity { shots[order.removeFirst()] = nil }
        return true
    }

    public func removeAll() { shots = [:]; order = [] }

    static func jpeg(_ image: CGImage, quality: Double = 0.72) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// "just now", "3 min ago", "2 h ago", "yesterday".
    public static func age(_ taken: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(taken))
        switch seconds {
        case ..<45: return "just now"
        case ..<3_600: return "\(max(1, seconds / 60)) min ago"
        case ..<86_400: return "\(seconds / 3_600) h ago"
        default: return "yesterday"
        }
    }
}
