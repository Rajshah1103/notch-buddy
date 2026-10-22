import SwiftUI

/// Hover for the notch. SwiftUI's `onHover` does not fire in a panel that never becomes the active
/// window (this one must not steal focus), so the notch forwards the pointer position and this does the
/// hit testing: views register their frames, one lookup per pointer move finds the one under it.
@MainActor
final class HoverHub: ObservableObject {
    final class Box {
        var action: (Bool) -> Void
        init(_ action: @escaping (Bool) -> Void) { self.action = action }
    }

    private var frames: [UUID: CGRect] = [:]
    private var boxes: [UUID: Box] = [:]
    /// Everything the pointer is over right now. A row and a button inside it are both hovered, as with
    /// native hover; leaving the button must not end the row's hover.
    private var current: Set<UUID> = []

    func register(_ id: UUID, frame: CGRect, box: Box) {
        frames[id] = frame
        boxes[id] = box
    }

    func unregister(_ id: UUID) {
        frames[id] = nil
        boxes[id] = nil
        current.remove(id)
    }

    /// `point` is in the open notch's coordinates, or nil when the pointer is outside it.
    func pointerMoved(_ point: CGPoint?) {
        let now: Set<UUID> = point.map { p in Set(frames.filter { $0.value.contains(p) }.keys) } ?? []
        guard now != current else { return }
        let left = current.subtracting(now), entered = now.subtracting(current)
        current = now
        for id in left { boxes[id]?.action(false) }
        for id in entered { boxes[id]?.action(true) }
    }
}

private struct HoverHubKey: EnvironmentKey { static let defaultValue: HoverHub? = nil }
extension EnvironmentValues {
    var hoverHub: HoverHub? {
        get { self[HoverHubKey.self] }
        set { self[HoverHubKey.self] = newValue }
    }
}

extension View {
    /// Like `onHover`, but driven by the notch's own pointer tracking. Falls back to `onHover` where there
    /// is no hub (ordinary windows).
    func pointerHover(perform action: @escaping (Bool) -> Void) -> some View {
        modifier(PointerHover(action: action))
    }
}

private struct PointerHover: ViewModifier {
    @Environment(\.hoverHub) private var hub
    @State private var id = UUID()
    @State private var box = HoverHub.Box { _ in }
    let action: (Bool) -> Void

    func body(content: Content) -> some View {
        box.action = action          // always the latest closure, so a row never reports a stale entry
        return Group {
            if let hub {
                content
                    // Reports this view's frame, in the notch's coordinates, whenever it changes.
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("notch")) } action: { [box, id] frame in
                        hub.register(id, frame: frame, box: box)
                    }
                    .onDisappear { [id] in hub.unregister(id) }
            } else {
                content.onHover(perform: action)
            }
        }
    }
}
