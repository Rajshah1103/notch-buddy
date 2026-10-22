import CoreGraphics
import ScreenCaptureKit

/// Live window previews via ScreenCaptureKit. Needs Screen Recording; without it every call
/// returns only what is already cached, so callers fall back to icons.
public actor ThumbnailService {
    private var cache: [UInt32: (image: CGImage, taken: Date)] = [:]
    private let freshFor: TimeInterval = 3

    public init() {}

    public func cached() -> [UInt32: CGImage] {
        cache.mapValues(\.image)
    }

    /// Captures any window in `ids` whose cached image is stale and returns everything cached.
    public func refresh(_ ids: [UInt32], maxWidth: Int = 360) async -> [UInt32: CGImage] {
        guard CGPreflightScreenCaptureAccess() else { return cached() }
        let stale = ids.filter { id in
            guard let entry = cache[id] else { return true }
            return Date().timeIntervalSince(entry.taken) > freshFor
        }
        guard !stale.isEmpty,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return cached() }

        let windows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        for id in stale {
            guard let window = windows[id], window.frame.width > 0, window.frame.height > 0 else { continue }
            let config = SCStreamConfiguration()
            let scale = CGFloat(maxWidth) / window.frame.width
            config.width = maxWidth
            config.height = max(1, Int(window.frame.height * scale))
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: window)
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                cache[id] = (image, Date())
            }
        }
        return cached()
    }
}
