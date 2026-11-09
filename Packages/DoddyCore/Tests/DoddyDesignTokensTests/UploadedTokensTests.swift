import XCTest
@testable import DoddyDesignTokens

final class UploadedTokensTests: XCTestCase {
    /// Light is Brand Guidelines V2.2 (decision 2026-11-09-remove-old-design-leftovers, D2): the
    /// same paper, ink and orange as the site and Doddy Web.
    func testLightIsTheBrandPalette() {
        XCTAssertEqual(UploadedColorRole.canvas.hex(.light), HexColor(hex: "#FFF7E9"))
        XCTAssertEqual(UploadedColorRole.readingInk.hex(.light), HexColor(hex: "#171715"))
        XCTAssertEqual(UploadedColorRole.orangeCue.hex(.light), HexColor(hex: "#FF6A00"))
        for role in UploadedColorRole.allCases {
            XCTAssertEqual(role.hex(.light), role.brand.hex(.light), "\(role) follows the site's \(role.brand)")
        }
    }

    /// Dark waits for the owner (brand review item 3b); only the orange is the brand's.
    func testDarkKeepsTheNightPaletteWithTheBrandOrange() {
        XCTAssertEqual(UploadedColorRole.canvas.hex(.dark), HexColor(hex: "#1D1C19"))
        XCTAssertEqual(UploadedColorRole.readingInk.hex(.dark), HexColor(hex: "#F5EFE2"))
        XCTAssertEqual(UploadedColorRole.orangeCue.hex(.dark), HexColor(hex: "#FF6A00"))
    }

    func testReadableRolesOnBothSurfacesAndAppearances() {
        for scheme in CandidateColorScheme.allCases {
            for role in UploadedColorRole.textRoles {
                for surface in [UploadedColorRole.canvas, .quietSurface] {
                    XCTAssertGreaterThanOrEqual(role.hex(scheme).contrastRatio(against: surface.hex(scheme)), 4.5,
                                                "\(role) on \(surface), \(scheme)")
                }
            }
        }
    }
}
