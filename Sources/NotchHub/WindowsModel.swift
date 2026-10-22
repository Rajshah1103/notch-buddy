import AppKit
import WindowEngine

@MainActor
final class WindowsModel: ObservableObject {
    @Published private(set) var snapshot = Snapshot.empty
    @Published private(set) var icons: [Int32: NSImage] = [:]
    @Published private(set) var thumbnails: [UInt32: NSImage] = [:]
    @Published private(set) var accessibilityGranted = Permissions.accessibilityGranted
    @Published private(set) var screenRecordingGranted = Permissions.screenRecordingGranted

    /// The snapshot tool turns this off so a design render never captures real window content.
    var capturesThumbnails = true

    private let provider = SystemWindowProvider()
    private let thumbnailService = ThumbnailService()
    private var inFlight = false
    private var lastRefresh = Date.distantPast

    /// How old a snapshot may be before hovering triggers another scan.
    private let maxAge: TimeInterval = 1.5

    /// Stale-while-revalidate: the view keeps showing the last snapshot while a new one loads.
    /// Called when the pointer nears the notch (data only) and when it opens (data and previews).
    func refresh(previews: Bool) {
        if Date().timeIntervalSince(lastRefresh) < maxAge {
            if previews { refreshThumbnails() }
            return
        }
        guard !inFlight else { return }
        inFlight = true
        let provider = provider
        Task.detached {
            let snapshot = provider.snapshot()
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
    }

    /// Only windows on the current Space can be captured, so only those are asked for.
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

    func focus(_ window: WindowRecord, in space: SpaceInfo?) {
        let provider = provider
        Task { await provider.focus(window, in: space) }
    }

    func open(_ app: AppRecord) {
        provider.open(app)
    }

    /// For the snapshot tool: load data directly.
    func loadForPreview(_ snapshot: Snapshot) {
        capturesThumbnails = false
        apply(snapshot)
    }
}
