import AppKit
import DoddyDesignTokens
import SwiftUI

/// The same owner-selected palette as the iPhone (`DoddyDesignTokens.UploadedColorRole`, whose
/// contrast is unit-tested), adapted to AppKit's light and dark appearances.
enum MacTheme {
    static var ink: Color { .uploaded(.readingInk) }
    static var secondaryText: Color { .uploaded(.secondaryText) }
    static var quietSurface: Color { .uploaded(.quietSurface) }
    static var separator: Color { .uploaded(.separator) }
    static var accentText: Color { .uploaded(.accentText) }
    static var confirmed: Color { .uploaded(.confirmed) }
    static var error: Color { .uploaded(.error) }
    /// Decoration only (the Save button's fill, dots). Never body text.
    static var orangeCue: Color { .uploaded(.orangeCue) }
}

extension Color {
    static func uploaded(_ role: UploadedColorRole) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = role.hex(isDark ? .dark : .light)
            return NSColor(
                srgbRed: CGFloat(hex.red) / 255, green: CGFloat(hex.green) / 255,
                blue: CGFloat(hex.blue) / 255, alpha: 1)
        })
    }
}
