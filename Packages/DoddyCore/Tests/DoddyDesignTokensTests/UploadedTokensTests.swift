import XCTest
@testable import DoddyDesignTokens

final class UploadedTokensTests: XCTestCase {
    func testSelectedPaperAndInkMatchPreview() {
        XCTAssertEqual(UploadedColorRole.canvas.hex(.light), HexColor(hex: "#F5EFE2"))
        XCTAssertEqual(UploadedColorRole.readingInk.hex(.light), HexColor(hex: "#080808"))
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
