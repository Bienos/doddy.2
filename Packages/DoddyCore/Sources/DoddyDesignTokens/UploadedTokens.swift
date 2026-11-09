import Foundation

/// The app's palette: what `Theme` reads (and the notification extension and the wallpaper).
///
/// - **Light:** Brand Guidelines V2.2 (`design/brand-v2.2/`, ADR-556), the same values as
///   `CandidateColorRole`, which the site and Doddy Web are generated from, so the app, its widgets,
///   the site and the web share one palette (owner, 9 Nov 2026, decision
///   `2026-11-09-remove-old-design-leftovers`, D2). Before, the app's light paper was `#F5EFE2`, its
///   ink `#080808` and its orange `#EC803F` (the numbered-asset preview of 10 Oct).
/// - **Orange:** the brand's `#FF6A00` in both appearances. Decoration only, never text.
/// - **Dark:** the numbered-asset night palette, unchanged until the owner decides on the guide's
///   night `#16171C` (brand review item 3b).
public enum UploadedColorRole: CaseIterable, Sendable {
    case readingInk, canvas, orangeCue, secondaryText, quietSurface, separator, accentText, confirmed, error

    public func hex(_ scheme: CandidateColorScheme) -> HexColor {
        if scheme == .light || self == .orangeCue { return brand.hex(scheme) }
        let dark: String
        switch self {
        case .readingInk: dark = "#F5EFE2"
        case .canvas: dark = "#1D1C19"
        case .orangeCue: dark = "#FF6A00"
        case .secondaryText: dark = "#BDB7AA"
        case .quietSurface: dark = "#292720"
        case .separator: dark = "#49453D"
        case .accentText: dark = "#EC9A68"
        case .confirmed: dark = "#97CEA6"
        case .error: dark = "#FFA98E"
        }
        return HexColor(hex: dark)!
    }

    /// The Brand Guidelines V2.2 role this one takes its light value (and the orange) from.
    public var brand: CandidateColorRole {
        switch self {
        case .readingInk: .readingInk
        case .canvas: .canvas
        case .orangeCue: .orangeCue
        case .secondaryText: .secondaryText
        case .quietSurface: .quietSurface
        case .separator: .separator
        case .accentText: .accentText
        case .confirmed: .confirmed
        case .error: .error
        }
    }

    public static let textRoles: [Self] = [.readingInk, .secondaryText, .accentText, .confirmed, .error]
}
