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
        #expect(chrome.entries[0].section == "Window 1 · Desktop 2")
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

struct PlaceAndProfileTests {
    private let frame = CGRect(x: 0, y: 30, width: 1440, height: 870)

    @Test func profileComesFromTheWindowTitle() {
        #expect(profileName(fromWindowTitle: "Inbox - Google Chrome - Work", appName: "Google Chrome") == "Work")
        #expect(profileName(fromWindowTitle: "Inbox – Google Chrome – Side project", appName: "Google Chrome") == "Side project")
        #expect(profileName(fromWindowTitle: "Inbox - Google Chrome", appName: "Google Chrome") == nil)
        #expect(profileName(fromWindowTitle: "", appName: "Google Chrome") == nil)
    }

    @Test func fullScreenSpacesAreNotDesktops() {
        let desktop = SpaceInfo(id: 1, index: 1, displayID: "d", isCurrent: true, kind: .desktop,
                                windows: [WindowRecord(id: 1, pid: 1, appName: "Ghostty", title: "zsh", spaceIDs: [1], bounds: frame, order: 0)])
        let full = SpaceInfo(id: 9, index: 2, displayID: "d", isCurrent: false, kind: .fullScreen,
                             windows: [WindowRecord(id: 2, pid: 2, appName: "Code", title: "main.swift", spaceIDs: [9], bounds: frame, order: 1)])
        let groups = AppGroupBuilder.build(snapshot: Snapshot(spaces: [desktop, full], minimized: [], windowlessApps: []),
                                           browsers: [:], bundleIDs: [:], recents: [1, 2], frontmostPID: 1)
        #expect(groups[0].entries[0].place.label == "")            // the only Desktop: nothing to say
        #expect(groups[1].entries[0].place.label == "Full screen")
    }

    @Test func desktopsAreNumberedOnlyWhenThereAreSeveral() {
        func window(_ id: UInt32, _ space: Int) -> WindowRecord {
            WindowRecord(id: id, pid: Int32(id), appName: "App\(id)", title: "t", spaceIDs: [space], bounds: frame, order: Int(id))
        }
        let one = SpaceInfo(id: 1, index: 1, displayID: "d", isCurrent: true, kind: .desktop, windows: [window(1, 1)])
        let two = SpaceInfo(id: 2, index: 2, displayID: "d", isCurrent: false, kind: .desktop, windows: [window(2, 2)])
        let groups = AppGroupBuilder.build(snapshot: Snapshot(spaces: [one, two], minimized: [], windowlessApps: []),
                                           browsers: [:], bundleIDs: [:], recents: [1, 2], frontmostPID: 1)
        #expect(groups[0].entries[0].place.label == "Desktop 1")
        #expect(groups[1].entries[0].place.label == "Desktop 2")
    }
}

struct SearchTests {
    private func tab(_ id: Int, _ title: String, _ url: String, active: Bool = false) -> Entry {
        let t = BrowserTab(windowID: 1, index: id, title: title, url: url, isActive: active)
        return Entry(id: "t\(id)", title: title, subtitle: t.host, detail: "", url: url,
                     place: EntryPlace(kind: .fullScreen, isCurrent: false), section: nil, isActive: active,
                     thumbnailWindowID: nil, target: .tab(t, bundleID: "com.google.Chrome"))
    }

    private var groups: [AppGroup] {
        [AppGroup(pid: 1, name: "Google Chrome", bundleID: "com.google.Chrome", entries: [
            tab(1, "Pull request #482 · api-gateway", "https://github.com/acme/api/pull/482"),
            tab(2, "Inbox (12)", "https://mail.google.com/mail/u/0/", active: true),
            tab(3, "Jenkins · deploy-prod #318", "https://jenkins.acme.dev/job/deploy-prod/318"),
            tab(4, "Grafana · p99 latency", "https://grafana.acme.dev/d/latency")])]
    }

    private func titles(_ query: String) -> [String] { Search.results(for: query, in: groups).map(\.entry.title) }

    @Test func findsByTitleHostAndApp() {
        #expect(titles("jenkins") == ["Jenkins · deploy-prod #318"])
        #expect(titles("github").first == "Pull request #482 · api-gateway")
        #expect(titles("chrome").count == 4)
    }

    @Test func everyTermMustMatch() {
        #expect(titles("pull 482").count == 1)
        #expect(titles("pull zzz").isEmpty)
    }

    @Test func toleratesTyposThroughSubsequence() {
        #expect(titles("grfn").first == "Grafana · p99 latency")
    }

    @Test func wordStartsBeatBuriedMatches() {
        let list = [AppGroup(pid: 3, name: "X", bundleID: nil, entries: [
            tab(1, "Bandwidth report", "https://a.com"), tab(2, "Dashboard", "https://b.com")])]
        #expect(Search.results(for: "dash", in: list).first?.entry.title == "Dashboard")
    }
}

struct SearchLearningTests {
    private func tab(_ id: Int, _ title: String, _ url: String) -> Entry {
        let t = BrowserTab(windowID: 1, index: id, title: title, url: url, isActive: false)
        return Entry(id: "t\(id)", title: title, subtitle: t.host, detail: "", url: url,
                     place: EntryPlace(kind: .fullScreen, isCurrent: false), section: nil, isActive: false,
                     thumbnailWindowID: nil, target: .tab(t, bundleID: "com.google.Chrome"))
    }

    private var groups: [AppGroup] {
        [AppGroup(pid: 1, name: "Google Chrome", bundleID: nil, entries: [
            tab(1, "Jenkins docs — pipeline syntax", "https://www.jenkins.io/doc/book/pipeline/syntax"),
            tab(2, "Jenkins · deploy-prod #318", "https://jenkins.acme.dev/job/deploy-prod/318"),
            tab(3, "Grafana · p99 latency", "https://grafana.acme.dev/d/latency")])]
    }

    private func order(_ query: String, _ learning: SearchLearning, now: Date = Date()) -> [String] {
        Search.results(for: query, in: groups, boost: { entry, app in
            learning.boost(key: SearchLearning.key(for: entry, appName: app), query: query, now: now)
        }).map(\.entry.title)
    }

    @Test func choosingAResultLiftsItNextTime() {
        var learning = SearchLearning()
        #expect(order("jen", learning).first == "Jenkins docs — pipeline syntax")
        let key = SearchLearning.key(for: groups[0].entries[1], appName: "Google Chrome")
        learning.record(key: key, query: "jen")
        learning.record(key: key, query: "jen")
        #expect(order("jen", learning).first == "Jenkins · deploy-prod #318")
        #expect(order("jenk", learning).first == "Jenkins · deploy-prod #318")
        #expect(order("grafana", learning) == ["Grafana · p99 latency"])
    }

    @Test func oldHabitsFadeAndFrequencyIsCapped() {
        let now = Date()
        var old = SearchLearning(), fresh = SearchLearning(), heavy = SearchLearning()
        old.record(key: "k", at: now.addingTimeInterval(-60 * 86_400))
        fresh.record(key: "k", at: now)
        for _ in 0..<500 { heavy.record(key: "k", at: now) }
        #expect(old.boost(key: "k", query: "", now: now) < fresh.boost(key: "k", query: "", now: now) / 5)
        #expect(heavy.boost(key: "k", query: "", now: now) <= 18.01)
    }

    @Test func aTabIsKeyedBySiteAndPersistsAndStaysSmall() throws {
        let key = SearchLearning.key(for: tab(9, "Other page", "https://jenkins.acme.dev/other"), appName: "Google Chrome")
        #expect(key == SearchLearning.key(for: groups[0].entries[1], appName: "Google Chrome"))

        var learning = SearchLearning()
        for i in 0..<2_000 { learning.record(key: "site\(i)", query: "q\(i % 50)", at: Date().addingTimeInterval(Double(i))) }
        let data = try JSONEncoder().encode(learning)
        #expect(data.count < 400_000)
        #expect(try JSONDecoder().decode(SearchLearning.self, from: data) == learning)
    }
}
