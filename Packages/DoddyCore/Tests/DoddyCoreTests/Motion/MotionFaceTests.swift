import XCTest
@testable import DoddyCore

/// MV7 (ADR-558): his eyes. The pieces are cut from the owner's sheets 007 and 008 by
/// `tools/whole_doddy/build_face_pieces.py`; these check what the code does with them: which eyes
/// the engine's state chooses, that every piece and picture the table names exists, that the
/// table is plausible against the pictures' own geometry, and that the engine's real events (a
/// look, a touch, a rub, an evening welcome) reach the picture.
final class MotionFaceTests: XCTestCase {
    // MARK: Choosing

    func testAGazeIsOneOfEightDirectionsAndAtYouIsThePictureAsDrawn() {
        func eyes(_ x: Double, _ y: Double, previous: MotionEyes? = nil) -> MotionEyes {
            MotionFace.choose(MotionEyeState(gazeX: x, gazeY: y), previous: previous)
        }
        XCTAssertEqual(eyes(0, 0), .atYou)
        XCTAssertTrue(MotionEyes.atYou.isAtYou)
        XCTAssertEqual(eyes(0.78, -0.68), .gaze(column: 2, row: 0), "the thinking look: up and to the right")
        XCTAssertEqual(eyes(-1, 0), .gaze(column: 0, row: 1))
        XCTAssertEqual(eyes(1, 0), .gaze(column: 2, row: 1))
        XCTAssertEqual(eyes(0, -1), .gaze(column: 1, row: 0), "up (ducking)")
        XCTAssertEqual(eyes(0, 1), .gaze(column: 1, row: 2))
        XCTAssertEqual(eyes(-0.7, 0.7), .gaze(column: 0, row: 2))
        XCTAssertEqual(eyes(0.3, 0.3), .atYou, "a small direction is still at you")
    }

    func testABandHoldsUntilTheDirectionHasClearlyLeftIt() {
        let held = MotionEyes.gaze(column: 2, row: 1)
        // 0.35 is under the 0.42 that enters a band and over the 0.28 that leaves it.
        XCTAssertEqual(MotionFace.choose(MotionEyeState(gazeX: 0.35), previous: held), held)
        XCTAssertEqual(MotionFace.choose(MotionEyeState(gazeX: 0.35), previous: .atYou), .atYou)
        XCTAssertEqual(MotionFace.choose(MotionEyeState(gazeX: 0.2), previous: held), .atYou)
        let up = MotionEyes.gaze(column: 1, row: 0)
        XCTAssertEqual(MotionFace.choose(MotionEyeState(gazeY: -0.33), previous: up), up)
        XCTAssertEqual(MotionFace.choose(MotionEyeState(gazeY: -0.33), previous: nil), .atYou)
    }

    func testABlinkGoesThroughHalfClosedAndHalfAgainAndASquintIsHalf() {
        var seen: [MotionEyes] = []
        for i in 0...20 {
            let blink = i <= 10 ? Double(i) / 10 : Double(20 - i) / 10
            let e = MotionFace.choose(MotionEyeState(closed: blink))
            if seen.last != e { seen.append(e) }
        }
        XCTAssertEqual(seen, [.atYou, .half, .closed, .half, .atYou], "the blink sheet's order: open, half, closed, half")
        XCTAssertEqual(MotionFace.choose(MotionEyeState(squint: 1)), .half)
        XCTAssertEqual(MotionFace.choose(MotionEyeState(gazeX: 1, closed: 1)), .closed, "shut eyes win over a look")
    }

    // MARK: The table

    static let cells: [MotionEyes] = (0..<3).flatMap { row in (0..<3).map { MotionEyes.gaze(column: $0, row: row) } }
        .filter { !$0.isAtYou } + [.half, .closed]

    func testEveryCellHasAPieceForEachEyeAndTheAppHasItsPicture() {
        for cell in Self.cells {
            for side in [MotionFace.Side.left, .right] {
                let found = MotionFace.pieces.filter { $0.cell == cell && $0.side == side }
                XCTAssertEqual(found.count, 1, "\(cell) \(side)")
            }
        }
        XCTAssertEqual(MotionFace.pieces.count, Self.cells.count * 2, "no stray pieces")
        XCTAssertEqual(Set(MotionFace.pieceAssets).count, MotionFace.pieces.count, "one image set each")
        XCTAssertTrue(MotionFace.pieceAssets.allSatisfy { $0.hasPrefix("DoddyEye_") })
    }

    func testPiecesAreFromTheSheetsAndSmall() {
        for p in MotionFace.pieces {
            // Eyes sit within a quarter of a head radius of the picture's own (the sheet's gazes
            // reach about 0.15; a lid a bit lower).
            XCTAssertLessThan(abs(p.dx), 0.25, p.asset)
            XCTAssertLessThan(abs(p.dy), 0.25, p.asset)
            // A frame of a cut eye: under half a head wide and tall.
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
        // Both eyes of a gaze move together (the tool moves the pair by one shift), so they stay level.
        for cell in Self.cells {
            guard case .gaze = cell else { continue }
            let pair = MotionFace.pieces.filter { $0.cell == cell }
            XCTAssertEqual(pair[0].dx, pair[1].dx, accuracy: 1e-9, "\(cell)")
            XCTAssertEqual(pair[0].dy, pair[1].dy, accuracy: 1e-9, "\(cell)")
        }
        // Up looks up, down looks down, left looks left, right looks right.
        func shift(_ column: Int, _ row: Int) -> MotionFace.Piece {
            MotionFace.pieces.first { $0.cell == .gaze(column: column, row: row) && $0.side == .left }!
        }
        XCTAssertLessThan(shift(1, 0).dy, shift(1, 2).dy)
        XCTAssertLessThan(shift(0, 1).dx, shift(2, 1).dx)
        XCTAssertLessThan(shift(0, 1).dx, 0)
        XCTAssertGreaterThan(shift(2, 1).dx, 0)
        XCTAssertLessThan(shift(1, 0).dy, 0)
        XCTAssertGreaterThan(shift(1, 2).dy, 0)
    }

    func testFacesAreOnTheFrontFacingPicturesOnly() {
        let expected = ((1...4).map { "strip:idle:\($0)" } + (1...5).map { "strip:wave:\($0)" } + ["pose:crosslegged"]).sorted()
        XCTAssertEqual(MotionFace.pictureKeys, expected)
        // Turned or tilted heads, and poses that draw their own face: front eyes don't fit them.
        for p: MotionArt.Picture in [.strip("jump", 1), .strip("jump", 2), .strip("jump", 3), .strip("jump", 4), .strip("jump", 5),
                                     .pose("listening"), .pose("kneeling_inspect"), .pose("yawn_stretch"),
                                     .pose("facepalm"), .pose("shrug"), .strip("turn", 2), .strip("sit", 3)] {
            XCTAssertFalse(MotionFace.hasFace(p), "\(p)")
            XCTAssertEqual(MotionFace.layers(for: p, eyes: .half), [], "\(p)")
        }
    }

    func testEachMeasuredFaceIsPlausible() {
        for (key, fit) in MotionFace.fits {
            XCTAssertTrue((55...70).contains(fit.radius), "\(key) radius \(fit.radius)")
            XCTAssertLessThan(fit.left.x, fit.right.x, key)
            // About two thirds of a head radius apart, at about the same height.
            let gap = (fit.right.x - fit.left.x) / fit.radius
            XCTAssertTrue((0.55...0.80).contains(gap), "\(key) eyes \(gap) radii apart")
            XCTAssertLessThan(abs(fit.left.y - fit.right.y), 12, key)
            for eye in [fit.left, fit.right] {
                XCTAssertTrue((5...14).contains(eye.w), "\(key) eye w \(eye.w)")
                XCTAssertTrue((15...30).contains(eye.h), "\(key) eye h \(eye.h)")
                XCTAssertTrue((0...MotionFace.pictureWidth).contains(eye.x), key)
                XCTAssertTrue((0...MotionFace.pictureHeight).contains(eye.y), key)
                XCTAssertEqual(eye.fill.count, 3, key)
                // The paper is the pack's cream: light, a little warm.
                XCTAssertTrue(eye.fill.allSatisfy { (200...255).contains($0) }, "\(key) fill \(eye.fill)")
                XCTAssertGreaterThanOrEqual(eye.fill[0], eye.fill[2], key)
            }
        }
    }

    // MARK: Layers

    func testAtYouDrawsNothingAndAGazeDrawsACoverAndAnEyeOverEachOfTheTwo() throws {
        let idle = MotionArt.Picture.strip("idle", 1)
        XCTAssertEqual(MotionFace.layers(for: idle, eyes: .atYou), [])
        let layers = MotionFace.layers(for: idle, eyes: .gaze(column: 2, row: 0))
        XCTAssertEqual(layers.count, 4)
        let fit = try XCTUnwrap(MotionFace.fits["strip:idle:1"])
        for (i, eye) in [fit.left, fit.right].enumerated() {
            guard case .cover(let fill, let blur) = layers[i * 2].kind else { return XCTFail("a cover first") }
            XCTAssertEqual(fill, eye.fill)
            XCTAssertEqual(blur, MotionFace.coverBlur)
            let cover = layers[i * 2]
            // The cover is bigger than the picture's own eye all round.
            XCTAssertEqual(cover.x, eye.x)
            XCTAssertEqual(cover.y, eye.y)
            XCTAssertGreaterThan(cover.width, eye.w)
            XCTAssertGreaterThan(cover.height, eye.h)
            guard case .piece(let asset) = layers[i * 2 + 1].kind else { return XCTFail("then the cut eye") }
            XCTAssertTrue(asset.hasPrefix("DoddyEye_g02_"))
            let piece = layers[i * 2 + 1]
            // The eye moves up and to the right of where the picture drew it, and is its size.
            XCTAssertGreaterThan(piece.x, eye.x)
            XCTAssertLessThan(piece.y, eye.y)
            XCTAssertTrue((0.9...1.8).contains(piece.height / eye.h), "stretched to the picture's own eye, frame included")
            // And stays inside the head: well within a radius of the eye it replaces.
            XCTAssertLessThan(abs(piece.x - eye.x), 0.25 * fit.radius)
        }
        // The cut eyes stay level (the gaze moves the pair together).
        let leftEye = layers[1], rightEye = layers[3]
        XCTAssertEqual(leftEye.y - fit.left.y, rightEye.y - fit.right.y, accuracy: 1e-9)
        XCTAssertEqual(leftEye.x - fit.left.x, rightEye.x - fit.right.x, accuracy: 1e-9)
    }

    func testClosedEyesAreWiderThanTheyAreTallAndSitBelowTheOpenOnes() throws {
        let key = MotionArt.Picture.pose("crosslegged")
        let fit = try XCTUnwrap(MotionFace.fits["pose:crosslegged"])
        let closed = MotionFace.layers(for: key, eyes: .closed)
        let half = MotionFace.layers(for: key, eyes: .half)
        XCTAssertEqual(closed.count, 4)
        XCTAssertEqual(half.count, 4)
        for layers in [closed, half] {
            for (i, eye) in [fit.left, fit.right].enumerated() {
                let piece = layers[i * 2 + 1]
                XCTAssertGreaterThan(piece.width, piece.height, "a lid is wide")
                XCTAssertGreaterThan(piece.y, eye.y - 1, "a lid sits at or below where the open eye was centred")
            }
        }
        XCTAssertGreaterThan(closed[1].width, half[1].width, "closed is wider than half")
    }

    func testEveryCellOnEveryFacePictureLaysItsPieces() {
        XCTAssertEqual(MotionFace.pictures.count, MotionFace.pictureKeys.count, "every key names a picture")
        for picture in MotionFace.pictures {
            XCTAssertTrue(MotionFace.hasFace(picture))
            for cell in Self.cells {
                let layers = MotionFace.layers(for: picture, eyes: cell)
                XCTAssertEqual(layers.count, 4, "\(picture) \(cell)")
                XCTAssertTrue(layers.allSatisfy { $0.width > 0 && $0.height > 0 }, "\(picture) \(cell)")
            }
        }
    }

    func testEyesMarkersNameWhatIsDrawn() {
        XCTAssertNil(MotionEyes.atYou.marker)
        XCTAssertEqual(MotionEyes.half.marker, "doddy.eyes.half")
        XCTAssertEqual(MotionEyes.closed.marker, "doddy.eyes.closed")
        XCTAssertEqual(MotionEyes.gaze(column: 2, row: 0).marker, "doddy.eyes.gaze02")
    }

    // MARK: The engine's events reach the picture

    var host: MotionHost!
    var e: MotionEngine { host.engine }

    func makeHost(welcome: WelcomeKind? = nil, reduceMotion: Bool = false) {
        var settings = MotionSettings()
        settings.reduceMotion = reduceMotion
        host = MotionHost(settings: settings)
        var s = MotionScene()
        s.frames[.rail] = MotionHostTests.rail
        s.frames[.stage] = MotionHostTests.stage
        s.marks["tab.home"] = MotionRect(x: 32, y: 768, width: 110, height: 44)
        s.mounted = [.rail, .stage]
        host.scene = s
        host.behaviours = true
        host.welcomeToday = welcome
        XCTAssertTrue(host.placeOnCurrentScreen())
    }

    /// Runs `ms` at 240 Hz, recording each distinct pair of picture and eyes.
    @discardableResult
    func run(_ ms: Double, until: ((MotionHost) -> Bool)? = nil) -> [MotionEyes] {
        var seen: [MotionEyes] = []
        var previous: MotionEyes?
        var t = 0.0
        let dt = 1000.0 / 240
        while t < ms {
            host.step(dt)
            host.settle()
            t += dt
            let art = MotionArt.choose(e, previousEyes: previous)
            previous = art.eyes
            if seen.last != art.eyes { seen.append(art.eyes) }
            if let until, until(host) { break }
        }
        return seen
    }

    func eyes() -> MotionEyes { MotionArt.choose(e).eyes }

    func testALookReachesHisEyesAndLookingAtYouBringsThemBack() {
        makeHost()
        run(200)
        XCTAssertEqual(eyes(), .atYou)
        // Something up and to the right of his head.
        e.look(at: MotionPoint(x: 380, y: 100), "the top right")
        run(300)
        XCTAssertEqual(eyes(), .gaze(column: 2, row: 0))
        XCTAssertTrue(MotionArt.choose(e).faceLayers.count == 4)
        e.lookAtUser()
        run(300)
        XCTAssertEqual(eyes(), .atYou)
        XCTAssertEqual(MotionArt.choose(e).faceLayers, [])
    }

    func testTheEyesLeadTheyAreThereWithinAFewFramesOfTheLook() {
        makeHost()
        run(200)
        e.look(at: MotionPoint(x: 0, y: e.headPos().y), "the left")
        // 88 ms to 95 % (the brief); the band is entered well before that.
        run(88)
        XCTAssertEqual(eyes(), .gaze(column: 0, row: 1))
    }

    /// Home watches the whole screen for a finger (the scroll view keeps the touch): only his eyes
    /// follow it, and they come back to you after it lifts.
    func testAFingerElsewhereOnHomeMovesHisEyesAndNothingElse() {
        makeHost()
        run(200)
        XCTAssertEqual(eyes(), .atYou)
        let head = e.headPos()
        host.fingerElsewhere(x: head.x + 180, y: head.y)
        run(300)
        XCTAssertEqual(eyes(), .gaze(column: 2, row: 1), "to the right, level with his head")
        XCTAssertNil(e.homeTouch, "it is not a touch on him: no dip, no lean, no tap")
        XCTAssertFalse(host.scene.finger.isDown, "the hold check never sees it")
        host.fingerElsewhere(x: head.x - 180, y: head.y)
        run(300)
        XCTAssertEqual(eyes(), .gaze(column: 0, row: 1), "and it follows the finger across")
        host.fingerElsewhereLifted()
        run(700)
        XCTAssertEqual(eyes(), .atYou, "300 ms after it lifts he looks at you")
    }

    func testAFingerElsewhereIsIgnoredWhileASheetIsUp() {
        makeHost()
        run(200)
        host.scene.covers = 1
        let head = e.headPos()
        host.fingerElsewhere(x: head.x + 180, y: head.y)
        run(300)
        XCTAssertEqual(eyes(), .atYou, "a sheet is up: his eyes stay")
    }

    func testHisEyesLetGoOfATouchThatNeverSaidItLifted() {
        makeHost()
        run(200)
        let head = e.headPos()
        host.fingerElsewhere(x: head.x - 180, y: head.y)
        run(300)
        XCTAssertEqual(eyes(), .gaze(column: 0, row: 1))
        // The system cancelled the touch (a menu opened over it) and no lift was reported.
        run(MotionHost.fingerStaleAfter + 1500)
        XCTAssertEqual(eyes(), .atYou)
    }

    func testATouchSquintsHisEyesAndLettingGoOpensThem() {
        makeHost()
        run(300)
        let soles = e.pos
        host.touchDown(x: soles.x, y: soles.y - 60)
        run(80)
        XCTAssertEqual(eyes(), .half, "squints within 60 ms")
        host.touchUp(vx: 0, vy: 0)
        run(300)
        XCTAssertEqual(eyes(), .atYou)
    }

    func testStrokingHisHeadClosesHisEyesAndTheyOpenAgainAfterwards() {
        makeHost()
        run(300)
        let head = e.headPos()
        host.touchDown(x: head.x, y: head.y)
        // A slow stroke across his head.
        var x = head.x
        for _ in 0..<12 {
            x += 4
            host.touchMoved(x: x, y: head.y, vx: 100, vy: 0)
            run(30)
        }
        run(150)
        XCTAssertEqual(eyes(), .closed, "head rub: eyes close")
        host.touchUp(vx: 0, vy: 0)
        run(1200)
        XCTAssertEqual(eyes(), .atYou)
    }

    func testTheEveningWelcomeIsOneSlowBlinkOnTheWave() {
        makeHost(welcome: .evening)
        let seen = run(5000)
        XCTAssertEqual(seen.filter { $0 == .closed }.count, 1, "one blink")
        let i = try! XCTUnwrap(seen.firstIndex(of: .closed))
        XCTAssertEqual(seen[i - 1], .half)
        XCTAssertEqual(seen[i + 1], .half)
    }

    func testNoBlinkAppearsOnItsOwnWhileHeStandsStill() {
        makeHost()
        let seen = run(40_000)
        XCTAssertFalse(seen.contains(.closed), "no idle blink loop (brief rule 9)")
        XCTAssertFalse(seen.contains(.half))
    }

    func testReduceMotionKeepsTheEyes() {
        makeHost(reduceMotion: true)
        run(200)
        e.look(at: MotionPoint(x: 380, y: 100), "the top right")
        run(300)
        XCTAssertEqual(eyes(), .gaze(column: 2, row: 0), "eyes still lead under Reduce Motion")
    }

    func testHisHopPicturesNeverCarryEyesAndHeStillLooksWhereHeLandsOn() {
        makeHost()
        run(200)
        e.look(at: MotionPoint(x: 380, y: 100), "the top right")
        host.scene.marks["tab.memories"] = MotionRect(x: 146, y: 768, width: 101, height: 44)
        host.tabChanged(to: .memories, tapT: e.now)
        host.scene.mounted.remove(.stage)
        host.scene.marks["memories.list"] = MotionHostTests.listViewport
        host.scene.ruleCount = 4
        for i in 0..<4 {
            host.scene.frames[.rule(i)] = MotionHostTests.card(i)
            host.scene.mounted.insert(.rule(i))
        }
        var jumpFrames = 0
        var previous: MotionEyes?
        var t = 0.0
        while t < 1500, !(e.mode == .attached && e.anchor?.surface.isRule == true && e.now - e.lastLand > 300) {
            host.step(1000.0 / 240)
            host.settle()
            t += 1000.0 / 240
            let art = MotionArt.choose(e, previousEyes: previous)
            previous = art.eyes
            if case .strip("jump", _) = art.picture {
                jumpFrames += 1
                XCTAssertEqual(art.eyes, .atYou, "a three-quarter head has no front eyes to move")
                XCTAssertEqual(art.faceLayers, [])
            }
        }
        XCTAssertGreaterThan(jumpFrames, 10, "the hop was drawn on the jump strip")
        // Standing on the card, a look is drawn again.
        e.look(at: MotionPoint(x: 0, y: e.headPos().y), "the left")
        run(300)
        XCTAssertEqual(eyes(), .gaze(column: 0, row: 1))
    }
}
