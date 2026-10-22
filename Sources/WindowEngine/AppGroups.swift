import Foundation

/// Where an entry lives, in words a person would use.
public struct EntryPlace: Hashable {
    public enum Kind: Hashable {
        /// A Desktop. `number` is nil when there is only one, so nothing needs saying.
        case desktop(number: Int?)
        case fullScreen
        case minimized
        case unknown
    }

    public let kind: Kind
    public let isCurrent: Bool

    public var label: String {
        switch kind {
        case .desktop(let number): return number.map { "Desktop \($0)" } ?? ""
        case .fullScreen: return "Full screen"
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

    /// "github.com" for a tab's address; empty for windows.
    public var host: String {
        guard !url.isEmpty, let host = URL(string: url)?.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
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

/// Chromium browsers append the profile to the window title when more than one profile exists:
/// "Inbox - Google Chrome - Work". Returns "Work", or nil when there is no profile to show.
public func profileName(fromWindowTitle title: String, appName: String) -> String? {
    guard let range = title.range(of: appName, options: .backwards) else { return nil }
    let rest = title[range.upperBound...]
        .trimmingCharacters(in: CharacterSet(charactersIn: " -–—·").union(.whitespaces))
    return rest.isEmpty ? nil : rest
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

        // Number only real Desktops, and say nothing when there is just one.
        let desktops = snapshot.spaces.filter { $0.kind == .desktop }
        let desktopNumber = Dictionary(uniqueKeysWithValues: desktops.enumerated().map { ($1.id, $0 + 1) })

        func place(_ item: Located?) -> EntryPlace {
            guard let item else { return EntryPlace(kind: .unknown, isCurrent: false) }
            guard let space = item.space else { return EntryPlace(kind: .minimized, isCurrent: false) }
            if space.kind == .fullScreen { return EntryPlace(kind: .fullScreen, isCurrent: space.isCurrent) }
            let number = desktops.count > 1 ? desktopNumber[space.id] : nil
            return EntryPlace(kind: .desktop(number: number), isCurrent: space.isCurrent)
        }

        var groups: [AppGroup] = []

        for (pid, items) in located {
            let name = items.first?.record.appName ?? "App"
            let bundleID = bundleIDs[pid]

            if let bundleID, let windows = browsers[bundleID], !windows.isEmpty {
                let matched = BrowserWindowMatcher.match(windows, to: items.map(\.record))
                let byID = Dictionary(items.map { ($0.record.id, $0) }, uniquingKeysWith: { first, _ in first })
                let places = windows.map { place(matched[$0.id].flatMap { byID[$0.id] }) }
                let profiles = windows.map { profileName(fromWindowTitle: matched[$0.id]?.title ?? "", appName: name) }

                // "Work · Full screen", "Personal", or "Window 2" when nothing better is known.
                let headings = windows.indices.map { i -> String in
                    let base = profiles[i] ?? "Window \(i + 1)"
                    return places[i].label.isEmpty ? base : "\(base) · \(places[i].label)"
                }
                let duplicates = Dictionary(grouping: headings, by: { $0 }).mapValues(\.count)
                var seen: [String: Int] = [:]
                var entries: [Entry] = []

                for (i, window) in windows.enumerated() {
                    let p = places[i]
                    let record = matched[window.id]
                    seen[headings[i], default: 0] += 1
                    let section = (duplicates[headings[i]] ?? 1) > 1 ? "\(headings[i]) (\(seen[headings[i]]!))" : headings[i]

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
