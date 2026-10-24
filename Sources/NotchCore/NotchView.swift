import SwiftUI

public final class NotchState: ObservableObject {
    @Published public var isExpanded = false
    /// True while the notch is open for typing (hotkey or the Search button): it holds keyboard
    /// focus and stays open until dismissed.
    @Published public var isSearching = false
    /// True while a panel needs the keyboard (a text field): like searching, it holds focus and
    /// keeps the notch open, but shows no search UI.
    @Published public var isTyping = false
    /// Extra width on each side of the collapsed notch while a live activity shows (0 when none).
    @Published public var liveExtra: CGFloat = 0
    /// Size of the pop-out bubble under the collapsed notch while an event is announced; nil when none shows.
    @Published public var bubbleSize: CGSize?
    /// A panel (by integration id) asked for by a click on a bubble; the open notch shows it, then clears this.
    @Published public var requestedPanel: String?
    public let geometry: NotchGeometry
    /// Set by the controller; content calls these after the user picks something.
    var collapseHandler: () -> Void = {}
    var searchHandler: (Bool) -> Void = { _ in }
    /// Receives the pointer position inside the open notch (points, origin at its top-left), or nil when it
    /// is outside. SwiftUI's own hover tracking does not fire in a panel that is never the active window, so
    /// the content does its own hit testing from this.
    public var pointerHandler: ((CGPoint?) -> Void)?
    var typingHandler: (Bool) -> Void = { _ in }
    var openPanelHandler: (String) -> Void = { _ in }
    /// Called when the pointer enters or leaves the bubble, so it can stay up while you read it.
    public var bubbleHoverHandler: ((Bool) -> Void)?

    public func collapse() { collapseHandler() }
    public func setSearching(_ on: Bool) { searchHandler(on) }
    public func setTyping(_ on: Bool) { typingHandler(on) }
    /// Opens the notch on this integration's panel (a bubble was clicked).
    public func openPanel(_ id: String) { openPanelHandler(id) }

    public init(geometry: NotchGeometry) {
        self.geometry = geometry
    }
}
