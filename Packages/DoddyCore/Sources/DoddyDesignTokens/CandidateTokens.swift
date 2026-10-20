import Foundation

/// CANDIDATE design tokens from `design/interface-v1.2/docs/DESIGN-SYSTEM.md (deleted 20 Oct 2026, ADR-548; see git history)` (Pocket Notebook).
/// Not an approved brand. Nothing here is from `assets/brand_candidate/` (historical palette),
/// per docs/design/CANONICAL_DESIGN_DIRECTION.md. Bright orange is decoration, never body text.
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
        case .readingInk: ("#171715", "#FFF7E9")
        case .canvas: ("#FFF7E9", "#171F29")
        case .orangeCue: ("#F58A24", "#F58A24")
        case .secondaryText: ("#655F56", "#C5BCAD")
        case .quietSurface: ("#F5EAD8", "#252E39")
        case .separator: ("#DFD5C6", "#414953")
        case .accentText: ("#A64B00", "#FFB56B")
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
