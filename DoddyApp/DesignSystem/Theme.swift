import SwiftUI
import UIKit
import DoddyDesignTokens

/// Owner-selected numbered-asset memory journey, 10 October 2026.
/// Values live in `DoddyDesignTokens` so contrast is unit-tested; this file only adapts them.
enum Theme {
    static var ink: Color { .uploaded(.readingInk) }
    static var canvas: Color { .uploaded(.canvas) }
    static var secondaryText: Color { .uploaded(.secondaryText) }
    static var quietSurface: Color { .uploaded(.quietSurface) }
    static var separator: Color { .uploaded(.separator) }
    static var accentText: Color { .uploaded(.accentText) }
    static var confirmed: Color { .uploaded(.confirmed) }
    static var error: Color { .uploaded(.error) }
    /// Decoration only (underlines, dots, props). Never body text.
    static var orangeCue: Color { .uploaded(.orangeCue) }
}

extension Color {
    static func uploaded(_ role: UploadedColorRole) -> Color {
        Color(uiColor: UIColor { traits in
            let scheme: CandidateColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            let hex = role.hex(scheme)
            return UIColor(red: CGFloat(hex.red) / 255, green: CGFloat(hex.green) / 255,
                           blue: CGFloat(hex.blue) / 255, alpha: 1)
        })
    }
    static func candidate(_ role: CandidateColorRole) -> Color {
        Color(uiColor: UIColor { traits in
            let scheme: CandidateColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            let hex = role.hex(scheme)
            return UIColor(
                red: CGFloat(hex.red) / 255, green: CGFloat(hex.green) / 255,
                blue: CGFloat(hex.blue) / 255, alpha: 1)
        })
    }
}
