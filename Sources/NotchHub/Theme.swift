import SwiftUI

/// Design tokens. The notch is pure black so it merges with the hardware cutout; everything
/// on it is built from white at different opacities plus one accent.
enum Theme {
    static let accent = Color(red: 0.04, green: 0.52, blue: 1.0)          // #0A84FF
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.58)                  // 6.9:1 on black
    static let cardFill = Color.white.opacity(0.07)
    static let cardStroke = Color.white.opacity(0.08)
    static let currentStroke = Color.white.opacity(0.18)
    static let rowHover = Color.white.opacity(0.10)

    static let cardRadius: CGFloat = 16
    static let cardPadding: CGFloat = 8
    /// Concentric: inner radius = outer radius − padding.
    static let rowRadius: CGFloat = cardRadius - cardPadding

    static let cardWidth: CGFloat = 196
    static let rowHeight: CGFloat = 40
}
