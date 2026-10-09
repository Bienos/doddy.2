import Foundation

/// Colour tokens from the owner-selected brand master: `DODDY_BRAND_SYSTEM_v1.3_COMPLETE.zip`
/// (`doddy.tokens.json`, mirrored in `reference/brand_v1.3_unpacked/v1.3_COMPLETE/`).
/// Layout/roles still follow the Pocket Notebook UI direction. Final logo, icon and character art are NOT
/// approved yet, so these stay "candidate". The historical `assets/brand_candidate/` palette and the
/// smaller v1.3 zip's palette are not used. Bright orange is decoration, never body text.
///
/// Roles the pack does not define are marked DERIVED below. They exist because the pack's own
/// success/error fills fail 4.5:1 as text on its paper (2.04:1 and 3.37:1) and it gives no accessible orange.
public struct HexColor: Equatable, Sendable {
    public let red: UInt8, green: UInt8, blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red; self.green = green; self.blue = blue
    }

    /// Accepts "#RRGGBB" or "RRGGBB"; returns nil for anything else.
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }

    /// WCAG 2.x relative luminance.
    public var relativeLuminance: Double {
        func linear(_ channel: UInt8) -> Double {
            let s = Double(channel) / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2.x contrast ratio, 1...21.
    public func contrastRatio(against other: HexColor) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

public enum CandidateColorScheme: Sendable, CaseIterable { case light, dark }

public enum CandidateColorRole: String, CaseIterable, Sendable {
    case readingInk, canvas, orangeCue, secondaryText, quietSurface, separator, accentText, confirmed, error

    public func hex(_ scheme: CandidateColorScheme) -> HexColor {
        let (light, dark) = pair
        return HexColor(hex: scheme == .light ? light : dark)!
    }

    /// (light, dark) hex values.
    var pair: (String, String) {
        switch self {
        // Pack values: ink #0B0B0B, paper #F7F2E9, orange #FF7A00, gray600 #4B4B4B, gray300 #BABABA,
        // gray100 #E6E6E6, white #FFFDF7, dark #151515, slate #1E1E1E.
        case .readingInk: ("#0B0B0B", "#F7F2E9")
        case .canvas: ("#F7F2E9", "#151515")
        case .orangeCue: ("#FF7A00", "#FF7A00")
        case .secondaryText: ("#4B4B4B", "#BABABA")
        case .quietSurface: ("#FFFDF7", "#1E1E1E")
        case .separator: ("#E6E6E6", "#4B4B4B")
        // DERIVED (not in pack): light = #FF7A00 darkened to reach 4.5:1 on canvas and quietSurface;
        // dark = the pack orange itself (6.99:1 on #151515).
        case .accentText: ("#B05400", "#FF7A00")
        // DERIVED (not in pack): accessible text/icon variants for the pack's success/error hues.
        // Carried over from the v1.2 interface system, where they were contrast-verified.
        case .confirmed: ("#326746", "#97CEA6")
        case .error: ("#A3342E", "#FFAAA1")
        }
    }

    /// Roles that carry readable text and must meet 4.5:1 on the canvas.
    public static let textRoles: [CandidateColorRole] = [.readingInk, .secondaryText, .accentText, .confirmed, .error]
}

public enum CandidateMetrics {
    /// Minimum interactive target, in points (Apple HIG).
    public static let minimumTapTarget = 44.0
    public static let primaryControlHeight = 54.0
    public static let horizontalMargin = 24.0
    public static let spacing: [Double] = [4, 8, 12, 16, 24, 32]
}
