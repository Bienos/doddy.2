import SwiftUI
import UIKit
import DoddyDesignTokens

/// CANDIDATE semantic colours (Pocket Notebook, docs/design/CANONICAL_DESIGN_DIRECTION.md).
/// Values live in `DoddyDesignTokens` so contrast is unit-tested; this file only adapts them.
enum Theme {
    static var ink: Color { .candidate(.readingInk) }
    static var canvas: Color { .candidate(.canvas) }
    static var secondaryText: Color { .candidate(.secondaryText) }
    static var quietSurface: Color { .candidate(.quietSurface) }
    static var separator: Color { .candidate(.separator) }
    static var accentText: Color { .candidate(.accentText) }
    static var confirmed: Color { .candidate(.confirmed) }
    static var error: Color { .candidate(.error) }
    /// Decoration only (underlines, dots, props). Never body text.
    static var orangeCue: Color { .candidate(.orangeCue) }
}

extension Color {
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
