import XCTest
@testable import DoddyDesignTokens

final class CandidateTokensTests: XCTestCase {
    func testHexParsing() {
        XCTAssertEqual(HexColor(hex: "#F7F2E9"), HexColor(red: 247, green: 242, blue: 233))
        XCTAssertEqual(HexColor(hex: "0B0B0B"), HexColor(red: 11, green: 11, blue: 11))
        XCTAssertNil(HexColor(hex: "#FFF"))
        XCTAssertNil(HexColor(hex: "#GGGGGG"))
        XCTAssertNil(HexColor(hex: ""))
    }

    func testContrastReferenceValues() {
        let black = HexColor(red: 0, green: 0, blue: 0), white = HexColor(red: 255, green: 255, blue: 255)
        XCTAssertEqual(black.contrastRatio(against: white), 21, accuracy: 0.001)
        XCTAssertEqual(white.contrastRatio(against: white), 1, accuracy: 0.001)
    }

    func testMatchesIndependentlyComputedContrastFigures() {
        // Computed outside Swift (Python, WCAG 2.x formula) from the v1.3_COMPLETE values; 2 dp.
        let cases: [(CandidateColorRole, CandidateColorRole, CandidateColorScheme, Double)] = [
            (.readingInk, .canvas, .light, 17.65), (.secondaryText, .canvas, .light, 7.82),
            (.secondaryText, .quietSurface, .light, 8.58), (.accentText, .canvas, .light, 4.58),
            (.confirmed, .canvas, .light, 5.95), (.error, .canvas, .light, 6.10),
            (.readingInk, .canvas, .dark, 16.38), (.secondaryText, .canvas, .dark, 9.41),
            (.secondaryText, .quietSurface, .dark, 8.59), (.accentText, .canvas, .dark, 6.99),
            (.confirmed, .canvas, .dark, 10.17), (.error, .canvas, .dark, 10.01),
        ]
        for (fg, bg, scheme, expected) in cases {
            let ratio = fg.hex(scheme).contrastRatio(against: bg.hex(scheme))
            XCTAssertEqual(ratio, expected, accuracy: 0.01, "\(fg) on \(bg) (\(scheme))")
        }
    }

    func testEveryTextRoleMeetsAA45OnCanvasInBothSchemes() {
        for scheme in CandidateColorScheme.allCases {
            for role in CandidateColorRole.textRoles {
                let ratio = role.hex(scheme).contrastRatio(against: CandidateColorRole.canvas.hex(scheme))
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(role) on canvas (\(scheme)) = \(ratio)")
            }
        }
    }

    func testSecondaryTextAndAccentTextMeetAA45OnQuietSurface() {
        for scheme in CandidateColorScheme.allCases {
            for role in [CandidateColorRole.readingInk, .secondaryText, .accentText] {
                let ratio = role.hex(scheme).contrastRatio(against: CandidateColorRole.quietSurface.hex(scheme))
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(role) on quietSurface (\(scheme)) = \(ratio)")
            }
        }
    }

    func testBrightOrangeIsNotUsableAsBodyText() {
        // Documents why `orangeCue` is decoration-only: it fails 4.5:1 on the light canvas (2.34:1).
        let ratio = CandidateColorRole.orangeCue.hex(.light).contrastRatio(against: CandidateColorRole.canvas.hex(.light))
        XCTAssertLessThan(ratio, 4.5)
        XCTAssertFalse(CandidateColorRole.textRoles.contains(.orangeCue))
    }

    func testTapTargetMeetsMinimum() {
        XCTAssertGreaterThanOrEqual(CandidateMetrics.primaryControlHeight, CandidateMetrics.minimumTapTarget)
    }
}
