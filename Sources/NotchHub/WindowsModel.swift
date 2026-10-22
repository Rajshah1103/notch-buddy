import AppKit
import WindowEngine

@MainActor
final class WindowsModel: ObservableObject {
    @Published private(set) var snapshot = Snapshot.empty
    @Published private(set) var groups: [AppGroup] = []
    @Published private(set) var icons: [Int32: NSImage] = [:]
    @Published private(set) var thumbnails: [UInt32: NSImage] = [:]
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
    private var browserWindows: [String: [BrowserWindow]] = [:]
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
        let rebuilt = AppGroupBuilder.build(
            snapshot: snapshot, browsers: browserWindows, bundleIDs: bundleIDs, recents: recents,
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
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
            if windows != browserWindows || denied != browsersNeedingAccess {
                browserWindows = windows
                browsersNeedingAccess = denied
                rebuildGroups()
            }
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
        }
    }

    // MARK: - Actions

    func perform(_ entry: Entry) {
        switch entry.target {
        case .window(let window, let space):
            let provider = provider
            Task { await provider.focus(window, in: space) }
        case .tab(let tab, let bundleID):
            browserProvider.activate(tab, bundleID: bundleID)
        case .launch(let app):
            provider.open(app)
        }
    }

    func switchTo(_ space: SpaceInfo) {
        provider.switchTo(space)
    }

    /// For the snapshot tool: load data directly.
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
