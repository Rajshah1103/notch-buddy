import AppKit

/// Where the notch (or the fallback pill on screens without one) sits on a screen.
public struct NotchGeometry {
    public let hasNotch: Bool
    public let collapsedSize: CGSize
    public let expandedSize: CGSize
    /// Panel frame in screen coordinates. It stays at the expanded size so the open/close
    /// animation happens inside it; clicks pass through while collapsed.
    public let panelFrame: NSRect

    public init(screen: NSScreen, expandedSize: CGSize) {
        let frame = screen.frame
        hasNotch = screen.safeAreaInsets.top > 0

        if hasNotch, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            collapsedSize = CGSize(width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
        } else {
            collapsedSize = CGSize(width: 160, height: 10)
        }

        let width = min(expandedSize.width, frame.width - 40)
        self.expandedSize = CGSize(width: width, height: expandedSize.height)
        panelFrame = NSRect(x: frame.midX - width / 2, y: frame.maxY - expandedSize.height,
                            width: width, height: expandedSize.height)
    }

    /// Mouse-sensitive strip over the collapsed notch, a little generous so it is easy to hit.
    public var triggerFrame: NSRect {
        NSRect(x: panelFrame.midX - collapsedSize.width / 2 - 4,
               y: panelFrame.maxY - collapsedSize.height - 2,
               width: collapsedSize.width + 8,
               height: collapsedSize.height + 4)
    }

    /// Wider zone around the notch; entering it is the cue to load data before the notch opens.
    public var prefetchFrame: NSRect {
        triggerFrame.insetBy(dx: -120, dy: -60).intersection(
            NSRect(x: panelFrame.minX, y: panelFrame.maxY - 200, width: panelFrame.width, height: 200))
    }

    /// Area that keeps the notch open once expanded.
    public var openFrame: NSRect {
        NSRect(x: panelFrame.midX - expandedSize.width / 2,
               y: panelFrame.maxY - expandedSize.height,
               width: expandedSize.width,
               height: expandedSize.height)
    }
}
