import SwiftUI

public final class NotchState: ObservableObject {
    @Published public var isExpanded = false
    /// True while the notch is open for typing (hotkey or the Search button): it holds keyboard
    /// focus and stays open until dismissed.
    @Published public var isSearching = false
    public let geometry: NotchGeometry
    /// Set by the controller; content calls these after the user picks something.
    var collapseHandler: () -> Void = {}
    var searchHandler: (Bool) -> Void = { _ in }

    public func collapse() { collapseHandler() }
    public func setSearching(_ on: Bool) { searchHandler(on) }

    public init(geometry: NotchGeometry) {
        self.geometry = geometry
    }
}
