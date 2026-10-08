import XCTest
@testable import DoddyDesignTokens

final class CandidateTokensTests: XCTestCase {
    func testHexParsing() {
        XCTAssertEqual(HexColor(hex: "#FFF7E9"), HexColor(red: 255, green: 247, blue: 233))
        XCTAssertEqual(HexColor(hex: "171715"), HexColor(red: 23, green: 23, blue: 21))
        XCTAssertNil(HexColor(hex: "#FFF"))
        XCTAssertNil(HexColor(hex: "#GGGGGG"))
        XCTAssertNil(HexColor(hex: ""))
    }

    func testContrastReferenceValues() {
        let black = HexColor(red: 0, green: 0, blue: 0), white = HexColor(red: 255, green: 255, blue: 255)
        XCTAssertEqual(black.contrastRatio(against: white), 21, accuracy: 0.001)
        XCTAssertEqual(white.contrastRatio(against: white), 1, accuracy: 0.001)
    }

    func testMatchesPublishedContrastFigures() {
        // design/interface-v1.2/verification/contrast.json (rounded to 2 dp there).
        let cases: [(CandidateColorRole, CandidateColorRole, CandidateColorScheme, Double)] = [
            (.readingInk, .canvas, .light, 16.87), (.secondaryText, .canvas, .light, 5.94),
            (.secondaryText, .quietSurface, .light, 5.31), (.accentText, .canvas, .light, 5.44),
            (.confirmed, .canvas, .light, 6.24), (.error, .canvas, .light, 6.39),
            (.readingInk, .canvas, .dark, 15.61), (.secondaryText, .canvas, .dark, 8.83),
            (.secondaryText, .quietSurface, .dark, 7.31), (.accentText, .canvas, .dark, 9.55),
            (.confirmed, .canvas, .dark, 9.25), (.error, .canvas, .dark, 9.11),
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
        // Documents why `orangeCue` is decoration-only: it fails 4.5:1 on the light canvas.
        let ratio = CandidateColorRole.orangeCue.hex(.light).contrastRatio(against: CandidateColorRole.canvas.hex(.light))
        XCTAssertLessThan(ratio, 4.5)
        XCTAssertFalse(CandidateColorRole.textRoles.contains(.orangeCue))
    }

    func testTapTargetMeetsMinimum() {
        XCTAssertGreaterThanOrEqual(CandidateMetrics.primaryControlHeight, CandidateMetrics.minimumTapTarget)
    }
}
