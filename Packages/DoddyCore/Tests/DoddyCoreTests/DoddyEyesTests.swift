import XCTest
@testable import DoddyCore

/// ADR-560: his eyes. The pieces are cut from the owner's sheets 007 and 008 by
/// `tools/whole_doddy/build_face_pieces.py`; these check which piece a moment chooses, that every
/// piece and picture the table names is there, that the table is plausible against the pictures'
/// own geometry, and what Home does with a finger, a touch and the evening.
final class DoddyEyesTests: XCTestCase {
    static let home = "WholeDoddy_crosslegged"

    // MARK: Choosing a piece

    func testAGazeIsOneOfEightDirectionsAndAtYouIsThePictureAsDrawn() {
        func look(_ x: Double, _ y: Double) -> DoddyLook { DoddyEyes.look(DoddyEyeState(gazeX: x, gazeY: y)) }
        XCTAssertEqual(look(0, 0), .atYou)
        XCTAssertTrue(DoddyLook.atYou.isAtYou)
        XCTAssertEqual(look(0.78, -0.68), .gaze(column: 2, row: 0), "up and to the right")
        XCTAssertEqual(look(-1, 0), .gaze(column: 0, row: 1))
        XCTAssertEqual(look(1, 0), .gaze(column: 2, row: 1))
        XCTAssertEqual(look(0, -1), .gaze(column: 1, row: 0))
        XCTAssertEqual(look(0, 1), .gaze(column: 1, row: 2))
        XCTAssertEqual(look(-0.7, 0.7), .gaze(column: 0, row: 2))
        XCTAssertEqual(look(0.3, 0.3), .atYou, "a small direction is still at you")
    }

    func testABandHoldsUntilTheDirectionHasClearlyLeftIt() {
        let held = DoddyLook.gaze(column: 2, row: 1)
        // 0.35 is under the 0.42 that enters a band and over the 0.28 that leaves it.
        XCTAssertEqual(DoddyEyes.look(DoddyEyeState(gazeX: 0.35), previous: held), held)
        XCTAssertEqual(DoddyEyes.look(DoddyEyeState(gazeX: 0.35), previous: .atYou), .atYou)
        XCTAssertEqual(DoddyEyes.look(DoddyEyeState(gazeX: 0.2), previous: held), .atYou)
        let up = DoddyLook.gaze(column: 1, row: 0)
        XCTAssertEqual(DoddyEyes.look(DoddyEyeState(gazeY: -0.33), previous: up), up)
        XCTAssertEqual(DoddyEyes.look(DoddyEyeState(gazeY: -0.33), previous: nil), .atYou)
    }

    func testABlinkGoesThroughHalfClosedAndHalfAgainAndASquintIsHalf() {
        var seen: [DoddyLook] = []
        for i in 0...20 {
            let closed = i <= 10 ? Double(i) / 10 : Double(20 - i) / 10
            let look = DoddyEyes.look(DoddyEyeState(closed: closed))
            if seen.last != look { seen.append(look) }
        }
        XCTAssertEqual(seen, [.atYou, .half, .closed, .half, .atYou], "the blink sheet's order: open, half, closed, half")
        XCTAssertEqual(DoddyEyes.look(DoddyEyeState(squint: 1)), .half)
        XCTAssertEqual(DoddyEyes.look(DoddyEyeState(gazeX: 1, closed: 1)), .closed, "a blink wins over a look")
    }

    func testNamesForTheMarkers() {
        XCTAssertNil(DoddyLook.atYou.name)
        XCTAssertEqual(DoddyLook.half.name, "half")
        XCTAssertEqual(DoddyLook.closed.name, "closed")
        XCTAssertEqual(DoddyLook.gaze(column: 2, row: 0).name, "gaze02")
    }

    // MARK: The table

    static let cells: [DoddyLook] = (0..<3).flatMap { row in (0..<3).map { DoddyLook.gaze(column: $0, row: row) } }
        .filter { !$0.isAtYou } + [.half, .closed]

    func testEveryCellHasAPieceForEachEye() {
        for cell in Self.cells {
            for side in [DoddyEyes.Side.left, .right] {
                XCTAssertEqual(DoddyEyes.pieces.filter { $0.cell == cell && $0.side == side }.count, 1, "\(cell) \(side)")
            }
        }
        XCTAssertEqual(DoddyEyes.pieces.count, Self.cells.count * 2, "no stray pieces")
        XCTAssertEqual(Set(DoddyEyes.pieceAssets).count, DoddyEyes.pieces.count, "one image set each")
        XCTAssertTrue(DoddyEyes.pieceAssets.allSatisfy { $0.hasPrefix("DoddyEye_") })
    }

    func testPiecesAreSmallAndAGazeMovesBothEyesTogether() {
        for p in DoddyEyes.pieces {
            XCTAssertLessThan(abs(p.dx), 0.25, p.asset)
            XCTAssertLessThan(abs(p.dy), 0.25, p.asset)
            XCTAssertTrue((0.1...0.5).contains(p.w), "\(p.asset) w \(p.w)")
            XCTAssertTrue((0.1...0.5).contains(p.h), "\(p.asset) h \(p.h)")
            if case .gaze = p.cell {
                XCTAssertGreaterThan(p.normW, 0)
                XCTAssertGreaterThan(p.normH, 0)
            } else {
                XCTAssertEqual(p.normW, 0)
                XCTAssertEqual(p.normH, 0)
            }
        }
        for cell in Self.cells {
            guard case .gaze = cell else { continue }
            let pair = DoddyEyes.pieces.filter { $0.cell == cell }
            XCTAssertEqual(pair[0].dx, pair[1].dx, accuracy: 1e-9, "\(cell)")
            XCTAssertEqual(pair[0].dy, pair[1].dy, accuracy: 1e-9, "\(cell)")
        }
        func shift(_ column: Int, _ row: Int) -> DoddyEyes.Piece {
            DoddyEyes.pieces.first { $0.cell == .gaze(column: column, row: row) && $0.side == .left }!
        }
        XCTAssertLessThan(shift(0, 1).dx, 0, "left looks left")
        XCTAssertGreaterThan(shift(2, 1).dx, 0, "right looks right")
        XCTAssertLessThan(shift(1, 0).dy, 0, "up looks up")
        XCTAssertGreaterThan(shift(1, 2).dy, 0, "down looks down")
    }

    func testFacesAreOnTheFrontFacingPicturesOnly() {
        let expected = ([Self.home] + (1...4).map { "DoddyMotion_idle_\($0)" } + (1...5).map { "DoddyMotion_wave_\($0)" }).sorted()
        XCTAssertEqual(DoddyEyes.pictureAssets, expected)
        for asset in ["UploadedDoddy_Listening", "WholeDoddy_listening", "DoddyMotion_jump_3", "WholeDoddy_kneeling_inspect",
                      "WholeDoddy_yawn_stretch", "WholeDoddy_shrug"] {
            XCTAssertFalse(DoddyEyes.hasFace(asset), asset)
            XCTAssertEqual(DoddyEyes.layers(for: asset, look: .half), [], asset)
            XCTAssertNil(DoddyEyes.eyesCentre(asset), asset)
        }
    }

    func testEachMeasuredFaceIsPlausible() {
        for (asset, fit) in DoddyEyes.fits {
            XCTAssertTrue((55...70).contains(fit.radius), "\(asset) radius \(fit.radius)")
            XCTAssertLessThan(fit.left.x, fit.right.x, asset)
            let gap = (fit.right.x - fit.left.x) / fit.radius
            XCTAssertTrue((0.55...0.80).contains(gap), "\(asset) eyes \(gap) radii apart")
            XCTAssertLessThan(abs(fit.left.y - fit.right.y), 12, asset)
            for eye in [fit.left, fit.right] {
                XCTAssertTrue((5...14).contains(eye.w), "\(asset) eye w \(eye.w)")
                XCTAssertTrue((15...30).contains(eye.h), "\(asset) eye h \(eye.h)")
                XCTAssertTrue((0...DoddyEyes.pictureWidth).contains(eye.x), asset)
                XCTAssertTrue((0...DoddyEyes.pictureHeight).contains(eye.y), asset)
                XCTAssertEqual(eye.fill.count, 3, asset)
                XCTAssertTrue(eye.fill.allSatisfy { (200...255).contains($0) }, "\(asset) fill \(eye.fill)")
            }
        }
    }

    // MARK: Layers

    func testAtYouDrawsNothingAndALookDrawsACoverAndAnEyeOverEachOfTheTwo() throws {
        XCTAssertEqual(DoddyEyes.layers(for: Self.home, look: .atYou), [])
        let layers = DoddyEyes.layers(for: Self.home, look: .gaze(column: 2, row: 0))
        XCTAssertEqual(layers.count, 4)
        let fit = try XCTUnwrap(DoddyEyes.fits[Self.home])
        for (i, eye) in [fit.left, fit.right].enumerated() {
            guard case .cover(let fill, let blur) = layers[i * 2].kind else { return XCTFail("a cover first") }
            XCTAssertEqual(fill, eye.fill)
            XCTAssertEqual(blur, DoddyEyes.coverBlur)
            XCTAssertEqual(layers[i * 2].x, eye.x)
            XCTAssertEqual(layers[i * 2].y, eye.y)
            XCTAssertGreaterThan(layers[i * 2].width, eye.w)
            XCTAssertGreaterThan(layers[i * 2].height, eye.h)
            guard case .piece(let asset) = layers[i * 2 + 1].kind else { return XCTFail("then the cut eye") }
            XCTAssertTrue(asset.hasPrefix("DoddyEye_g02_"))
            let piece = layers[i * 2 + 1]
            XCTAssertGreaterThan(piece.x, eye.x, "looks right")
            XCTAssertLessThan(piece.y, eye.y, "looks up")
            XCTAssertTrue((0.9...1.8).contains(piece.height / eye.h), "the picture's own eye size, frame included")
            XCTAssertLessThan(abs(piece.x - eye.x), 0.25 * fit.radius)
        }
        XCTAssertEqual(layers[1].y - fit.left.y, layers[3].y - fit.right.y, accuracy: 1e-9, "level")
    }

    func testClosedEyesAreWideLidsAtOrBelowTheOpenOnes() throws {
        let fit = try XCTUnwrap(DoddyEyes.fits[Self.home])
        let closed = DoddyEyes.layers(for: Self.home, look: .closed)
        let half = DoddyEyes.layers(for: Self.home, look: .half)
        XCTAssertEqual(closed.count, 4)
        XCTAssertEqual(half.count, 4)
        for layers in [closed, half] {
            for (i, eye) in [fit.left, fit.right].enumerated() {
                XCTAssertGreaterThan(layers[i * 2 + 1].width, layers[i * 2 + 1].height, "a lid is wide")
                XCTAssertGreaterThan(layers[i * 2 + 1].y, eye.y - 1)
            }
        }
        XCTAssertGreaterThan(closed[1].width, half[1].width)
    }

    func testEveryCellOnEveryFacePictureLaysItsPieces() {
        for asset in DoddyEyes.pictureAssets {
            XCTAssertNotNil(DoddyEyes.eyesCentre(asset))
            for cell in Self.cells {
                let layers = DoddyEyes.layers(for: asset, look: cell)
                XCTAssertEqual(layers.count, 4, "\(asset) \(cell)")
                XCTAssertTrue(layers.allSatisfy { $0.width > 0 && $0.height > 0 }, "\(asset) \(cell)")
            }
        }
    }

    // MARK: Home

    let eyes = DoddyEyePoint(x: 200, y: 300)

    func testHisEyesFollowAFingerAndComeBack300MsAfterItLifts() {
        let upRight = DoddyEyePoint(x: 380, y: 100)
        XCTAssertEqual(HomeEyes.look(eyes: eyes, finger: upRight, lifted: nil, pressed: false, blinkElapsed: nil, previous: nil),
                       .gaze(column: 2, row: 0))
        let left = DoddyEyePoint(x: 0, y: 300)
        XCTAssertEqual(HomeEyes.look(eyes: eyes, finger: left, lifted: nil, pressed: false, blinkElapsed: nil, previous: nil),
                       .gaze(column: 0, row: 1))
        // Lifted: still on where it was for 300 ms, then at you.
        XCTAssertEqual(HomeEyes.look(eyes: eyes, finger: nil, lifted: (left, 0.1), pressed: false, blinkElapsed: nil, previous: nil),
                       .gaze(column: 0, row: 1))
        XCTAssertEqual(HomeEyes.look(eyes: eyes, finger: nil, lifted: (left, 0.31), pressed: false, blinkElapsed: nil, previous: nil),
                       .atYou)
        XCTAssertEqual(HomeEyes.look(eyes: eyes, finger: nil, lifted: nil, pressed: false, blinkElapsed: nil, previous: nil), .atYou)
    }

    func testAFingerRightOnHisFaceDoesntMoveHisEyes() {
        let close = DoddyEyePoint(x: 210, y: 310)
        XCTAssertEqual(HomeEyes.direction(from: eyes, to: close).x, 0)
        XCTAssertEqual(HomeEyes.look(eyes: eyes, finger: close, lifted: nil, pressed: false, blinkElapsed: nil, previous: nil), .atYou)
    }

    func testAFingerOnHimHalfClosesHisEyes() {
        XCTAssertEqual(HomeEyes.look(eyes: eyes, finger: nil, lifted: nil, pressed: true, blinkElapsed: nil, previous: nil), .half)
    }

    func testTheEveningBlinkIsOneSlowBlink() {
        var seen: [DoddyLook] = []
        var t = 0.0
        while t <= 0.4 {
            let look = HomeEyes.look(eyes: eyes, finger: nil, lifted: nil, pressed: false, blinkElapsed: t, previous: seen.last)
            if seen.last != look { seen.append(look) }
            t += 1.0 / 120
        }
        XCTAssertEqual(seen, [.atYou, .half, .closed, .half, .atYou])
        XCTAssertEqual(HomeEyes.blink(elapsed: HomeEyes.blinkDuration * 0.43), 1, accuracy: 1e-9)
        XCTAssertEqual(HomeEyes.blink(elapsed: HomeEyes.blinkDuration), 0)
        XCTAssertEqual(HomeEyes.blink(elapsed: -0.1), 0)
    }

    func testTheEveningBlinkIsDueFrom21OnceADay() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Warsaw"))
        func at(_ hour: Int, _ minute: Int = 0, day: Int = 20) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        XCTAssertNil(HomeEyes.eveningBlinkDay(now: at(20, 59), lastDay: nil, calendar: cal), "not before 21:00")
        XCTAssertEqual(HomeEyes.eveningBlinkDay(now: at(21), lastDay: nil, calendar: cal), "2026-10-20")
        XCTAssertEqual(HomeEyes.eveningBlinkDay(now: at(23, 30), lastDay: "2026-10-19", calendar: cal), "2026-10-20")
        XCTAssertNil(HomeEyes.eveningBlinkDay(now: at(22), lastDay: "2026-10-20", calendar: cal), "once a day")
        XCTAssertNil(HomeEyes.eveningBlinkDay(now: at(9, day: 21), lastDay: "2026-10-20", calendar: cal), "morning: no")
    }

    // MARK: The persistent Doddy (motion v2, ADR-552)

    func testTheMovingDoddysHomePicturesHaveFaces() {
        // On Home's stage he breathes (idle 1 to 4), waves his welcome (wave 1 to 5) and sits
        // cross-legged after a while (ADR-555): his eyes can be drawn on every one of them.
        for n in 1...4 { XCTAssertTrue(DoddyEyes.hasFace("DoddyMotion_idle_\(n)"), "idle \(n)") }
        for n in 1...5 { XCTAssertTrue(DoddyEyes.hasFace("DoddyMotion_wave_\(n)"), "wave \(n)") }
        XCTAssertTrue(DoddyEyes.hasFace("WholeDoddy_crosslegged"))
        // The hop strip turns his head, so it keeps the eyes it was drawn with.
        XCTAssertFalse(DoddyEyes.hasFace("DoddyMotion_jump_3"))
    }

    func testAMirroredPictureSwapsLeftAndRightAndNothingElse() throws {
        XCTAssertEqual(DoddyLook.gaze(column: 0, row: 2).mirrored, .gaze(column: 2, row: 2))
        XCTAssertEqual(DoddyLook.gaze(column: 2, row: 0).mirrored, .gaze(column: 0, row: 0))
        XCTAssertEqual(DoddyLook.atYou.mirrored, .atYou)
        XCTAssertEqual(DoddyLook.half.mirrored, .half)
        XCTAssertEqual(DoddyLook.closed.mirrored, .closed)
        for column in 0...2 {
            for row in 0...2 {
                let look = DoddyLook.gaze(column: column, row: row)
                XCTAssertEqual(look.mirrored.mirrored, look)
            }
        }
        let asset = "DoddyMotion_idle_1"
        let centre = try XCTUnwrap(DoddyEyes.eyesCentre(asset))
        let flipped = try XCTUnwrap(DoddyEyes.eyesCentre(asset, mirrored: true))
        XCTAssertEqual(flipped.x, DoddyEyes.pictureWidth - centre.x, accuracy: 1e-9)
        XCTAssertEqual(flipped.y, centre.y)
    }
}
