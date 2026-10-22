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
    public let geometry: NotchGeometry
    /// Set by the controller; content calls these after the user picks something.
    var collapseHandler: () -> Void = {}
    var searchHandler: (Bool) -> Void = { _ in }
    /// Receives the pointer position inside the open notch (points, origin at its top-left), or nil when it
    /// is outside. SwiftUI's own hover tracking does not fire in a panel that is never the active window, so
    /// the content does its own hit testing from this.
    public var pointerHandler: ((CGPoint?) -> Void)?
    var typingHandler: (Bool) -> Void = { _ in }

    public func collapse() { collapseHandler() }
    public func setSearching(_ on: Bool) { searchHandler(on) }
    public func setTyping(_ on: Bool) { typingHandler(on) }

    public init(geometry: NotchGeometry) {
        self.geometry = geometry
    }
}
