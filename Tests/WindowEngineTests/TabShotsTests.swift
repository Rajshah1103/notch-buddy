import CoreGraphics
import Foundation
import Testing
@testable import WindowEngine

struct TabShotsTests {
    private func image() -> CGImage {
        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return context.makeImage()!
    }

    @Test func windowTitlesAndTabTitlesShareAKey() {
        #expect(TabShotKey.key(windowTitle: "Inbox - Google Chrome - Work", appName: "Google Chrome") == "inbox")
        #expect(TabShotKey.key(windowTitle: "Inbox - Google Chrome", appName: "Google Chrome") == "inbox")
        #expect(TabShotKey.key(tabTitle: "  Inbox ") == "inbox")
        #expect(TabShotKey.key(windowTitle: "A - B - Google Chrome - Work", appName: "Google Chrome") == "a - b")
        #expect(TabShotKey.key(windowTitle: "", appName: "Google Chrome") == "")
    }

    @Test func keepsTheNewestAndForgetsTheOldest() {
        let cache = TabShotCache(capacity: 2)
        #expect(cache.store(image(), key: "a")); #expect(cache.store(image(), key: "b")); #expect(cache.store(image(), key: "c"))
        #expect(cache.shot(for: "a") == nil)
        #expect(cache.shot(for: "b") != nil && cache.shot(for: "c") != nil)
        cache.store(image(), key: "b")          // touching b makes c the oldest
        cache.store(image(), key: "d")
        #expect(cache.shot(for: "c") == nil && cache.shot(for: "b") != nil)
        #expect(!cache.store(image(), key: ""))
    }

    @Test func describesAge() {
        let now = Date()
        #expect(TabShotCache.age(now.addingTimeInterval(-10), now: now) == "just now")
        #expect(TabShotCache.age(now.addingTimeInterval(-180), now: now) == "3 min ago")
        #expect(TabShotCache.age(now.addingTimeInterval(-7_300), now: now) == "2 h ago")
        #expect(TabShotCache.age(now.addingTimeInterval(-90_000), now: now) == "yesterday")
    }
}
