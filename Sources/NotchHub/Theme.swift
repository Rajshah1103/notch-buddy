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

extension Color {
    /// `#RRGGBB` (the `#` is optional); nil for anything else.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
