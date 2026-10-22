import CoreGraphics
import ScreenCaptureKit

/// Live window previews via ScreenCaptureKit. Needs Screen Recording; without it nothing is captured
/// and callers fall back to icons. macOS can only capture windows on the current Space.
public actor ThumbnailService {
    private var lastCapture: [UInt32: Date] = [:]
    private var shareable: (windows: [CGWindowID: SCWindow], taken: Date)?

    private let freshFor: TimeInterval = 4
    private let shareableFor: TimeInterval = 5

    public init() {}

    /// Captures windows in `ids` that have no recent capture. Returns only the new images.
    public func capture(_ ids: [UInt32], maxWidth: Int = 640) async -> [UInt32: CGImage] {
        guard CGPreflightScreenCaptureAccess() else { return [:] }
        let stale = ids.filter { Date().timeIntervalSince(lastCapture[$0] ?? .distantPast) > freshFor }
        guard !stale.isEmpty, let windows = await windowIndex() else { return [:] }

        var captured: [UInt32: CGImage] = [:]
        for id in stale {
            lastCapture[id] = Date()   // also throttles windows that fail to capture
            guard let window = windows[id], window.frame.width > 0, window.frame.height > 0 else { continue }
            let config = SCStreamConfiguration()
            config.width = maxWidth
            config.height = max(1, Int(window.frame.height * CGFloat(maxWidth) / window.frame.width))
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: window)
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                captured[id] = image
            }
        }
        return captured
    }

    /// One window at high resolution, for the preview pane, which is much bigger than a tile. Only works
    /// for a window on a Space that is on screen right now.
    public func captureLarge(_ id: UInt32, maxWidth: Int = 1400) async -> CGImage? {
        guard CGPreflightScreenCaptureAccess(), let windows = await windowIndex(), let window = windows[id],
              window.frame.width > 0, window.frame.height > 0
        else { return nil }
        let config = SCStreamConfiguration()
        config.width = maxWidth
        config.height = max(1, Int(window.frame.height * CGFloat(maxWidth) / window.frame.width))
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                           configuration: config)
    }

    /// Listing shareable windows is the expensive part of a capture, so reuse it briefly.
    private func windowIndex() async -> [CGWindowID: SCWindow]? {
        if let shareable, Date().timeIntervalSince(shareable.taken) < shareableFor { return shareable.windows }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return nil }
        let index = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        shareable = (index, Date())
        return index
    }
}
