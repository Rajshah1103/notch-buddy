import Testing
@testable import WindowEngine

struct SnapshotBuilderTests {
    private func window(_ id: UInt32, pid: Int32 = 1, spaces: [Int]) -> WindowRecord {
        WindowRecord(id: id, pid: pid, appName: "App\(pid)", title: "w\(id)", spaceIDs: spaces)
    }

    private let spaces = [
        SpaceInfo(id: 10, index: 1, displayID: "d", isCurrent: true),
        SpaceInfo(id: 20, index: 2, displayID: "d", isCurrent: false),
    ]

    @Test func windowsAreGroupedBySpaceInFrontToBackOrder() {
        let snapshot = SnapshotBuilder.build(
            spaces: spaces,
            windows: [window(1, spaces: [20]), window(2, spaces: [10]), window(3, spaces: [20])],
            minimizedIDs: [],
            regularApps: []
        )
        #expect(snapshot.spaces[0].windows.map(\.id) == [2])
        #expect(snapshot.spaces[1].windows.map(\.id) == [1, 3])
    }

    @Test func minimizedWindowsGoToDockGroupNotSpaces() {
        let snapshot = SnapshotBuilder.build(
            spaces: spaces,
            windows: [window(1, spaces: [10]), window(2, spaces: [])],
            minimizedIDs: [2],
            regularApps: []
        )
        #expect(snapshot.spaces[0].windows.map(\.id) == [1])
        #expect(snapshot.minimized.map(\.id) == [2])
    }

    @Test func windowWithoutSpaceThatIsNotMinimizedIsDropped() {
        let snapshot = SnapshotBuilder.build(
            spaces: spaces,
            windows: [window(1, spaces: [])],
            minimizedIDs: [],
            regularApps: []
        )
        #expect(snapshot.spaces.allSatisfy { $0.windows.isEmpty })
        #expect(snapshot.minimized.isEmpty)
    }

    @Test func dockAppsWithoutAnyWindowAreListedAsWindowless() {
        let withWindow = AppRecord(pid: 1, name: "Terminal", bundleURL: nil)
        let without = AppRecord(pid: 2, name: "Pritunl", bundleURL: nil)
        let snapshot = SnapshotBuilder.build(
            spaces: spaces,
            windows: [window(1, pid: 1, spaces: [10])],
            minimizedIDs: [],
            regularApps: [withWindow, without]
        )
        #expect(snapshot.windowlessApps.map(\.name) == ["Pritunl"])
    }

    @Test func appWithOnlyMinimizedWindowIsNotWindowless() {
        let app = AppRecord(pid: 1, name: "Terminal", bundleURL: nil)
        let snapshot = SnapshotBuilder.build(
            spaces: spaces,
            windows: [window(1, pid: 1, spaces: [])],
            minimizedIDs: [1],
            regularApps: [app]
        )
        #expect(snapshot.windowlessApps.isEmpty)
    }

    @Test func windowOnSeveralSpacesLandsInFirstMatchingOnly() {
        let snapshot = SnapshotBuilder.build(
            spaces: spaces,
            windows: [window(1, spaces: [20, 10])],
            minimizedIDs: [],
            regularApps: []
        )
        #expect(snapshot.spaces[0].windows.count == 1)
        #expect(snapshot.spaces[1].windows.isEmpty)
    }
}
