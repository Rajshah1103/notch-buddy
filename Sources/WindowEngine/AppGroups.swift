import Foundation

/// Where an entry lives, in words a person would use.
public struct EntryPlace: Hashable {
    public enum Kind: Hashable {
        case desktop(Int)
        case minimized
        case unknown
    }

    public let kind: Kind
    public let isCurrent: Bool

    public var label: String {
        switch kind {
        case .desktop(let number): return "Desktop \(number)"
        case .minimized: return "Minimized"
        case .unknown: return ""
        }
    }
}

public enum EntryTarget: Hashable {
    case window(WindowRecord, SpaceInfo?)
    case tab(BrowserTab, bundleID: String)
    case launch(AppRecord)
}

/// One thing you can jump to: a window, a browser tab, or an app with no window to open.
public struct Entry: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let detail: String
    public let url: String
    public let place: EntryPlace
    /// Heading to show above this entry when it starts a new group (browser windows).
    public let section: String?
    public let isActive: Bool
    /// System window whose live preview represents this entry, when there is one.
    public let thumbnailWindowID: UInt32?
    public let target: EntryTarget
}

/// A running app and everything inside it that can be jumped to.
public struct AppGroup: Identifiable, Hashable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let bundleID: String?
    public let entries: [Entry]

    /// What clicking the app's icon opens: the active tab or front window.
    public var primary: Entry? { entries.first(where: \.isActive) ?? entries.first }
    public var isBrowserWithTabs: Bool { entries.contains { if case .tab = $0.target { true } else { false } } }
}

public enum AppGroupBuilder {
    /// - Parameters:
    ///   - browsers: tab data per browser bundle identifier.
    ///   - bundleIDs: bundle identifier per process.
    ///   - recents: process IDs, most recently used first.
    public static func build(
        snapshot: Snapshot,
        browsers: [String: [BrowserWindow]],
        bundleIDs: [Int32: String],
        recents: [Int32],
        frontmostPID: Int32?
    ) -> [AppGroup] {
        struct Located {
            let record: WindowRecord
            let space: SpaceInfo?   // nil: minimized
        }

        var located: [Int32: [Located]] = [:]
        for space in snapshot.spaces {
            for window in space.windows { located[window.pid, default: []].append(Located(record: window, space: space)) }
        }
        for window in snapshot.minimized { located[window.pid, default: []].append(Located(record: window, space: nil)) }
        for pid in located.keys { located[pid]?.sort { $0.record.order < $1.record.order } }

        func place(_ item: Located?) -> EntryPlace {
            guard let item else { return EntryPlace(kind: .unknown, isCurrent: false) }
            guard let space = item.space else { return EntryPlace(kind: .minimized, isCurrent: false) }
            return EntryPlace(kind: .desktop(space.index), isCurrent: space.isCurrent)
        }

        var groups: [AppGroup] = []

        for (pid, items) in located {
            let name = items.first?.record.appName ?? "App"
            let bundleID = bundleIDs[pid]

            if let bundleID, let windows = browsers[bundleID], !windows.isEmpty {
                let matched = BrowserWindowMatcher.match(windows, to: items.map(\.record))
                let byID = Dictionary(items.map { ($0.record.id, $0) }, uniquingKeysWith: { first, _ in first })
                let places = windows.map { place(matched[$0.id].flatMap { byID[$0.id] }) }
                let sameLabel = Dictionary(grouping: places.map(\.label), by: { $0 }).mapValues(\.count)
                var seen: [String: Int] = [:]
                var entries: [Entry] = []

                for (i, window) in windows.enumerated() {
                    let p = places[i]
                    let record = matched[window.id]
                    let base = p.label.isEmpty ? "Window \(i + 1)" : p.label
                    seen[base, default: 0] += 1
                    let section = (sameLabel[p.label] ?? 1) > 1 ? "\(base) · Window \(seen[base]!)" : base

                    for (n, tab) in window.tabs.enumerated() {
                        entries.append(Entry(
                            id: "\(bundleID):\(tab.id)",
                            title: tab.title.isEmpty ? (tab.host.isEmpty ? "Untitled" : tab.host) : tab.title,
                            subtitle: tab.host,
                            detail: "Tab \(tab.index) of \(window.tabs.count)",
                            url: tab.url,
                            place: p,
                            section: n == 0 ? section : nil,
                            isActive: tab.isActive,
                            thumbnailWindowID: tab.isActive ? record?.id : nil,
                            target: .tab(tab, bundleID: bundleID)))
                    }
                }
                groups.append(AppGroup(pid: pid, name: name, bundleID: bundleID, entries: entries))
                continue
            }

            let entries = items.enumerated().map { i, item -> Entry in
                let p = place(item)
                let hasTitle = !item.record.title.isEmpty
                return Entry(
                    id: "w\(item.record.id)",
                    title: hasTitle ? item.record.title : name,
                    subtitle: hasTitle ? p.label : (p.label.isEmpty ? "" : p.label),
                    detail: items.count > 1 ? "Window \(i + 1) of \(items.count)" : "",
                    url: "",
                    place: p,
                    section: nil,
                    isActive: pid == frontmostPID && i == 0,
                    thumbnailWindowID: item.record.id,
                    target: .window(item.record, item.space))
            }
            groups.append(AppGroup(pid: pid, name: name, bundleID: bundleID, entries: entries))
        }

        for app in snapshot.windowlessApps where located[app.pid] == nil {
            let entry = Entry(id: "app\(app.pid)", title: "Open \(app.name)", subtitle: "No windows open", detail: "",
                              url: "", place: EntryPlace(kind: .unknown, isCurrent: false), section: nil,
                              isActive: false, thumbnailWindowID: nil, target: .launch(app))
            groups.append(AppGroup(pid: app.pid, name: app.name, bundleID: bundleIDs[app.pid], entries: [entry]))
        }

        let rank = Dictionary(recents.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return groups.sorted {
            let a = rank[$0.pid] ?? Int.max, b = rank[$1.pid] ?? Int.max
            return a != b ? a < b : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
