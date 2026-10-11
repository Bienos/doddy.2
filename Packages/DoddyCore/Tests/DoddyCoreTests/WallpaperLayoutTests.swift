import Foundation
import XCTest
@testable import DoddyCore

/// The paper wallpaper (ADR-341): Doddy stands clear of the clock and the controls.
final class WallpaperLayoutTests: XCTestCase {
    func testPixelSizeRoundsAndNeverShrinksBelowTheMinimum() {
        let size = WallpaperLayout.pixelSize(pointWidth: 393, pointHeight: 852, scale: 3)
        XCTAssertEqual(size, .init(width: 1179, height: 2556))
        XCTAssertEqual(WallpaperLayout.pixelSize(pointWidth: 10, pointHeight: 10, scale: 1),
                       .init(width: WallpaperLayout.minimumSide, height: WallpaperLayout.minimumSide))
    }

    func testFigureStandsBelowTheClockAndAboveTheControls() {
        let layout = WallpaperLayout(canvas: .init(width: 1179, height: 2556))
        // A pose from the pack: its figure box is about 2:3.
        let frame = layout.figureFrame(aspect: 0.62)
        XCTAssertGreaterThan(frame.y, 2556 * WallpaperLayout.clockBand, "below the clock band")
        XCTAssertLessThanOrEqual(frame.maxY, 2556 * (1 - WallpaperLayout.controlsBand), "above the controls")
        XCTAssertEqual(frame.height, 2556 * WallpaperLayout.figureShare, accuracy: 0.001)
        XCTAssertEqual(frame.width / frame.height, 0.62, accuracy: 0.001, "aspect kept")
        XCTAssertEqual(frame.x + frame.width / 2, 1179 / 2, accuracy: 0.001, "centred")
        XCTAssertGreaterThanOrEqual(frame.x, 0)
        XCTAssertLessThanOrEqual(frame.maxX, 1179)
    }

    func testAVeryWideFigureIsNarrowedToFit() {
        let layout = WallpaperLayout(canvas: .init(width: 600, height: 1000))
        let frame = layout.figureFrame(aspect: 4)
        XCTAssertLessThanOrEqual(frame.width, 600 * 0.8 + 0.001)
        XCTAssertEqual(frame.width / frame.height, 4, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(frame.x, 0)
    }

    func testAccentRuleSitsJustUnderTheClockBand() {
        let layout = WallpaperLayout(canvas: .init(width: 1179, height: 2556))
        let rule = layout.accentRule()
        XCTAssertGreaterThan(rule.y, 2556 * WallpaperLayout.clockBand)
        XCTAssertGreaterThanOrEqual(rule.height, 2)
        XCTAssertEqual(rule.x + rule.width / 2, 1179 / 2, accuracy: 0.001)
    }

    func testPapersAreTwo() {
        XCTAssertEqual(WallpaperLayout.Paper.allCases, [.light, .dark])
    }
}
