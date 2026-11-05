import XCTest
@testable import DoddyCore

final class WelcomePathDataTests: XCTestCase {
    func testAbsoluteCommandsAndImplicitRepeats() {
        let segments = WelcomePathData.parse("M10 20 V30 H40 L50 60 70 80 Z")
        XCTAssertEqual(segments, [
            .move(x: 10, y: 20), .line(x: 10, y: 30), .line(x: 40, y: 30),
            .line(x: 50, y: 60), .line(x: 70, y: 80), .close,
        ])
    }

    func testRelativeCommandsAndCurves() {
        let segments = WelcomePathData.parse("m 5,5 l 10 0 v 10 q 5 5 10 0 c 1 2 3 4 5 6")
        XCTAssertEqual(segments, [
            .move(x: 5, y: 5), .line(x: 15, y: 5), .line(x: 15, y: 15),
            .quad(cx: 20, cy: 20, x: 25, y: 15),
            .cubic(c1x: 26, c1y: 17, c2x: 28, c2y: 19, x: 30, y: 21),
        ])
    }

    func testNegativeAndDecimalNumbersRunTogether() {
        let segments = WelcomePathData.parse("M1.5-2.5L-3 4")
        XCTAssertEqual(segments, [.move(x: 1.5, y: -2.5), .line(x: -3, y: 4)])
    }

    func testAnUnsupportedOrBrokenPathIsNilNotHalfDrawn() {
        XCTAssertNil(WelcomePathData.parse("M0 0 a 6 6 0 0 1 6 -6"), "arcs are not supported")
        XCTAssertNil(WelcomePathData.parse("M0"), "a missing number")
        XCTAssertNil(WelcomePathData.parse("10 20"), "numbers before any command")
        XCTAssertNil(WelcomePathData.parse(""))
    }

    func testTheWelcomesOwnPathsAllParse() {
        // The placeholder Warsaw line and the pigeon (design: Figma frames, prompts/WELCOME_FLOW_2026-10-22.md).
        let paths = [
            "M50 130 V122 H74 V130 M56 122 V40 M68 122 V40 M52 40 H72 M62 40 V24 M56 31 H68",
            "M120 130 V76 L132 64 L144 76 L156 64 L168 76 V130 M172 130 V58 H180 V50 H190 V44 H202 V50 H212 V58 H222 V130 M226 130 V82 Q253 54 280 82 V130",
            "M430 130 V62 H452 V130 M460 130 V38 H486 V130 M494 130 V78 H516 V130",
            "M650 130 V102 H668 V86 H684 V72 H696 V34 H700 V10 L704 34 H708 V72 H720 V86 H736 V102 H754 V130",
            "M830 130 V80 L842 68 L854 80 L866 68 L878 80 V130 M886 130 V60 H894 V52 H906 V60 H916 V130 M922 130 V86 Q946 62 970 86 V130",
            "M8 22 C8 14 16 11 24 12.5 C30 13.5 33 16 35 20 L42 27 L29 27.5 C22 31 12 29 8 22 Z",
            "M20 29 V33 M26 29 V33",
            "M37.5 11 L43 13 L37.5 14.5 Z",
        ]
        for path in paths {
            XCTAssertNotNil(WelcomePathData.parse(path), path)
        }
    }
}
