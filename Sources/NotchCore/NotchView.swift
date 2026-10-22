import SwiftUI

public final class NotchState: ObservableObject {
    @Published public var isExpanded = false
    public let geometry: NotchGeometry
    /// Set by the controller; content calls `collapse()` after the user picks something.
    var collapseHandler: () -> Void = {}

    public func collapse() { collapseHandler() }

    public init(geometry: NotchGeometry) {
        self.geometry = geometry
    }
}
