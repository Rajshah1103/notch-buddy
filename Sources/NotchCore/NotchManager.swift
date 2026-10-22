import AppKit
import SwiftUI

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One overlay panel for one screen, with hover state.
private final class NotchController {
    let state: NotchState
    private let panel: NotchPanel
    private var collapseWork: DispatchWorkItem?
    private var wasInPrefetchZone = false

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

        let hosting = NSHostingView(rootView: NotchShell(state: state, content: content(state)))
        hosting.frame = NSRect(origin: .zero, size: geometry.panelFrame.size)
        panel.contentView = hosting
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
            setExpanded(true)
            return true
        }
        return false
    }

    private func setExpanded(_ expanded: Bool) {
        collapseWork?.cancel()
        collapseWork = nil
        guard state.isExpanded != expanded else { return }
        panel.ignoresMouseEvents = !expanded
        state.isExpanded = expanded
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
        controllers = NSScreen.screens.map {
            NotchController(screen: $0, expandedSize: expandedSize, content: content)
        }
    }

    private func handleMouseMoved() {
        let point = NSEvent.mouseLocation
        var expanded = false
        var prefetch = false
        for controller in controllers {
            if controller.enteredPrefetchZone(point) { prefetch = true }
            if controller.mouseMoved(to: point) { expanded = true }
        }
        if prefetch { onPrefetch() }
        if expanded { onExpand() }
    }
}
