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

/// Black shape that flares outward at the top so it melts into the screen edge, with rounded
/// bottom corners, like the Dynamic Island.
///
/// It animates by interpolating its own outline between the collapsed and expanded sizes, so the
/// animation redraws a path instead of re-running SwiftUI layout for everything inside the notch.
struct NotchShape: Shape {
    var progress: CGFloat
    let collapsed: CGSize
    let expanded: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * progress }

    func path(in rect: CGRect) -> Path {
        let w = lerp(collapsed.width, expanded.width)
        let h = lerp(collapsed.height, expanded.height)
        let frame = CGRect(x: rect.midX - w / 2, y: rect.minY, width: w, height: h)
        let t = min(lerp(0, 12), h / 2, w / 4)
        let b = min(lerp(9, 28), h / 2, w / 4)

        var path = Path()
        path.move(to: CGPoint(x: frame.minX, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY))
        path.addQuadCurve(to: CGPoint(x: frame.maxX - t, y: frame.minY + t),
                          control: CGPoint(x: frame.maxX - t, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX - t, y: frame.maxY - b))
        path.addArc(center: CGPoint(x: frame.maxX - t - b, y: frame.maxY - b), radius: b,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: frame.minX + t + b, y: frame.maxY))
        path.addArc(center: CGPoint(x: frame.minX + t + b, y: frame.maxY - b), radius: b,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: frame.minX + t, y: frame.minY + t))
        path.addQuadCurve(to: CGPoint(x: frame.minX, y: frame.minY),
                          control: CGPoint(x: frame.minX + t, y: frame.minY))
        path.closeSubpath()
        return path
    }
}

/// The animated black backdrop. Only this view animates in SwiftUI; the content above it is
/// faded by Core Animation (see NotchController), so opening costs almost nothing per frame.
struct NotchBackdrop: View {
    @ObservedObject var state: NotchState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let g = state.geometry
        NotchShape(progress: state.isExpanded ? 1 : 0, collapsed: g.collapsedSize, expanded: g.expandedSize)
            .fill(.black)
            .animation(reduceMotion
                       ? .easeInOut(duration: 0.15)
                       : .spring(response: 0.32, dampingFraction: 0.82),
                       value: state.isExpanded)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
