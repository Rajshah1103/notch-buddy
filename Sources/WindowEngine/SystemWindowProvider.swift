import AppKit
import ApplicationServices

/// Reads Spaces/windows from macOS and brings a chosen window to the front.
public final class SystemWindowProvider {
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    public init() {}

    // MARK: - Reading

    public func snapshot() -> Snapshot {
        let cid = CGSMainConnectionID()
        let apps = NSWorkspace.shared.runningApplications
        let regular = apps.filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID }
        let regularPIDs = Set(regular.map(\.processIdentifier))

        let ax = accessibilityInfo(pids: Array(regularPIDs))
        let records = windowRecords(connection: cid, regularPIDs: regularPIDs, axTitles: ax.titles)
        let minimizedIDs = ax.minimized

        let regularApps = regular.map {
            AppRecord(pid: $0.processIdentifier, name: $0.localizedName ?? "App", bundleURL: $0.bundleURL)
        }
        return SnapshotBuilder.build(
            spaces: spaces(connection: cid),
            windows: records,
            minimizedIDs: minimizedIDs,
            regularApps: regularApps
        )
    }

    private func spaces(connection cid: Int32) -> [SpaceInfo] {
        guard let displays = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else { return [] }
        var result: [SpaceInfo] = []
        var index = 1
        for display in displays {
            let displayID = display["Display Identifier"] as? String ?? "Main"
            let current = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard let id = space["ManagedSpaceID"] as? Int else { continue }
                // type 0 is a Desktop; type 4 is the Space macOS makes for a full-screen app.
                let kind: SpaceKind = (space["type"] as? Int) == 4 ? .fullScreen : .desktop
                result.append(SpaceInfo(id: id, index: index, displayID: displayID, isCurrent: id == current, kind: kind))
                index += 1
            }
        }
        return result
    }

    private func windowRecords(connection cid: Int32, regularPIDs: Set<Int32>, axTitles: [UInt32: String]) -> [WindowRecord] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

        return infos.enumerated().compactMap { order, info in
            guard let id = info[kCGWindowNumber as String] as? UInt32,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let appName = info[kCGWindowOwnerName as String] as? String,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 80, bounds.height > 80
            else { return nil }

            // Titles from the window server need Screen Recording; Accessibility is the fallback.
            var title = info[kCGWindowName as String] as? String ?? ""
            if title.isEmpty { title = axTitles[id] ?? "" }
            // Skip helper windows of accessory apps unless they have a real title.
            guard regularPIDs.contains(pid) || !title.isEmpty else { return nil }

            let spaceIDs = CGSCopySpacesForWindows(cid, 7, [id] as CFArray) as? [Int] ?? []
            return WindowRecord(id: id, pid: pid, appName: appName, title: title, spaceIDs: spaceIDs, bounds: bounds, order: order)
        }
    }

    /// One Accessibility pass: which windows are minimized, and every readable window title.
    /// Windows on other Spaces are invisible to Accessibility, so those titles come from elsewhere.
    private func accessibilityInfo(pids: [Int32]) -> (minimized: Set<UInt32>, titles: [UInt32: String]) {
        guard AXIsProcessTrusted() else { return ([], [:]) }
        var minimized = Set<UInt32>()
        var titles: [UInt32: String] = [:]
        for pid in pids {
            for window in axWindows(pid: pid) {
                guard let id = windowID(of: window) else { continue }
                if axBool(window, kAXMinimizedAttribute) == true { minimized.insert(id) }
                if let title = axValue(window, kAXTitleAttribute) as? String, !title.isEmpty { titles[id] = title }
            }
        }
        return (minimized, titles)
    }

    // MARK: - Acting

    /// Brings a window to the front: unhides the app, switches Space, unminimizes and raises the window.
    public func focus(_ window: WindowRecord, in space: SpaceInfo?) async {
        let app = NSRunningApplication(processIdentifier: window.pid)
        if app?.isHidden == true { app?.unhide() }

        let switchedSpace = space.map { !$0.isCurrent } ?? false
        if let space, switchedSpace {
            CGSManagedDisplaySetCurrentSpace(CGSMainConnectionID(), space.displayID as CFString, space.id)
        }

        if AXIsProcessTrusted() {
            // Windows on another Space only become reachable once that Space is current, and some
            // apps (Chrome) are slow to report them. Poll briefly, then fall back to activating the app.
            let attempts = switchedSpace ? 6 : 1
            for attempt in 0..<attempts {
                if let element = axWindows(pid: window.pid).first(where: { windowID(of: $0) == window.id }) {
                    AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    AXUIElementPerformAction(element, kAXRaiseAction as CFString)
                    break
                }
                if attempt < attempts - 1 { try? await Task.sleep(nanoseconds: 25_000_000) }
            }
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(window.pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        if let app { bringToFront(app) }
    }

    /// Closes a window by pressing its close button, as clicking it would (the app may ask about unsaved
    /// work). Only possible for windows Accessibility can reach, which means those on the current Space.
    @discardableResult
    public func close(_ window: WindowRecord) -> Bool {
        guard AXIsProcessTrusted(),
              let element = axWindows(pid: window.pid).first(where: { windowID(of: $0) == window.id }),
              let button = axValue(element, kAXCloseButtonAttribute)
        else { return false }
        // swiftlint:disable:next force_cast
        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
    }

    /// Opens (or reopens) an app that has no window, like clicking its Dock icon.
    public func open(_ app: AppRecord) {
        guard let running = NSRunningApplication(processIdentifier: app.pid) else { return }
        if running.isHidden { running.unhide() }
        bringToFront(running)
    }

    /// `NSRunningApplication.activate()` is cooperative on macOS 14+: an app running in the
    /// background, like this one, is often not allowed to bring another app forward. Launch Services
    /// is, and it is exactly what a Dock click uses.
    private func bringToFront(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else { app.activate(); return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// Switches to a Desktop directly, without the swipe animation.
    public func switchTo(_ space: SpaceInfo) {
        CGSManagedDisplaySetCurrentSpace(CGSMainConnectionID(), space.displayID as CFString, space.id)
    }

    // MARK: - Accessibility helpers

    private func axWindows(pid: Int32) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        return axValue(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    private func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return status == .success ? value : nil
    }

    private func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        axValue(element, attribute) as? Bool
    }

    private func windowID(of element: AXUIElement) -> UInt32? {
        var id = CGWindowID(0)
        return _AXUIElementGetWindow(element, &id) == .success ? id : nil
    }
}
