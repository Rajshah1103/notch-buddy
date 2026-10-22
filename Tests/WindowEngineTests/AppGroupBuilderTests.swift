import CoreGraphics
import Testing
@testable import WindowEngine

struct AppGroupBuilderTests {
    private let frame = CGRect(x: 0, y: 30, width: 1440, height: 870)

    private func groups() -> [AppGroup] {
        let chrome = WindowRecord(id: 50, pid: 10, appName: "Google Chrome", title: "", spaceIDs: [2], bounds: frame, order: 1)
        let phantom = WindowRecord(id: 51, pid: 10, appName: "Google Chrome", title: "", spaceIDs: [2],
                                   bounds: CGRect(x: 5, y: 5, width: 300, height: 200), order: 2)
        let code = WindowRecord(id: 70, pid: 20, appName: "Code", title: "main.swift", spaceIDs: [1], bounds: frame, order: 0)
        let one = SpaceInfo(id: 1, index: 1, displayID: "d", isCurrent: true, windows: [code])
        let two = SpaceInfo(id: 2, index: 2, displayID: "d", isCurrent: false, windows: [chrome, phantom])
        let snapshot = Snapshot(spaces: [one, two], minimized: [],
                                windowlessApps: [AppRecord(pid: 30, name: "Finder", bundleURL: nil)])
        let tabs = [BrowserTab(windowID: 1, index: 1, title: "A", url: "https://a.com", isActive: false),
                    BrowserTab(windowID: 1, index: 2, title: "B", url: "https://b.com", isActive: true)]
        return AppGroupBuilder.build(
            snapshot: snapshot,
            browsers: ["com.google.Chrome": [BrowserWindow(id: 1, bounds: frame, tabs: tabs)]],
            bundleIDs: [10: "com.google.Chrome", 20: "com.microsoft.VSCode"],
            recents: [20, 10], frontmostPID: 20)
    }

    @Test func appsAreOrderedByRecencyWithWindowlessLast() {
        #expect(groups().map(\.name) == ["Code", "Google Chrome", "Finder"])
    }

    @Test func browserShowsItsTabsAndDropsPhantomWindows() {
        let chrome = groups()[1]
        #expect(chrome.entries.count == 2)
        #expect(chrome.isBrowserWithTabs)
        #expect(chrome.primary?.title == "B")
    }

    @Test func tabKnowsItsDesktopThroughTheWindowFrame() {
        let chrome = groups()[1]
        #expect(chrome.entries[0].place.label == "Desktop 2")
        #expect(chrome.entries[0].section == "Desktop 2")
    }

    @Test func onlyTheActiveTabGetsTheWindowPreview() {
        let chrome = groups()[1]
        #expect(chrome.entries[1].thumbnailWindowID == 50)
        #expect(chrome.entries[0].thumbnailWindowID == nil)
    }

    @Test func plainWindowKeepsItsTitleAndIsActiveWhenFrontmost() {
        let code = groups()[0]
        #expect(code.entries[0].title == "main.swift")
        #expect(code.entries[0].isActive)
    }
}
