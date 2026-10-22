import SwiftUI

/// Design tokens. Everything is adaptive: the notch is system material, so text and fills come
/// from the system's own semantic colors and follow light/dark, the wallpaper and the accent color.
enum Theme {
    static let accent = Color.accentColor
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary

    /// Subtle fills that read on both light and dark material.
    static let fillHover = Color.primary.opacity(0.10)
    static let fillSelected = Color.primary.opacity(0.13)
    static let fillQuiet = Color.primary.opacity(0.06)
}
