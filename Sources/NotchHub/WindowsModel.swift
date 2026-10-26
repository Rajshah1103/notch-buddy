import AppKit
import WindowEngine

@MainActor
final class WindowsModel: ObservableObject {
    @Published private(set) var snapshot = Snapshot.empty
    @Published private(set) var groups: [AppGroup] = []
    @Published private(set) var icons: [Int32: NSImage] = [:]
    @Published private(set) var thumbnails: [UInt32: NSImage] = [:]
    /// Sharp captures of the few windows recently hovered, for the big preview pane.
    @Published private(set) var largeThumbnails: [UInt32: NSImage] = [:]
    private var largeOrder: [UInt32] = []
    private var largeWork: Task<Void, Never>?
    @Published private(set) var accessibilityGranted = Permissions.accessibilityGranted
    @Published private(set) var screenRecordingGranted = Permissions.screenRecordingGranted
    /// Browsers that are running but have not been allowed to share their tabs (Automation).
    @Published private(set) var browsersNeedingAccess: [String] = []

    /// The snapshot tool turns these off so a design render never reads real windows or tabs.
    var capturesThumbnails = true
    var readsBrowsers = true

    private let provider = SystemWindowProvider()
    private let browserProvider = BrowserTabsProvider()
    private let thumbnailService = ThumbnailService()
    /// Pictures of tabs from when they were last in front; a background tab cannot be captured live.
    private let tabShots = TabShotCache()
    @Published private(set) var tabShotsRevision = 0
    private var watchedTab: (key: String, reads: Int)?
    private var watchInFlight = false
    private var browserWindows: [String: [BrowserWindow]] = [:]
    /// Entries just closed, hidden until the next real read confirms they are gone.
    private var hiddenEntryIDs: Set<String> = []
    private var recents: [Int32] = []
    private var inFlight = false
    private var lastRefresh = Date.distantPast
    private var lastBrowserRefresh = Date.distantPast

    /// How old data may be before hovering triggers another read.
    private let maxAge: TimeInterval = 1.5
    private let browserMaxAge: TimeInterval = 2

    /// Most-recently-used order drives the app row: your next target is usually one you just left.
    func startTrackingRecents() {
        if let front = NSWorkspace.shared.frontmostApplication { recents = [front.processIdentifier] }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.noteActivated(app.processIdentifier) }
        }
    }

    /// A window can only be captured while its Space is on screen. Capturing whenever the Space changes
    /// means previews fill in as you move around, so they are ready the first time you open the notch there.
    func startTrackingSpaces() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Let the Space transition animation finish so the windows are really on screen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MainActor.assumeIsolated { self?.refresh(previews: true, force: true) }
            }
        }
    }

    private func noteActivated(_ pid: Int32) {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        recents.removeAll { $0 == pid }
        recents.insert(pid, at: 0)
        rebuildGroups()
    }

    /// Stale-while-revalidate: the view keeps showing the last data while new data loads.
    /// Called when the pointer nears the notch (data only) and when it opens (data and previews).
    func refresh(previews: Bool, force: Bool = false) {
        refreshBrowsers()
        if !force, Date().timeIntervalSince(lastRefresh) < maxAge {
            if previews { refreshThumbnails() }
            return
        }
        guard !inFlight else { return }
        inFlight = true
        let provider = provider
        Task.detached {
            let snapshot = PerfProbe.measure("window snapshot") { provider.snapshot() }
            await MainActor.run {
                self.apply(snapshot)
                if previews { self.refreshThumbnails() }
            }
        }
    }

    private func apply(_ new: Snapshot) {
        inFlight = false
        lastRefresh = Date()
        accessibilityGranted = Permissions.accessibilityGranted
        screenRecordingGranted = Permissions.screenRecordingGranted
        guard new != snapshot else { return }   // nothing changed: skip the re-render
        snapshot = new

        let pids = Set(new.spaces.flatMap(\.windows).map(\.pid))
            .union(new.minimized.map(\.pid))
            .union(new.windowlessApps.map(\.pid))
        for pid in pids where icons[pid] == nil {
            if let icon = NSRunningApplication(processIdentifier: pid)?.icon { icons[pid] = icon }
        }

        let live = Set((new.spaces.flatMap(\.windows) + new.minimized).map(\.id))
        if !thumbnails.keys.allSatisfy(live.contains) {
            thumbnails = thumbnails.filter { live.contains($0.key) }
        }
        rebuildGroups()
    }

    private func rebuildGroups() {
        let pids = Set(snapshot.spaces.flatMap(\.windows).map(\.pid))
            .union(snapshot.minimized.map(\.pid))
            .union(snapshot.windowlessApps.map(\.pid))
        var bundleIDs: [Int32: String] = [:]
        for pid in pids {
            if let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier { bundleIDs[pid] = id }
        }
        bundleIDs.merge(previewBundleIDs) { _, preview in preview }
        var rebuilt = AppGroupBuilder.build(
            snapshot: snapshot, browsers: browserWindows, bundleIDs: bundleIDs, recents: recents,
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        if !hiddenEntryIDs.isEmpty { rebuilt = rebuilt.compactMap { $0.removingEntries(hiddenEntryIDs) } }
        let hiddenApps = AppSettings.shared.hiddenApps
        if !hiddenApps.isEmpty { rebuilt.removeAll { hiddenApps.contains($0.bundleID ?? $0.name) } }
        if rebuilt != groups { groups = rebuilt }
    }

    // MARK: - Browser tabs

    private func refreshBrowsers() {
        guard readsBrowsers, Date().timeIntervalSince(lastBrowserRefresh) >= browserMaxAge else { return }
        lastBrowserRefresh = Date()
        let running = BrowserTabsProvider.supportedBundleIDs.filter {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
        }
        let provider = browserProvider
        Task {
            var windows: [String: [BrowserWindow]] = [:]
            var denied: [String] = []
            let start = Date()
            defer { PerfProbe.log("browser tabs read took \(Int(Date().timeIntervalSince(start) * 1000)) ms") }
            for id in running.sorted() {
                switch await provider.windows(bundleID: id) {
                case .success(let found): windows[id] = found
                case .failure(.notAuthorized): denied.append(id)
                case .failure: break
                }
            }
            hiddenEntryIDs.removeAll()          // fresh data from the browser is the truth again
            if windows != browserWindows || denied != browsersNeedingAccess {
                browserWindows = windows
                browsersNeedingAccess = denied
            }
            rebuildGroups()
        }
    }

    // MARK: - Thumbnails

    /// Only windows on the current Desktop can be captured, so only those are asked for.
    private func refreshThumbnails() {
        guard capturesThumbnails else { return }
        let ids = snapshot.spaces.filter(\.isCurrent).flatMap(\.windows).map(\.id)
        let service = thumbnailService
        Task {
            let images = await service.capture(ids)
            guard !images.isEmpty else { return }
            var updated = thumbnails
            for (id, image) in images {
                updated[id] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            }
            thumbnails = updated   // one publish for the whole batch
            rememberActiveTabs(images)
        }
    }

    /// Keeps the picture of each browser's front tab, so it can be shown later when that tab is in the back.
    private func rememberActiveTabs(_ images: [UInt32: CGImage]) {
        let titles = Dictionary(snapshot.spaces.flatMap(\.windows).map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        var stored = false
        for group in groups where group.isBrowserWithTabs {
            for entry in group.entries {
                guard case .tab(let tab, _) = entry.target, tab.isActive,
                      let id = entry.thumbnailWindowID, let image = images[id],
                      !TabShotKey.isPrivateWindow(title: titles[id] ?? "") else { continue }
                if tabShots.store(image, key: TabShotKey.key(tabTitle: tab.title)) { stored = true }
            }
        }
        if stored { tabShotsRevision += 1 }
    }

    /// The remembered picture of a background tab, with how long ago it was taken.
    func tabShot(for entry: Entry) -> (image: NSImage, age: String)? {
        guard entry.thumbnailWindowID == nil, case .tab(let tab, _) = entry.target,
              let shot = tabShots.shot(for: TabShotKey.key(tabTitle: tab.title)),
              let image = NSImage(data: shot.data) else { return nil }
        return (image, TabShotCache.age(shot.taken))
    }

    /// While a browser is in front, remembers its tab once the title has held still for two reads (a tab
    /// that is still loading keeps changing it), and again every 30 seconds so the picture stays recent.
    func startWatchingTabs() {
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchFrontTab() }
        }
    }

    private func watchFrontTab() {
        guard capturesThumbnails, readsBrowsers, !watchInFlight, Permissions.screenRecordingGranted,
              let front = NSWorkspace.shared.frontmostApplication, let bundleID = front.bundleIdentifier,
              BrowserTabsProvider.supportedBundleIDs.contains(bundleID) else { watchedTab = nil; return }
        watchInFlight = true
        let provider = provider, pid = front.processIdentifier, name = front.localizedName ?? ""
        Task.detached {
            let snapshot = provider.snapshot()
            await MainActor.run { self.finishWatching(snapshot, pid: pid, appName: name) }
        }
    }

    private func finishWatching(_ snapshot: Snapshot, pid: Int32, appName: String) {
        watchInFlight = false
        // The front-most real window: helper and popup windows have no title or are tiny.
        let candidates = snapshot.spaces.filter(\.isCurrent).flatMap(\.windows)
            .filter { $0.pid == pid && !$0.title.isEmpty && $0.bounds.width > 300 && $0.bounds.height > 200 }
        guard let window = candidates.min(by: { $0.order < $1.order }),
              !TabShotKey.isPrivateWindow(title: window.title) else { return }
        let key = TabShotKey.key(windowTitle: window.title, appName: appName)
        guard !key.isEmpty else { return }
        if watchedTab?.key != key { watchedTab = (key, 1); return }
        if let shot = tabShots.shot(for: key), Date().timeIntervalSince(shot.taken) < 30 { return }
        let service = thumbnailService, id = window.id
        Task {
            guard let image = await service.capture([id], maxWidth: 560)[id] else { return }   // throttled just after a capture; the next read retries
            if tabShots.store(image, key: key) { tabShotsRevision += 1; PerfProbe.log("remembered front tab (\(tabShots.count) kept)") }
        }
    }

    /// Fetches a sharp capture of one window shortly after the pointer settles on it, so sweeping across
    /// a list does not fire a capture per row.
    func requestLarge(_ windowID: UInt32?) {
        largeWork?.cancel()
        guard capturesThumbnails, let windowID else { return }
        if largeThumbnails[windowID] != nil, Date().timeIntervalSince(largeTaken[windowID] ?? .distantPast) < 3 { return }
        let service = thumbnailService
        largeWork = Task {
            try? await Task.sleep(nanoseconds: 90_000_000)
            let began = Date()
            guard !Task.isCancelled else { return }
            guard let image = await service.captureLarge(windowID) else { PerfProbe.log("sharp preview: capture returned nothing (window not capturable now)"); return }
            PerfProbe.log("sharp preview captured: \(image.width)x\(image.height) in \(Int(Date().timeIntervalSince(began) * 1000)) ms")
            largeThumbnails[windowID] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            largeTaken[windowID] = Date()
            largeOrder.removeAll { $0 == windowID }
            largeOrder.append(windowID)
            while largeOrder.count > 4 { largeThumbnails[largeOrder.removeFirst()] = nil }   // keep memory small
        }
    }
    private var largeTaken: [UInt32: Date] = [:]

    // MARK: - Actions

    func perform(_ entry: Entry) {
        switch entry.target {
        case .window(let window, let space):
            let provider = provider
            PerfProbe.log("perform: focus window")
            Task { await provider.focus(window, in: space); PerfProbe.log("focus finished") }
        case .tab(let tab, let bundleID):
            PerfProbe.log("perform: activate tab")
            browserProvider.activate(tab, bundleID: bundleID)
        case .launch(let app):
            PerfProbe.log("perform: open app")
            provider.open(app)
        }
    }

    /// Closes a tab or window. The row disappears at once; a moment later the real list is read back, so a
    /// close that did not happen (an app asked to save, or the window could not be reached) reappears.
    func close(_ entry: Entry) {
        switch entry.target {
        case .tab(let tab, let bundleID):
            browserProvider.close(tab, bundleID: bundleID)
        case .window(let window, _):
            guard provider.close(window) else { return }     // not reachable (another Space): nothing to hide
        case .launch:
            return
        }
        hiddenEntryIDs.insert(entry.id)
        rebuildGroups()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            MainActor.assumeIsolated {
                self.lastBrowserRefresh = .distantPast
                self.lastRefresh = .distantPast
                self.refresh(previews: false, force: true)
            }
        }
    }

    /// Applies a change to which apps are hidden straight away.
    func hiddenAppsChanged() { rebuildGroups() }

    func switchTo(_ space: SpaceInfo) {
        provider.switchTo(space)
    }

    /// The first Desktop, where "home" is: what a swipe back across your Spaces ends on. Taken from the Space
    /// list, which can lag a swipe, so it is never used to decide whether to go: pressing it on home is a no-op.
    var homeSpace: SpaceInfo? {
        let displayID = snapshot.spaces.first(where: \.isCurrent)?.displayID
        return snapshot.spaces.filter { $0.kind == .desktop && (displayID == nil || $0.displayID == displayID) }.min { $0.index < $1.index }
    }

    /// Takes you home, as a swipe back across your Spaces would: onto the first Desktop, with its Dock and wallpaper.
    /// The provider makes a real Space transition; setting the Space id alone leaves a full-screen app drawn behind.
    func goHome() {
        guard let home = homeSpace else { return }
        let provider = provider, spaces = snapshot.spaces
        Task {
            let account = await provider.goHome(to: home, among: spaces)
            PerfProbe.log("go home: \(account); front \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
        }
    }

    /// For the snapshot tool: an icon for an invented app.
    func setPreviewIcon(_ image: NSImage, for pid: Int32) { icons[pid] = image }
    private var previewBundleIDs: [Int32: String] = [:]
    func setPreviewBundleID(_ id: String, for pid: Int32) { previewBundleIDs[pid] = id }

    /// For the snapshot tool: load data directly.
    /// For design renders: pretend this tab was last in front a few minutes ago.
    func rememberForPreview(_ image: CGImage, tabTitle: String, minutesAgo: Double) {
        tabShots.store(image, key: TabShotKey.key(tabTitle: tabTitle), at: Date().addingTimeInterval(-minutesAgo * 60))
        tabShotsRevision += 1
    }

    func loadForPreview(_ snapshot: Snapshot, browsers: [String: [BrowserWindow]], frontApp: String?) {
        capturesThumbnails = false
        readsBrowsers = false
        browserWindows = browsers
        if let frontApp {
            let all = snapshot.spaces.flatMap(\.windows) + snapshot.minimized
            if let pid = all.first(where: { $0.appName == frontApp })?.pid { recents = [pid] }
        }
        apply(snapshot)
        rebuildGroups()
    }
}
