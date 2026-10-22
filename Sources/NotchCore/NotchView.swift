import SwiftUI

public final class NotchState: ObservableObject {
    @Published public var isExpanded = false
    public let geometry: NotchGeometry

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }
}

/// Black shape with a flat top and rounded bottom corners, like the hardware notch.
struct NotchShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(bottomRadius, rect.height / 2, rect.width / 2)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct NotchShell<Content: View>: View {
    @ObservedObject var state: NotchState
    let content: Content

    var body: some View {
        let g = state.geometry
        let size = state.isExpanded ? g.expandedSize : g.collapsedSize

        ZStack(alignment: .top) {
            NotchShape(bottomRadius: state.isExpanded ? 24 : 8)
                .fill(.black)
                .frame(width: size.width, height: size.height)

            if state.isExpanded {
                content
                    .padding(.top, g.collapsedSize.height)
                    .frame(width: g.expandedSize.width, height: g.expandedSize.height)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.isExpanded)
    }
}
