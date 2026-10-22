import Foundation

/// Pure grouping logic, kept free of system calls so it can be unit tested.
public enum SnapshotBuilder {
    /// - Parameters:
    ///   - spaces: Spaces with empty window lists, in display order.
    ///   - windows: Candidate windows, front to back.
    ///   - minimizedIDs: Window IDs known to be minimized into the Dock.
    ///   - regularApps: Running Dock apps.
    public static func build(
        spaces: [SpaceInfo],
        windows: [WindowRecord],
        minimizedIDs: Set<UInt32>,
        regularApps: [AppRecord]
    ) -> Snapshot {
        var spaces = spaces
        var minimized: [WindowRecord] = []
        var pidsWithWindows = Set<Int32>()

        for window in windows {
            if minimizedIDs.contains(window.id) {
                minimized.append(window)
                pidsWithWindows.insert(window.pid)
            } else if let i = spaces.firstIndex(where: { window.spaceIDs.contains($0.id) }) {
                spaces[i].windows.append(window)
                pidsWithWindows.insert(window.pid)
            }
        }

        let windowless = regularApps.filter { !pidsWithWindows.contains($0.pid) }
        return Snapshot(spaces: spaces, minimized: minimized, windowlessApps: windowless)
    }
}
