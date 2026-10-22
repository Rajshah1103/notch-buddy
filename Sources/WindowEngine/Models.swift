import Foundation

public struct WindowRecord: Identifiable, Hashable {
    public let id: UInt32
    public let pid: Int32
    public let appName: String
    public let title: String
    public let spaceIDs: [Int]

    public init(id: UInt32, pid: Int32, appName: String, title: String, spaceIDs: [Int]) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.title = title
        self.spaceIDs = spaceIDs
    }
}

public struct SpaceInfo: Identifiable, Hashable {
    public let id: Int
    public let index: Int
    public let displayID: String
    public let isCurrent: Bool
    public var windows: [WindowRecord]

    public init(id: Int, index: Int, displayID: String, isCurrent: Bool, windows: [WindowRecord] = []) {
        self.id = id
        self.index = index
        self.displayID = displayID
        self.isCurrent = isCurrent
        self.windows = windows
    }
}

/// A running app that has no window to jump to (closed its window, or lives in the Dock only).
public struct AppRecord: Identifiable, Hashable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let bundleURL: URL?

    public init(pid: Int32, name: String, bundleURL: URL?) {
        self.pid = pid
        self.name = name
        self.bundleURL = bundleURL
    }
}

public struct Snapshot {
    public var spaces: [SpaceInfo]
    public var minimized: [WindowRecord]
    public var windowlessApps: [AppRecord]

    public static let empty = Snapshot(spaces: [], minimized: [], windowlessApps: [])
}
