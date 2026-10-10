import Foundation

/// Owner-selected numbered-asset preview palette (10 October 2026). Historical
/// CandidateColorRole remains intact for the archived Pocket Notebook reference.
public enum UploadedColorRole: CaseIterable, Sendable {
    case readingInk, canvas, orangeCue, secondaryText, quietSurface, separator, accentText, confirmed, error

    public func hex(_ scheme: CandidateColorScheme) -> HexColor {
        let pair: (String, String)
        switch self {
        case .readingInk: pair = ("#080808", "#F5EFE2")
        case .canvas: pair = ("#F5EFE2", "#1D1C19")
        case .orangeCue: pair = ("#EC803F", "#EC803F")
        case .secondaryText: pair = ("#6B655B", "#BDB7AA")
        case .quietSurface: pair = ("#EEE7D9", "#292720")
        case .separator: pair = ("#D8D1C3", "#49453D")
        case .accentText: pair = ("#A64B19", "#EC9A68")
        case .confirmed: pair = ("#326746", "#97CEA6")
        case .error: pair = ("#9C3928", "#FFA98E")
        }
        return HexColor(hex: scheme == .light ? pair.0 : pair.1)!
    }

    public static let textRoles: [Self] = [.readingInk, .secondaryText, .accentText, .confirmed, .error]
}
