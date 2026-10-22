import AppKit
import WindowEngine

@MainActor
final class WindowsModel: ObservableObject {
    @Published private(set) var snapshot = Snapshot.empty
    @Published private(set) var icons: [Int32: NSImage] = [:]
    @Published private(set) var thumbnails: [UInt32: NSImage] = [:]
    @Published private(set) var accessibilityGranted = Permissions.accessibilityGranted
    @Published private(set) var screenRecordingGranted = Permissions.screenRecordingGranted

    private let provider = SystemWindowProvider()
    private let thumbnailService = ThumbnailService()
    private var inFlight = false
    private var lastRefresh = Date.distantPast

    var allWindowIDs: [UInt32] {
        (snapshot.spaces.flatMap(\.windows) + snapshot.minimized).map(\.id)
    }

    /// Stale-while-revalidate: the view keeps showing the last snapshot while a new one loads.
    /// Called early (pointer near the notch) and again on expand, so data is usually fresh on open.
    func refresh(force: Bool = false) {
        guard !inFlight, force || Date().timeIntervalSince(lastRefresh) > 0.6 else { return }
        inFlight = true
        let provider = provider
        Task.detached {
            let snapshot = provider.snapshot()
            await MainActor.run { self.apply(snapshot) }
        }
    }

    private func apply(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        accessibilityGranted = Permissions.accessibilityGranted
        screenRecordingGranted = Permissions.screenRecordingGranted

        let pids = Set(snapshot.spaces.flatMap(\.windows).map(\.pid))
            .union(snapshot.minimized.map(\.pid))
            .union(snapshot.windowlessApps.map(\.pid))
        for pid in pids where icons[pid] == nil {
            if let icon = NSRunningApplication(processIdentifier: pid)?.icon { icons[pid] = icon }
        }
        inFlight = false
        lastRefresh = Date()
        refreshThumbnails()
    }

    private func refreshThumbnails() {
        let ids = allWindowIDs
        let service = thumbnailService
        Task {
            let images = await service.refresh(ids)
            for (id, image) in images {
                thumbnails[id] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            }
        }
    }

    func focus(_ window: WindowRecord, in space: SpaceInfo?) {
        let provider = provider
        Task { await provider.focus(window, in: space) }
    }

    func open(_ app: AppRecord) {
        provider.open(app)
    }

    /// For the snapshot tool: load data without going through async refresh.
    func loadForPreview(_ snapshot: Snapshot, thumbnails: [UInt32: NSImage]) {
        apply(snapshot)
        self.thumbnails = thumbnails
    }
}
