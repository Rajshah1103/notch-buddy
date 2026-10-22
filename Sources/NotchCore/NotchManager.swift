import AppKit
import QuartzCore
import SwiftUI

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One overlay panel for one screen, with hover state.
private final class NotchController {
    let state: NotchState
    private let panel: NotchPanel
    private let contentHost: NSView
    private let outline = CAShapeLayer()     // masks the material and content to the notch shape
    private let edge = CAShapeLayer()        // hairline that defines the shape on any wallpaper
    private let panelSize: CGSize
    private var collapseWork: DispatchWorkItem?
    private var wasInPrefetchZone = false
    private var intentWork: DispatchWorkItem?
    /// Called after the notch opens from hover.
    var onExpanded: (() -> Void)?

    /// The pointer must rest on the notch this long before it opens, so brushing past it on the way
    /// to menu bar icons does nothing. Short enough not to be felt.
    private let intentDelay: TimeInterval = 0.06

    /// How long the pointer may stray outside the open notch before it collapses.
    private let collapseDelay: TimeInterval = 0.25

    init(screen: NSScreen, expandedSize: CGSize, content: (NotchState) -> AnyView) {
        let geometry = NotchGeometry(screen: screen, expandedSize: expandedSize)
        state = NotchState(geometry: geometry)

        panel = NotchPanel(contentRect: geometry.panelFrame,
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.level = .statusBar + 1
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        panelSize = geometry.panelFrame.size
        let bounds = NSRect(origin: .zero, size: panelSize)
        let root = NSView(frame: bounds)
        root.wantsLayer = true

        // The material: the same translucent glass macOS uses for popovers. It follows light/dark,
        // the wallpaper behind it, and the Reduce Transparency setting. `.active` keeps it from
        // going flat, because this panel never becomes the active window.
        let material = NSVisualEffectView(frame: bounds)
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.autoresizingMask = [.width, .height]

        let body = content(state)
            .frame(width: geometry.expandedSize.width, height: geometry.expandedSize.height, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        contentHost = NSHostingView(rootView: body)
        contentHost.frame = bounds
        contentHost.autoresizingMask = [.width, .height]
        contentHost.wantsLayer = true
        contentHost.layer?.opacity = 0
        contentHost.isHidden = true

        let clip = NSView(frame: bounds)
        clip.wantsLayer = true
        clip.autoresizingMask = [.width, .height]
        clip.addSubview(material)
        clip.addSubview(contentHost)

        outline.frame = bounds
        outline.fillColor = NSColor.black.cgColor
        outline.path = NotchPath.make(panelSize: panelSize, collapsed: geometry.collapsedSize,
                                      expanded: geometry.expandedSize, progress: 0)
        clip.layer?.mask = outline
        root.addSubview(clip)

        edge.frame = bounds
        edge.fillColor = nil
        edge.lineWidth = 0.5
        edge.path = outline.path
        edge.opacity = 0
        root.layer?.addSublayer(edge)

        panel.contentView = root
        panel.orderFrontRegardless()
        state.collapseHandler = { [weak self] in self?.collapse() }
    }

    deinit { panel.orderOut(nil) }

    /// True once per entry into the zone around the notch.
    func enteredPrefetchZone(_ point: NSPoint) -> Bool {
        let inside = state.geometry.prefetchFrame.contains(point)
        defer { wasInPrefetchZone = inside }
        return inside && !wasInPrefetchZone
    }

    /// Returns true when the notch just expanded.
    func mouseMoved(to point: NSPoint) -> Bool {
        let g = state.geometry
        if state.isExpanded {
            if g.openFrame.contains(point) {
                collapseWork?.cancel()
                collapseWork = nil
            } else if collapseWork == nil {
                let work = DispatchWorkItem { [weak self] in self?.setExpanded(false) }
                collapseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
            }
            return false
        }
        if g.triggerFrame.contains(point) {
            if intentWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    self?.intentWork = nil
                    self?.setExpanded(true)
                    self?.onExpanded?()
                }
                intentWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + intentDelay, execute: work)
            }
        } else {
            intentWork?.cancel()
            intentWork = nil
        }
        return false
    }

    private func setExpanded(_ expanded: Bool) {
        collapseWork?.cancel()
        collapseWork = nil
        guard state.isExpanded != expanded else { return }
        panel.ignoresMouseEvents = !expanded
        state.isExpanded = expanded
        animateContent(expanded: expanded)
    }

    /// Grows the outline and fades the content with Core Animation: no SwiftUI work per frame, and
    /// starting from the on-screen value keeps it smooth if the pointer flicks in and out.
    private func animateContent(expanded: Bool) {
        guard let layer = contentHost.layer else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let g = state.geometry

        // Outline (and the hairline that follows it).
        let target = NotchPath.make(panelSize: panelSize, collapsed: g.collapsedSize,
                                    expanded: g.expandedSize, progress: expanded ? 1 : 0)
        let fromPath = outline.presentation()?.path ?? outline.path
        let timing = expanded ? CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
                              : CAMediaTimingFunction(name: .easeOut)
        let duration: CFTimeInterval = reduceMotion ? 0.15 : (expanded ? 0.34 : 0.2)

        for shape in [outline, edge] {
            shape.removeAnimation(forKey: "path")
            shape.path = target
            let grow = CABasicAnimation(keyPath: "path")
            grow.fromValue = fromPath
            grow.toValue = target
            grow.duration = duration
            grow.timingFunction = timing
            shape.add(grow, forKey: "path")
        }
        edge.strokeColor = NSColor.labelColor.withAlphaComponent(0.16).cgColor
        edge.opacity = expanded ? 1 : 0

        // Content.
        let current = layer.presentation()
        let fromOpacity = current?.opacity ?? layer.opacity
        let fromTransform = current?.transform ?? layer.transform
        let toOpacity: Float = expanded ? 1 : 0
        let toTransform = (expanded || reduceMotion) ? CATransform3DIdentity : CATransform3DMakeTranslation(0, 8, 0)

        if expanded { contentHost.isHidden = false }
        layer.removeAllAnimations()

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, !self.state.isExpanded else { return }
            self.contentHost.isHidden = true
        }
        layer.opacity = toOpacity
        layer.transform = toTransform

        let delay: CFTimeInterval = expanded ? 0.04 : 0   // lets the shape lead
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromOpacity
        fade.toValue = toOpacity
        let move = CABasicAnimation(keyPath: "transform")
        move.fromValue = fromTransform
        move.toValue = toTransform
        for animation in [fade, move] {
            animation.duration = reduceMotion ? 0.15 : (expanded ? 0.22 : 0.1)
            animation.timingFunction = timing
            animation.beginTime = CACurrentMediaTime() + delay
            animation.fillMode = .backwards
        }
        layer.add(fade, forKey: "fade")
        layer.add(move, forKey: "move")
        CATransaction.commit()
    }

    func collapse() { setExpanded(false) }
}

/// Owns one notch panel per screen and keeps them in sync with display changes.
public final class NotchManager {
    private let expandedSize: CGSize
    private let content: (NotchState) -> AnyView
    private let onExpand: () -> Void
    private let onPrefetch: () -> Void
    private var controllers: [NotchController] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?

    public init(expandedSize: CGSize,
                onPrefetch: @escaping () -> Void,
                onExpand: @escaping () -> Void,
                content: @escaping (NotchState) -> AnyView) {
        self.expandedSize = expandedSize
        self.onPrefetch = onPrefetch
        self.onExpand = onExpand
        self.content = content
    }

    public func start() {
        rebuild()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuild() }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.handleMouseMoved()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMoved()
            return event
        }
    }

    public func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        controllers.removeAll()
    }

    private func rebuild() {
        controllers = NSScreen.screens.map { screen in
            let controller = NotchController(screen: screen, expandedSize: expandedSize, content: content)
            controller.onExpanded = { [weak self] in self?.onExpand() }
            return controller
        }
    }

    private func handleMouseMoved() {
        let point = NSEvent.mouseLocation
        var prefetch = false
        for controller in controllers {
            if controller.enteredPrefetchZone(point) { prefetch = true }
            _ = controller.mouseMoved(to: point)
        }
        if prefetch { onPrefetch() }
    }
}
