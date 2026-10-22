import AppKit
import QuartzCore
import SwiftUI

private final class NotchPanel: NSPanel {
    /// Only while searching: hovering must never pull keyboard focus away from what you are typing in.
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// One overlay panel for one screen, with hover state.
private final class NotchController {
    let state: NotchState
    private let panel: NotchPanel
    private let contentHost: NSView
    private let liveHost: NSView
    private var liveExtra: CGFloat = 0
    private let outline = CAShapeLayer()     // masks the material and content to the notch shape
    private let edge = CAShapeLayer()        // hairline that defines the shape on any wallpaper
    private let panelSize: CGSize
    private let screen: NSScreen
    private var collapseWork: DispatchWorkItem?
    private var wasInPrefetchZone = false
    private var intentWork: DispatchWorkItem?
    private var lastSample: (point: NSPoint, time: CFTimeInterval)?
    /// Slower than this (points per second) counts as a deliberate approach.
    private let openSpeed: CGFloat = 500
    var trace: ((String) -> Void)?
    /// Called after the notch opens from hover.
    var onExpanded: (() -> Void)?

    /// When the pointer arrives fast, how long it must then hold still on the notch before it opens.
    /// Brushing past on the way to a menu bar icon never stops, so it never opens. A slow approach
    /// opens immediately regardless. Set by the manager (a user setting); 0 opens as soon as it arrives.
    var intentDelay: TimeInterval = 0.04

    /// How long the pointer may stray outside the open notch before it collapses.
    private let collapseDelay: TimeInterval = 0.25

    init(screen: NSScreen, expandedSize: CGSize, content: (NotchState) -> AnyView, live: (NotchState) -> AnyView) {
        self.screen = screen
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

        // Live activity: shown only while collapsed, in the ears that grow out of the notch.
        liveHost = NSHostingView(rootView: live(state)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        liveHost.frame = bounds
        liveHost.autoresizingMask = [.width, .height]
        liveHost.wantsLayer = true
        liveHost.layer?.opacity = 0

        let clip = NSView(frame: bounds)
        clip.wantsLayer = true
        clip.autoresizingMask = [.width, .height]
        clip.addSubview(material)
        clip.addSubview(liveHost)
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
        state.searchHandler = { [weak self] on in self?.setSearching(on) }
        state.typingHandler = { [weak self] on in self?.setTyping(on) }

        // Clicking anywhere else ends a search.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self, self.state.isSearching || self.state.isTyping else { return }
            self.collapse()
        }
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
        let now = CACurrentMediaTime()
        let speed: CGFloat = lastSample.map {
            hypot(point.x - $0.point.x, point.y - $0.point.y) / CGFloat(max(now - $0.time, 0.001))
        } ?? 0
        lastSample = (point, now)

        if state.isSearching || state.isTyping { return false }
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
        if g.triggerFrame.insetBy(dx: -liveExtra, dy: 0).contains(point) {
            trace?("pointer in zone, speed \(Int(speed)) pt/s")
            if speed < openSpeed {
                // A slow, deliberate approach: open at once.
                openNow()
            } else {
                // Moving fast: either on the way somewhere else (a menu bar icon) or about to stop here.
                // Open only if the pointer comes to rest; any further movement restarts the wait.
                intentWork?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.openNow() }
                intentWork = work
                if intentDelay <= 0 { work.perform() } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + intentDelay, execute: work)
                }
            }
        } else {
            intentWork?.cancel()
            intentWork = nil
        }
        return false
    }

    private func openNow() {
        intentWork?.cancel()
        intentWork = nil
        guard !state.isExpanded else { return }
        trace?("opening")
        setExpanded(true)
        onExpanded?()
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
        let target = NotchPath.make(panelSize: panelSize, collapsed: g.collapsedSize, expanded: g.expandedSize,
                                    progress: expanded ? 1 : 0, liveExtra: liveExtra)
        let timing = expanded ? CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
                              : CAMediaTimingFunction(name: .easeOut)
        animateOutline(to: target, duration: reduceMotion ? 0.12 : (expanded ? 0.26 : 0.18), timing: timing)
        edge.strokeColor = NSColor.labelColor.withAlphaComponent(0.16).cgColor
        edge.opacity = expanded ? 1 : (liveExtra > 0 ? 1 : 0)
        fadeLive(visible: !expanded && liveExtra > 0, quickly: expanded)

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

        let delay: CFTimeInterval = 0   // content and shape start together: waiting reads as lag
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromOpacity
        fade.toValue = toOpacity
        let move = CABasicAnimation(keyPath: "transform")
        move.fromValue = fromTransform
        move.toValue = toTransform
        for animation in [fade, move] {
            animation.duration = reduceMotion ? 0.12 : (expanded ? 0.14 : 0.08)
            animation.timingFunction = timing
            animation.beginTime = CACurrentMediaTime() + delay
            animation.fillMode = .backwards
        }
        layer.add(fade, forKey: "fade")
        layer.add(move, forKey: "move")
        CATransaction.commit()
    }

    private func animateOutline(to target: CGPath, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        let fromPath = outline.presentation()?.path ?? outline.path
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
    }

    private func fadeLive(visible: Bool, quickly: Bool) {
        guard let layer = liveHost.layer else { return }
        let from = layer.presentation()?.opacity ?? layer.opacity
        let to: Float = visible ? 1 : 0
        layer.removeAnimation(forKey: "fade")
        layer.opacity = to
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = to
        fade.duration = quickly ? 0.08 : 0.25
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "fade")
    }

    /// A live activity (like Claude working) widens the collapsed notch into the space beside it.
    func setLive(extra: CGFloat) {
        guard extra != liveExtra else { return }
        liveExtra = extra
        state.liveExtra = extra
        guard !state.isExpanded else { return }   // takes effect when the notch next collapses
        let g = state.geometry
        let target = NotchPath.make(panelSize: panelSize, collapsed: g.collapsedSize, expanded: g.expandedSize,
                                    progress: 0, liveExtra: extra)
        animateOutline(to: target, duration: 0.38, timing: CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1))
        edge.opacity = extra > 0 ? 1 : 0
        edge.strokeColor = NSColor.labelColor.withAlphaComponent(0.16).cgColor
        fadeLive(visible: extra > 0, quickly: false)
    }

    func collapse() {
        if state.isSearching { setSearching(false) }
        if state.isTyping { setTyping(false) }
        setExpanded(false)
    }

    /// Opens the notch for typing (or closes it). The panel takes keyboard focus but never
    /// activates the app, so the app you were in stays in front and gets focus back afterwards.
    func setSearching(_ on: Bool) {
        guard state.isSearching != on else { return }
        intentWork?.cancel(); intentWork = nil
        collapseWork?.cancel(); collapseWork = nil
        if on {
            panel.allowsKey = true
            state.isSearching = true
            setExpanded(true)
            panel.makeKeyAndOrderFront(nil)
            onExpanded?()
        } else {
            state.isSearching = false
            panel.resignKey()
            panel.allowsKey = false
        }
    }

    /// For a panel with a text field: take keyboard focus and keep the notch open, without a search UI.
    func setTyping(_ on: Bool) {
        guard state.isTyping != on, !state.isSearching else { return }
        intentWork?.cancel(); intentWork = nil
        collapseWork?.cancel(); collapseWork = nil
        if on {
            panel.allowsKey = true
            state.isTyping = true
            panel.makeKeyAndOrderFront(nil)
        } else {
            state.isTyping = false
            panel.resignKey()
            panel.allowsKey = false
        }
    }

    var isSearching: Bool { state.isSearching }
    var containsMouse: Bool { screen.frame.contains(NSEvent.mouseLocation) }
}

/// Owns one notch panel per screen and keeps them in sync with display changes.
public final class NotchManager {
    private let expandedSize: CGSize
    private let content: (NotchState) -> AnyView
    private let liveContent: (NotchState) -> AnyView
    private let onExpand: () -> Void
    private let onPrefetch: () -> Void
    private var controllers: [NotchController] = []
    private var liveExtraWidth: CGFloat = 0

    /// Debug hook: called with short messages about hover decisions.
    public var trace: ((String) -> Void)? {
        didSet { controllers.forEach { $0.trace = trace } }
    }

    /// Seconds the pointer must rest on the notch before it opens (0 = immediately).
    public var hoverDelay: TimeInterval = 0.04 {
        didSet { controllers.forEach { $0.intentDelay = hoverDelay } }
    }
    private var globalMonitor: Any?
    private var localMonitor: Any?

    public init(expandedSize: CGSize,
                onPrefetch: @escaping () -> Void,
                onExpand: @escaping () -> Void,
                content: @escaping (NotchState) -> AnyView,
                liveContent: @escaping (NotchState) -> AnyView = { _ in AnyView(EmptyView()) }) {
        self.liveContent = liveContent
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

    /// Widens the collapsed notch by `extra` points on each side to show a live activity; nil removes it.
    public func setLive(extra: CGFloat?) {
        liveExtraWidth = extra ?? 0
        controllers.forEach { $0.setLive(extra: liveExtraWidth) }
    }

    /// Hotkey entry point: opens search on the screen the pointer is on, or closes it.
    public func toggleSearch() {
        let target = controllers.first(where: \.containsMouse) ?? controllers.first
        guard let target else { return }
        if target.isSearching {
            target.collapse()
        } else {
            controllers.forEach { $0.collapse() }
            target.setSearching(true)
        }
    }

    public func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        controllers.removeAll()
    }

    private func rebuild() {
        controllers = NSScreen.screens.map { screen in
            let controller = NotchController(screen: screen, expandedSize: expandedSize, content: content, live: liveContent)
            controller.onExpanded = { [weak self] in self?.onExpand() }
            controller.setLive(extra: liveExtraWidth)
            controller.intentDelay = hoverDelay
            controller.trace = trace
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
