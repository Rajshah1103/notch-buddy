import SwiftUI

/// Design tokens. The notch is pure black so it merges with the hardware cutout; everything
/// on it is built from white at different opacities plus one accent.
enum Theme {
    static let accent = Color(red: 0.04, green: 0.52, blue: 1.0)          // #0A84FF
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.58)                  // 6.9:1 on black

    static let cardRadius: CGFloat = 18
    static let cardPadding: CGFloat = 10
    /// Concentric: inner radius = outer radius − padding.
    static let tileRadius: CGFloat = cardRadius - cardPadding

    static let tileWidth: CGFloat = 132
    static let tileHeight: CGFloat = 82
    static let tileGap: CGFloat = 10

    /// Material that catches light on its top edge, like glass.
    static let cardFill = LinearGradient(
        colors: [Color.white.opacity(0.11), Color.white.opacity(0.04)],
        startPoint: .top, endPoint: .bottom)
    static let cardEdge = LinearGradient(
        colors: [Color.white.opacity(0.26), Color.white.opacity(0.05)],
        startPoint: .top, endPoint: .bottom)
    static let currentEdge = LinearGradient(
        colors: [accent.opacity(0.9), accent.opacity(0.18)],
        startPoint: .top, endPoint: .bottom)

    /// Strong ease-out, so motion starts fast and feels responsive.
    static let easeOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)

    /// Set by the snapshot tool so views render their settled state without animating in.
    nonisolated(unsafe) static var skipReveal = false
}
