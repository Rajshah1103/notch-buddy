import CoreGraphics
import Testing
@testable import WindowEngine

struct BrowserTests {
    private let frame = CGRect(x: 0, y: 30, width: 1440, height: 870)

    @Test func parsesWindowsAndTabs() {
        let report = "W\t7\t0\t30\t1440\t900\nT\t7\t1\t1\tGitHub — PR\thttps://www.github.com/a/b\nT\t7\t2\t0\tInbox\thttps://mail.google.com/\nW\t9\t10\t40\t800\t600\nT\t9\t1\t1\tLocal\thttp://localhost:3000/x\n"
        let windows = BrowserTabsParser.parse(report)
        #expect(windows.count == 2)
        #expect(windows[0].tabs.count == 2)
        #expect(windows[0].tabs[0].host == "github.com")
        #expect(windows[0].tabs[0].isActive)
        #expect(windows[0].bounds == CGRect(x: 0, y: 30, width: 1440, height: 870))
    }

    @Test func garbageYieldsNothing() {
        #expect(BrowserTabsParser.parse("garbage\n").isEmpty)
    }

    @Test func identicalFramesPairInFrontToBackOrder() {
        let browserWindows = [BrowserWindow(id: 1, bounds: frame, tabs: []), BrowserWindow(id: 2, bounds: frame, tabs: [])]
        let records = [
            WindowRecord(id: 50, pid: 1, appName: "C", title: "", spaceIDs: [5], bounds: frame, order: 3),
            WindowRecord(id: 60, pid: 1, appName: "C", title: "", spaceIDs: [6], bounds: frame, order: 9),
        ]
        let matched = BrowserWindowMatcher.match(browserWindows, to: records)
        #expect(matched[1]?.id == 50)
        #expect(matched[2]?.id == 60)
    }
}
