import XCTest
@testable import DoddyCore

/// MV2: Doddy's spots on the app's surfaces. On the brief's 390 × 844 canvas, laid out as the
/// reference prototype lays it out, each function must give the brief's own number.
final class MotionLayoutTests: XCTestCase {
    func testClearZoneIs48By108AndScalesWithHim() {
        let z = MotionLayout.zone(soles: MotionPoint(x: 195, y: 470), scale: 1)
        XCTAssertEqual(z, MotionRect(x: 171, y: 362, width: 48, height: 108))
        let home = MotionLayout.zone(soles: MotionPoint(x: 195, y: 470), scale: 1.4)
        XCTAssertEqual(home.width, 67.2, accuracy: 1e-9)
        XCTAssertEqual(home.height, 151.2, accuracy: 1e-9)
        XCTAssertEqual(home.maxY, 470)
        XCTAssertEqual(home.midX, 195)
    }

    func testStageSpotIsTheLineCentreAndHisZoneStaysOverTheLine() {
        let line = MotionRect(x: 125, y: 470, width: MotionLayout.stageLineWidth, height: 1)
        XCTAssertEqual(MotionLayout.stageSpotX(line: line), 195)
        let r = MotionLayout.stageStandRange(line: line, scale: 1.4)
        XCTAssertEqual(r.lowerBound, 125 + 33.6, accuracy: 1e-9)
        XCTAssertEqual(r.upperBound, 265 - 33.6, accuracy: 1e-9)
    }

    func testCardSpotIsTheReferenceRuleXAndStaysInTheGutter() {
        // The reference's rules run 24…366 and he stands at x 330.
        let card = MotionRect(x: 24, y: 300, width: 342, height: 120)
        XCTAssertEqual(MotionLayout.cardSpotX(card: card), 330)
        let r = MotionLayout.cardStandRange(card: card)
        XCTAssertTrue(r.contains(330))
        // His zone starts at least 6 pt right of the text column, which ends at the gutter.
        let textColumnEnd = card.maxX - MotionLayout.cardGutter
        let zone = MotionLayout.zone(soles: MotionPoint(x: r.lowerBound, y: card.minY), scale: 1)
        XCTAssertGreaterThanOrEqual(zone.minX, textColumnEnd)
        XCTAssertGreaterThanOrEqual(MotionLayout.zone(soles: MotionPoint(x: 330, y: card.minY), scale: 1).minX - textColumnEnd, 6)
        XCTAssertLessThanOrEqual(MotionLayout.zone(soles: MotionPoint(x: r.upperBound, y: card.minY), scale: 1).maxX, card.maxX)
    }

    func testComposerSpotIsLeftOfSendAndNeverPast284() {
        // The reference composer: 16…374 pt, Send's hit area from x 332.
        let composer = MotionRect(x: 16, y: 660, width: 358, height: 44)
        let send = MotionRect(x: 332, y: 660, width: 42, height: 44)
        let r = MotionLayout.composerStandRange(composer: composer, send: send)
        XCTAssertEqual(r.lowerBound, 44)
        XCTAssertEqual(r.upperBound, 284)
        XCTAssertEqual(MotionLayout.composerSpotX(composer: composer, send: send), 250, accuracy: 1e-9)
        // DECISIONS.md "Microphone button": Send moved to 288, so the spot tops out at 240.
        let moved = MotionRect(x: 288, y: 660, width: 42, height: 44)
        XCTAssertEqual(MotionLayout.composerStandRange(composer: composer, send: moved).upperBound, 240)
        XCTAssertEqual(MotionLayout.composerSpotX(composer: composer, send: moved), 240)
    }

    func testComposerSpotKeeps24PtFromSend() {
        let composer = MotionRect(x: 16, y: 660, width: 358, height: 44)
        let send = MotionRect(x: 332, y: 660, width: 42, height: 44)
        let x = MotionLayout.composerStandRange(composer: composer, send: send).upperBound
        let zone = MotionLayout.zone(soles: MotionPoint(x: x, y: composer.minY), scale: 1)
        XCTAssertTrue(MotionLayout.blocked(zone: zone, by: [send], clearance: MotionLayout.sendClearance - 0.6).isEmpty)
        XCTAssertFalse(MotionLayout.blocked(zone: zone, by: [send], clearance: MotionLayout.sendClearance + 1).isEmpty)
    }

    func testRailSpotIsUnderTheTabAndOnTheBar() {
        let bar = MotionRect(x: 24, y: 724, width: 342, height: 60)
        XCTAssertEqual(MotionLayout.railSpotX(tabCenter: 317, bar: bar), 317)
        XCTAssertEqual(MotionLayout.railSpotX(tabCenter: 30, bar: bar), 48)
        XCTAssertEqual(MotionLayout.railSpotX(tabCenter: 380, bar: bar), 342)
    }

    func testBarSpotKeeps24PtFromItsAction() {
        // DECISIONS.md "“Review ›” hit area": at x 250 his zone ends at 274, so the action starts at 298.
        let bar = MotionRect(x: 0, y: 652, width: 390, height: 56)
        let review = MotionRect(x: 298, y: 652, width: 76, height: 56)
        XCTAssertEqual(MotionLayout.barSpotX(bar: bar, action: review), 250)
        XCTAssertEqual(MotionLayout.barStandRange(bar: bar, action: review).lowerBound, 28)
    }

    func testDetailSpotIsTheCardsRightEnd() {
        let card = MotionRect(x: 24, y: 300, width: 342, height: 200)
        XCTAssertEqual(MotionLayout.detailSpotX(card: card), 330)
    }

    func testBlockedReportsOnlyWhatTheZoneCovers() {
        let zone = MotionLayout.zone(soles: MotionPoint(x: 330, y: 400), scale: 1)
        let text = MotionRect(x: 42, y: 300, width: 240, height: 60) // ends at 282, zone starts at 306
        let icon = MotionRect(x: 320, y: 360, width: 16, height: 16)
        XCTAssertEqual(MotionLayout.blocked(zone: zone, by: [text, icon]), [icon])
        XCTAssertEqual(MotionLayout.blocked(zone: zone, by: [text], clearance: 16), [])
        XCTAssertEqual(MotionLayout.blocked(zone: zone, by: [text], clearance: 25), [text])
    }

    /// A spot on a surface that moves keeps its place along the edge (the stage's centre stays
    /// its centre), and a report that comes back to the old frame brings it back exactly.
    func testACarriedSpotKeepsItsPlaceAlongTheEdge() {
        let portrait = MotionRect(x: 126.5, y: 430, width: 140, height: 1)
        let landscape = MotionRect(x: 356, y: 250, width: 140, height: 1)
        XCTAssertEqual(MotionLayout.carriedX(196.5, from: portrait, to: landscape), landscape.midX)
        XCTAssertEqual(MotionLayout.carriedX(426, from: landscape, to: portrait), portrait.midX)
        // A slide carries any spot by exactly the slide.
        XCTAssertEqual(MotionLayout.carriedX(150, from: portrait, to: landscape), 150 + 229.5, accuracy: 1e-9)
        // A card that grows keeps his fraction of its width.
        let card = MotionRect(x: 24, y: 300, width: 345, height: 110)
        let wide = MotionRect(x: 59, y: 200, width: 690, height: 110)
        XCTAssertEqual(MotionLayout.carriedX(24 + 300, from: card, to: wide), 59 + 600, accuracy: 1e-9)
        XCTAssertEqual(MotionLayout.carriedX(659, from: wide, to: card), 324, accuracy: 1e-9)
        // A frame with no width (mid-layout) keeps his offset from the centre, both ways.
        let none = MotionRect(x: 0, y: 0, width: 0, height: 0)
        let away = MotionLayout.carriedX(196.5, from: portrait, to: none)
        XCTAssertEqual(away, 0)
        XCTAssertEqual(MotionLayout.carriedX(away, from: none, to: portrait), 196.5)
    }

    func testLedgeIdIsNamed() {
        XCTAssertEqual(MotionSurfaceID.ledge("settings").description, "ledge:settings")
        XCTAssertNotEqual(MotionSurfaceID.ledge("settings"), .ledge("emptyMemories"))
        XCTAssertFalse(MotionSurfaceID.ledge("settings").isRule)
    }
}
