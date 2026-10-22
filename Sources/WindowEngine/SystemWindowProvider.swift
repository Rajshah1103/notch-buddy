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

        let records = windowRecords(connection: cid, regularPIDs: regularPIDs)
        let minimizedIDs = minimizedWindowIDs(pids: Array(regularPIDs))

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
                result.append(SpaceInfo(id: id, index: index, displayID: displayID, isCurrent: id == current))
                index += 1
            }
        }
        return result
    }

    private func windowRecords(connection cid: Int32, regularPIDs: Set<Int32>) -> [WindowRecord] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

        return infos.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? UInt32,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let appName = info[kCGWindowOwnerName as String] as? String,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 80, bounds.height > 80
            else { return nil }

            let title = info[kCGWindowName as String] as? String ?? ""
            // Skip helper windows of accessory apps unless they have a real title.
            guard regularPIDs.contains(pid) || !title.isEmpty else { return nil }

            let spaceIDs = CGSCopySpacesForWindows(cid, 7, [id] as CFArray) as? [Int] ?? []
            return WindowRecord(id: id, pid: pid, appName: appName, title: title, spaceIDs: spaceIDs)
        }
    }

    private func minimizedWindowIDs(pids: [Int32]) -> Set<UInt32> {
        guard AXIsProcessTrusted() else { return [] }
        var ids = Set<UInt32>()
        for pid in pids {
            for window in axWindows(pid: pid) where axBool(window, kAXMinimizedAttribute) == true {
                if let id = windowID(of: window) { ids.insert(id) }
            }
        }
        return ids
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
            // Windows on another Space only become reachable once that Space is current,
            // so poll briefly instead of waiting a fixed time.
            let attempts = switchedSpace ? 20 : 1
            for attempt in 0..<attempts {
                if let element = axWindows(pid: window.pid).first(where: { windowID(of: $0) == window.id }) {
                    AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    AXUIElementPerformAction(element, kAXRaiseAction as CFString)
                    break
                }
                if attempt < attempts - 1 { try? await Task.sleep(nanoseconds: 15_000_000) }
            }
        }
        app?.activate()
    }

    /// Opens (or reopens) an app that has no window, like clicking its Dock icon.
    public func open(_ app: AppRecord) {
        if let running = NSRunningApplication(processIdentifier: app.pid), running.isHidden {
            running.unhide()
        }
        guard let url = app.bundleURL else {
            NSRunningApplication(processIdentifier: app.pid)?.activate()
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
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
