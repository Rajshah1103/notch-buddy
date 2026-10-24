import CoreGraphics

/// The notch outline: it flares outward at the top so it melts into the screen edge, with rounded
/// bottom corners, like the Dynamic Island. Every `progress` yields a path with the same structure,
/// so Core Animation can interpolate between the collapsed and expanded outlines.
enum NotchPath {
    static func make(panelSize: CGSize, collapsed: CGSize, expanded: CGSize, progress: CGFloat, liveExtra: CGFloat = 0, bubble: CGSize? = nil) -> CGPath {
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * progress }
        // With a bubble the resting pill is wider and grows downward below the notch.
        let restW = bubble.map { max($0.width, collapsed.width + 2 * liveExtra) } ?? collapsed.width + 2 * liveExtra
        let restH = bubble.map { collapsed.height + $0.height } ?? collapsed.height
        let w = lerp(restW, expanded.width)
        let h = lerp(restH, expanded.height)
        let x0 = (panelSize.width - w) / 2
        let t = min(lerp(0, 12), h / 2, w / 4)
        let b = min(lerp(bubble != nil ? 24 : (liveExtra > 0 ? 12 : 9), 28), h / 2, w / 4)      // rounder when ears widen the pill

        // Built top-down (y grows downward), then flipped into layer coordinates.
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x0, y: 0))
        p.addLine(to: CGPoint(x: x0 + w, y: 0))
        p.addQuadCurve(to: CGPoint(x: x0 + w - t, y: t), control: CGPoint(x: x0 + w - t, y: 0))
        p.addLine(to: CGPoint(x: x0 + w - t, y: h - b))
        p.addArc(tangent1End: CGPoint(x: x0 + w - t, y: h), tangent2End: CGPoint(x: x0 + w - t - b, y: h), radius: b)
        p.addLine(to: CGPoint(x: x0 + t + b, y: h))
        p.addArc(tangent1End: CGPoint(x: x0 + t, y: h), tangent2End: CGPoint(x: x0 + t, y: h - b), radius: b)
        p.addLine(to: CGPoint(x: x0 + t, y: t))
        p.addQuadCurve(to: CGPoint(x: x0, y: 0), control: CGPoint(x: x0 + t, y: 0))
        p.closeSubpath()

        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: panelSize.height)
        return p.copy(using: &flip) ?? p
    }
}
