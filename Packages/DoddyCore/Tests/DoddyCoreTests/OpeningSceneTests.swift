import XCTest
@testable import DoddyCore

final class OpeningSceneTests: XCTestCase {
    private typealias Beat = OpeningScene.Beat

    private func frame(_ t: Double, reduced: Bool = false) -> OpeningFrame {
        OpeningScene.frame(at: t, reducedMotion: reduced)
    }

    func testStartsWithABlankPageAndNoBall() {
        let f = frame(0)
        XCTAssertEqual(f.doddy.pose, .dribble)
        XCTAssertEqual(f.doddy.nextPose, .dribble)
        XCTAssertEqual(f.doddy.sketch, 0)
        XCTAssertEqual(f.doddy.readyPop, 0)
        XCTAssertEqual(f.doddy.squashX, 1); XCTAssertEqual(f.doddy.squashY, 1)
        XCTAssertEqual(f.camera.scale, 0.82)
        XCTAssertEqual(f.ball.opacity, 0)
        XCTAssertEqual(f.bubble.opacity, 0)
        XCTAssertEqual(f.burst.opacity, 0)
        XCTAssertEqual(f.setOpacity, 1)
        XCTAssertFalse(f.scored)
    }

    func testThePenDrawsStrokesOneAfterAnotherWithinTheSketchWindow() {
        let count = 24
        // Nothing drawn before the start; everything by the end.
        for i in 0..<count {
            XCTAssertEqual(OpeningScene.strokeProgress(index: i, count: count, at: Beat.sketchStart), 0)
            XCTAssertEqual(OpeningScene.strokeProgress(index: i, count: count, at: Beat.sketchEnd), 1, accuracy: 1e-9)
        }
        // Earlier strokes are always at least as far along as later ones.
        for t in stride(from: 0.0, through: Beat.sketchEnd, by: 0.01) {
            var last = 1.0
            for i in 0..<count {
                let p = OpeningScene.strokeProgress(index: i, count: count, at: t)
                XCTAssertLessThanOrEqual(p, last + 1e-9, "stroke \(i) at \(t)")
                XCTAssertTrue((0...1).contains(p))
                last = p
            }
        }
        // The first stroke is done early, the last starts late.
        XCTAssertEqual(OpeningScene.strokeProgress(index: 0, count: count, at: Beat.strokeDuration), 1, accuracy: 1e-9)
        XCTAssertEqual(OpeningScene.strokeProgress(index: count - 1, count: count, at: Beat.sketchEnd - Beat.strokeDuration), 0, accuracy: 1e-9)
        XCTAssertEqual(OpeningScene.strokeProgress(index: 0, count: 1, at: Beat.strokeDuration), 1, accuracy: 1e-9)
        XCTAssertEqual(OpeningScene.strokeProgress(index: 0, count: 0, at: 0), 1)
        XCTAssertEqual(frame(Beat.sketchEnd).doddy.sketch, 1)
    }

    func testTheBallPopsIntoTheHandAndBouncesTwice() {
        let hand = OpeningLayout.dribbleHand
        XCTAssertEqual(frame(Beat.dribbleStart - 0.01).ball.opacity, 0)
        let popped = frame(Beat.dribbleStart)
        XCTAssertEqual(popped.ball.opacity, 1)
        XCTAssertEqual(popped.ball.scale, 0, accuracy: 1e-9, "starts the pop from nothing")
        XCTAssertEqual(frame(Beat.dribbleStart + 0.12).ball.scale, 1, accuracy: 1e-9)
        for t in stride(from: Beat.dribbleStart, through: Beat.dribbleEnd - 0.001, by: 0.005) {
            let ball = frame(t).ball
            XCTAssertEqual(ball.center.x, hand.x, accuracy: 1e-9)
            XCTAssertGreaterThanOrEqual(ball.center.y, hand.y - 1e-9, "never above the hand at \(t)")
            XCTAssertLessThanOrEqual(ball.center.y + ball.radius, OpeningLayout.floorY + 1e-9, "never through the floor at \(t)")
            XCTAssertTrue(ball.trail.isEmpty)
        }
        // On the floor at a quarter and three quarters of each bounce, flattened; round in the hand.
        for t in [Beat.dribbleStart + Beat.bouncePeriod / 2, Beat.dribbleStart + Beat.bouncePeriod * 1.5] {
            let ball = frame(t).ball
            XCTAssertEqual(ball.center.y + ball.radius, OpeningLayout.floorY, accuracy: 1e-9)
            XCTAssertLessThan(ball.squash, 1)
            XCTAssertEqual(ball.stretch, 1, accuracy: 1e-9, "flat on the floor, not stretched")
        }
        let back = frame(Beat.dribbleStart + Beat.bouncePeriod)
        XCTAssertEqual(back.ball.center.y, hand.y, accuracy: 1e-9)
        XCTAssertEqual(back.ball.squash, 1)
        XCTAssertGreaterThan(frame(Beat.dribbleStart + Beat.bouncePeriod * 0.9).ball.stretch, 1, "stretched when moving fast")
        XCTAssertEqual(Beat.dribbleEnd - Beat.dribbleStart, Beat.bouncePeriod * 2, accuracy: 1e-9)
    }

    func testPosesComeInOrderWithShortCrossFades() {
        var seen: [OpeningPose] = []
        for t in stride(from: 0.0, through: Beat.end, by: 0.005) {
            let figure = frame(t).doddy
            XCTAssertTrue((0...1).contains(figure.blend), "\(figure.blend) at \(t)")
            if figure.blend == 0 {
                XCTAssertEqual(figure.pose, figure.nextPose, "outside a change both layers are the same drawing (\(t))")
                if seen.last != figure.pose { seen.append(figure.pose) }
            } else {
                XCTAssertNotEqual(figure.pose, figure.nextPose)
            }
        }
        XCTAssertEqual(seen, [.dribble, .gather, .shot, .followThrough, .ready])
        for (start, end) in [(Beat.gatherStart, Beat.gatherEnd), (Beat.shotStart, Beat.shotEnd), (Beat.followStart, Beat.followEnd)] {
            XCTAssertLessThanOrEqual(end - start, 0.1, "cross-fades are quick")
        }
        XCTAssertEqual(frame(Beat.end).doddy.pose, .ready)
        XCTAssertEqual(frame(Beat.end).doddy.readyPop, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(frame(Beat.readyStart + 0.12).doddy.readyPop, 1, "pops past full size")
    }

    func testCrouchThenStretch() {
        let crouch = frame(Beat.crouchPeak).doddy
        XCTAssertGreaterThan(crouch.squashX, 1.05)
        XCTAssertLessThan(crouch.squashY, 0.92)
        let stretch = frame(Beat.stretchPeak).doddy
        XCTAssertLessThan(stretch.squashX, 0.96)
        XCTAssertGreaterThan(stretch.squashY, 1.06)
        XCTAssertEqual(frame(0.5).doddy.squashX, 1, accuracy: 1e-9)
        XCTAssertEqual(frame(Beat.end).doddy.squashY, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(frame((Beat.hopStart + Beat.hopEnd) / 2).doddy.hop, 0.05)
        XCTAssertEqual(frame(Beat.hopEnd + 0.01).doddy.hop, 0, accuracy: 1e-9)
    }

    func testTheBallIsGatheredThenRaisedAndStaysInTheHandUntilTheRelease() {
        let gathered = frame((Beat.gatherEnd + Beat.shotStart) / 2)
        XCTAssertEqual(gathered.doddy.pose, .gather)
        XCTAssertEqual(gathered.ball.center.x, OpeningLayout.gatherHand.x, accuracy: 1e-9)
        XCTAssertEqual(gathered.ball.center.y, OpeningLayout.gatherHand.y, accuracy: 1e-9)
        XCTAssertLessThan(OpeningLayout.gatherHand.y, OpeningLayout.dribbleHand.y)

        let justBefore = frame(Beat.release - 0.001)
        XCTAssertEqual(justBefore.doddy.pose, .shot)
        XCTAssertEqual(justBefore.doddy.blend, 0)
        XCTAssertEqual(justBefore.ball.center.x, OpeningLayout.shotHand.x, accuracy: 1e-9)
        XCTAssertEqual(justBefore.ball.center.y, OpeningLayout.shotHand.y - justBefore.doddy.hop, accuracy: 1e-9)
        XCTAssertEqual(justBefore.ball.radius, OpeningLayout.highBallRadius, accuracy: 1e-9)
        let atRelease = frame(Beat.release)
        XCTAssertEqual(atRelease.ball.center.x, OpeningScene.releasePoint.x, accuracy: 1e-9)
        XCTAssertEqual(atRelease.ball.center.y, OpeningScene.releasePoint.y, accuracy: 1e-9)
        XCTAssertEqual(atRelease.ball.center.y, justBefore.ball.center.y, accuracy: 0.002, "no jump at the release")
    }

    func testAfterTheReleaseTheDrawingHoldsNoBall() {
        XCTAssertNil(OpeningLayout.ballInArt(.followThrough))
        XCTAssertNil(OpeningLayout.ballInArt(.ready))
        XCTAssertNil(OpeningLayout.hand(.followThrough))
        for t in stride(from: Beat.followEnd, through: Beat.readyStart, by: 0.05) {
            XCTAssertEqual(frame(t).doddy.pose, .followThrough, "at \(t)")
        }
        XCTAssertEqual(Beat.followStart, Beat.release)
    }

    func testTheBallFliesInAnArcWithATrailAndScoresOnTheBeat() {
        let f = frame(Beat.score)
        XCTAssertEqual(f.ball.center.x, OpeningLayout.ringCenter.x, accuracy: 1e-9)
        XCTAssertEqual(f.ball.center.y, OpeningLayout.ringCenter.y, accuracy: 1e-9)
        XCTAssertTrue(f.scored)
        XCTAssertFalse(frame(Beat.score - 0.001).scored)
        let mid = frame((Beat.release + Beat.score) / 2).ball
        XCTAssertLessThan(mid.center.y, OpeningLayout.ringCenter.y, "rises above the ring")
        XCTAssertLessThan(mid.center.y, OpeningScene.releasePoint.y)
        XCTAssertGreaterThan(mid.stretch, 1.2, "stretched along the flight")
        XCTAssertEqual(mid.trail.count, 3)
        for ghost in mid.trail { XCTAssertLessThan(ghost.x, mid.center.x, "ghosts are behind the ball") }
        XCTAssertEqual(frame(Beat.release + 0.01).ball.trail.count, 0, "no ghosts before there is a path behind")
        // Comes down into the ring, heading right and down.
        let landing = frame(Beat.score - 0.02).ball
        XCTAssertLessThan(landing.center.y, OpeningLayout.ringCenter.y)
        XCTAssertGreaterThan(landing.heading, 0); XCTAssertLessThan(landing.heading, Double.pi / 2)
        // Through the net and gone.
        XCTAssertEqual(frame(Beat.throughNet).ball.opacity, 0, accuracy: 1e-9)
        XCTAssertEqual(frame(Beat.end).ball.opacity, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(frame(Beat.score + 0.1).netStretch, 1.2)
        XCTAssertEqual(frame(Beat.score - 0.01).netStretch, 1)
    }

    func testTheSwishBurstPopsAndTheRingWobbles() {
        XCTAssertEqual(frame(Beat.burstStart - 0.01).burst, OpeningBurst(opacity: 0, scale: 0, rays: 0, ringWobble: 0))
        let pop = frame(Beat.burstStart + 0.10).burst
        XCTAssertEqual(pop.opacity, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(pop.scale, 0.8)
        XCTAssertGreaterThan(pop.rays, 0.5)
        XCTAssertNotEqual(pop.ringWobble, 0)
        XCTAssertGreaterThan(frame(Beat.burstStart + 0.14).burst.scale, 1, "overshoots")
        XCTAssertEqual(frame(Beat.burstStart + 0.40).burst.scale, 1, accuracy: 0.02)
        XCTAssertEqual(frame(Beat.burstEnd).burst.opacity, 0, accuracy: 1e-9)
        XCTAssertEqual(frame(Beat.burstStart + 0.5).burst.ringWobble, 0, accuracy: 1e-9, "the wobble dies out")
        XCTAssertEqual(frame(Beat.end).burst.rays, 1, accuracy: 1e-9)
    }

    func testTheHelloComesWithTheReadyPoseAndGoesAsHomeShowsThrough() {
        XCTAssertGreaterThan(Beat.bubbleIn, Beat.readyStart)
        XCTAssertEqual(frame(Beat.bubbleIn).bubble.opacity, 0)
        XCTAssertEqual(frame(Beat.handoverStart).bubble.opacity, 1, accuracy: 1e-9)
        XCTAssertEqual(frame(Beat.handoverStart).bubble.scale, 1, accuracy: 0.01)
        XCTAssertEqual(frame(Beat.handoverStart + 0.2).bubble.opacity, 0, accuracy: 1e-9, "the hello moves into Home's heading")
        XCTAssertEqual(frame(Beat.handoverStart).setOpacity, 1, accuracy: 1e-9)
        XCTAssertEqual(frame(Beat.handoverStart).backdropOpacity, 1, accuracy: 1e-9)
        XCTAssertEqual(frame(Beat.arrive).setOpacity, 0, accuracy: 1e-9)
        XCTAssertEqual(frame(Beat.arrive).backdropOpacity, 0, accuracy: 1e-9, "Home fully visible when Doddy lands")
        XCTAssertEqual(frame(Beat.end).hintOpacity, 0, accuracy: 1e-9)
        XCTAssertTrue(OpeningScene.isFinished(at: Beat.end, reducedMotion: false))
        XCTAssertFalse(OpeningScene.isFinished(at: Beat.end - 0.01, reducedMotion: false))
        XCTAssertLessThanOrEqual(OpeningScene.duration(reducedMotion: false), 2.5)
    }

    func testDoddyLandsExactlyInHisPlaceOnHome() {
        let court = OpeningHandover.courtBox(screenWidth: 390, screenHeight: 844)
        let home = ScreenBox(centerX: 195, centerY: 300, height: 210)
        func place(_ t: Double) -> PlacedDoddy { OpeningHandover.place(court: court, home: home, at: t, reducedMotion: false) }
        // On the court until the hand-over, at full size and opacity.
        XCTAssertEqual(place(0), PlacedDoddy(box: court, squashX: 1, squashY: 1, opacity: 1))
        XCTAssertEqual(place(Beat.handoverStart), PlacedDoddy(box: court, squashX: 1, squashY: 1, opacity: 1))
        // Arrives at the beat, then only squashes; the last frame is exactly Home's box, unsquashed.
        XCTAssertEqual(place(Beat.arrive).box, home)
        XCTAssertEqual(place((Beat.arrive + Beat.end) / 2).box, home)
        XCTAssertLessThan(place((Beat.arrive + Beat.end) / 2).squashY, 0.95, "squashes on landing")
        XCTAssertEqual(place(Beat.end), PlacedDoddy(box: home, squashX: 1, squashY: 1, opacity: 1))
        XCTAssertEqual(place(Beat.end + 1), PlacedDoddy(box: home, squashX: 1, squashY: 1, opacity: 1))
        // An arc: above the straight line half way.
        let mid = place((Beat.handoverStart + Beat.arrive) / 2).box
        XCTAssertLessThan(mid.centerY, (court.centerY + home.centerY) / 2 - 30)
        XCTAssertGreaterThan(place((Beat.handoverStart + Beat.arrive) / 2).squashY, 1, "stretched in the air")
        // Never faded while he has a place to land in.
        for t in stride(from: 0.0, through: Beat.end, by: 0.01) { XCTAssertEqual(place(t).opacity, 1) }
    }

    func testTheCourtBoxIsTheStageReadyPoseOnScreen() {
        let box = OpeningHandover.courtBox(screenWidth: 390, screenHeight: 844)
        let ready = OpeningLayout.ready
        XCTAssertEqual(box.height, ready.height * 390, accuracy: 1e-9)
        XCTAssertEqual(box.centerX, ready.center.x * 390, accuracy: 1e-9)
        XCTAssertEqual(box.centerY, (844 - 2 * 390) / 2 + ready.center.y * 390, accuracy: 1e-9)
        XCTAssertEqual(box.height * OpeningHandover.artAspect, ready.width * 390, accuracy: 0.5, "the art's aspect")
        // The camera is 1:1 well before the hand-over starts, so the court box needs no camera.
        XCTAssertEqual(frame(Beat.bubbleIn).camera.scale, 1, accuracy: 1e-9)
        XCTAssertEqual(frame(Beat.handoverStart).camera.shake, StagePoint(x: 0, y: 0))
    }

    func testWithoutAPlaceOnHomeDoddyFadesWithThePaper() {
        let court = OpeningHandover.courtBox(screenWidth: 390, screenHeight: 844)
        let start = OpeningHandover.place(court: court, home: nil, at: Beat.handoverStart, reducedMotion: false)
        XCTAssertEqual(start.box, court)
        XCTAssertEqual(start.opacity, 1, accuracy: 1e-9)
        XCTAssertEqual(OpeningHandover.place(court: court, home: nil, at: Beat.arrive, reducedMotion: false).opacity, 0, accuracy: 1e-9)
    }

    func testUnderReduceMotionDoddyIsInHisPlaceFromTheStart() {
        let court = OpeningHandover.courtBox(screenWidth: 390, screenHeight: 844)
        let home = ScreenBox(centerX: 195, centerY: 300, height: 100)
        for t in [0.0, 0.5, Beat.stillEnd] {
            XCTAssertEqual(OpeningHandover.place(court: court, home: home, at: t, reducedMotion: true),
                           PlacedDoddy(box: home, squashX: 1, squashY: 1, opacity: 1))
        }
    }

    func testTheHelloSitsAboveHisHeadAndOnTheScreen() {
        let box = ScreenBox(centerX: 195, centerY: 300, height: 210)
        let anchor = OpeningHandover.bubbleAnchor(for: box, bubbleWidth: 180, screenWidth: 390)
        let headTop = box.top + box.height * OpeningLayout.readyHeadFraction
        XCTAssertEqual(anchor.y, headTop - 4, accuracy: 1e-9)
        XCTAssertLessThan(anchor.x, box.centerX)
        // Pushed back on screen near an edge.
        XCTAssertEqual(OpeningHandover.bubbleAnchor(for: ScreenBox(centerX: 20, centerY: 300, height: 210), bubbleWidth: 180, screenWidth: 390).x, 12)
        XCTAssertEqual(OpeningHandover.bubbleAnchor(for: ScreenBox(centerX: 380, centerY: 300, height: 210), bubbleWidth: 180, screenWidth: 390).x, 390 - 12 - 180)
    }

    func testConfettiFliesUpOutOfTheRingAndFalls() {
        XCTAssertTrue(frame(Beat.score - 0.01).particles.filter { $0.kind != .dust }.isEmpty)
        let start = frame(Beat.score).particles.filter { $0.kind != .dust }
        XCTAssertEqual(start.count, OpeningScene.confettiCount)
        for piece in start {
            XCTAssertEqual(piece.center.x, OpeningLayout.ringCenter.x, accuracy: 1e-9)
            XCTAssertEqual(piece.center.y, OpeningLayout.ringCenter.y, accuracy: 1e-9)
        }
        let early = frame(Beat.score + 0.15).particles.filter { $0.kind != .dust }
        XCTAssertTrue(early.allSatisfy { $0.center.y < OpeningLayout.ringCenter.y }, "thrown upwards first")
        XCTAssertEqual(Set(early.map(\.kind)), [.confettiOrange, .confettiInk])
        let late = frame(Beat.score + 0.85).particles.filter { $0.kind != .dust }
        XCTAssertTrue(late.contains { $0.center.y > OpeningLayout.ringCenter.y }, "gravity brings them down")
        XCTAssertTrue(frame(Beat.score + Beat.confettiLength + 0.001).particles.filter { $0.kind != .dust }.isEmpty)
        XCTAssertLessThan(Beat.score + Beat.confettiLength, Beat.end)
        XCTAssertEqual(frame(Beat.score + 0.3), frame(Beat.score + 0.3), "the same every time")
    }

    func testDustPuffsWhereTheBallHitsTheFloorAndWhereDoddyLands() {
        let firstBounce = Beat.dribbleStart + Beat.bouncePeriod * 0.5
        XCTAssertTrue(frame(firstBounce - 0.01).particles.isEmpty)
        let puff = frame(firstBounce + 0.1).particles
        XCTAssertEqual(puff.count, 5)
        XCTAssertTrue(puff.allSatisfy { $0.kind == .dust && $0.center.y < OpeningLayout.floorY && $0.opacity > 0 })
        // The second bounce's puff overlaps the first; once the first is over only five are left.
        XCTAssertEqual(frame(firstBounce + Beat.puffLength + 0.001).particles.filter { $0.kind == .dust }.count, 5)
        XCTAssertTrue(frame(Beat.dribbleStart + Beat.bouncePeriod * 1.5 + Beat.puffLength + 0.001).particles.filter { $0.kind == .dust }.isEmpty)
        let landing = frame(Beat.hopEnd + 0.05).particles.filter { $0.kind == .dust }
        XCTAssertEqual(landing.count, 5)
        XCTAssertEqual(landing.map(\.center.x).reduce(0, +) / 5, OpeningLayout.doddy.bottomCenter.x, accuracy: 1e-9)
    }

    func testTheScoreShakesTheCameraBriefly() {
        XCTAssertEqual(frame(Beat.score - 0.01).camera.shake, StagePoint(x: 0, y: 0))
        let shaken = frame(Beat.score + 0.03).camera.shake
        XCTAssertGreaterThan(abs(shaken.x) + abs(shaken.y), 0.001)
        XCTAssertLessThan(abs(shaken.x), 0.01)
        XCTAssertEqual(frame(Beat.score + 0.3).camera.shake, StagePoint(x: 0, y: 0))
    }

    func testTheCameraPunchesInForTheShotAndSettlesBackForTheHandover() {
        var last = frame(0).camera.scale
        for t in stride(from: 0.0, through: Beat.shotEnd, by: 0.01) {
            let scale = frame(t).camera.scale
            XCTAssertGreaterThanOrEqual(scale, last - 1e-9, "zooms in, never out, until the shot (\(t))")
            last = scale
        }
        XCTAssertEqual(frame(Beat.shotEnd).camera.scale, 1.18, accuracy: 1e-9)
        XCTAssertEqual(frame(Beat.end).camera.scale, 1.0, accuracy: 1e-9)
        XCTAssertEqual(frame(Beat.end).camera.anchor, StagePoint(x: 0.50, y: 1.10))
        XCTAssertEqual(frame(Beat.bubbleIn).camera.scale, 1.0, accuracy: 1e-9, "1:1 by the hello")
        for t in stride(from: 0.0, through: Beat.end, by: 0.05) {
            let anchor = frame(t).camera.anchor
            XCTAssertTrue((0...1).contains(anchor.x) && (0...OpeningScene.stageHeight).contains(anchor.y))
        }
    }

    func testNegativeTimeIsTheFirstFrame() {
        XCTAssertEqual(frame(-1), frame(0))
    }

    func testEveryFrameStaysInRange() {
        for reduced in [false, true] {
            for t in stride(from: 0.0, through: OpeningScene.duration(reducedMotion: reduced), by: 0.005) {
                let f = frame(t, reduced: reduced)
                for value in [f.backdropOpacity, f.setOpacity, f.bubble.opacity, f.burst.opacity, f.hintOpacity, f.ball.opacity, f.doddy.blend, f.doddy.sketch] + f.particles.map(\.opacity) {
                    XCTAssertTrue((0...1).contains(value), "\(value) at \(t)")
                }
                XCTAssertTrue((0.6...1.3).contains(f.ball.squash))
                XCTAssertTrue((1.0...1.5).contains(f.ball.stretch))
                XCTAssertTrue((0.8...1.3).contains(f.camera.scale))
                XCTAssertTrue((0.85...1.15).contains(f.doddy.squashX) && (0.8...1.2).contains(f.doddy.squashY))
                XCTAssertGreaterThanOrEqual(f.doddy.hop, 0)
                XCTAssertTrue((0...1.2).contains(f.doddy.readyPop))
                XCTAssertTrue((0...1).contains(f.ball.center.x), "the ball stays on the stage at \(t)")
                XCTAssertTrue((0...OpeningScene.stageHeight).contains(f.ball.center.y))
                XCTAssertLessThanOrEqual(f.ball.trail.count, 3)
            }
        }
    }

    func testReduceMotionIsAStillPictureOfDoddyReadyToTalk() {
        for t in stride(from: 0.0, through: Beat.stillEnd, by: 0.05) {
            let f = frame(t, reduced: true)
            XCTAssertEqual(f.doddy, OpeningDoddy(pose: .ready, nextPose: .ready, blend: 0, sketch: 1, hop: 0, squashX: 1, squashY: 1, readyPop: 1), "at \(t)")
            XCTAssertEqual(f.ball.opacity, 0)
            XCTAssertEqual(f.camera.scale, 1)
            XCTAssertEqual(f.setOpacity, 0, "no court, no hoop")
            XCTAssertEqual(f.burst.opacity, 0)
            XCTAssertFalse(f.scored)
        }
        XCTAssertEqual(frame(0, reduced: true).backdropOpacity, 1, "Home is covered from the first frame")
        XCTAssertEqual(frame(0.5, reduced: true).backdropOpacity, 1, accuracy: 1e-9)
        XCTAssertEqual(frame(0.5, reduced: true).bubble.opacity, 1, accuracy: 1e-9)
        XCTAssertTrue(frame(0.5, reduced: true).particles.isEmpty)
        XCTAssertEqual(frame(Beat.stillEnd, reduced: true).backdropOpacity, 0, accuracy: 1e-9)
        XCTAssertTrue(OpeningScene.isFinished(at: Beat.stillEnd, reducedMotion: true))
        XCTAssertLessThan(OpeningScene.duration(reducedMotion: true), OpeningScene.duration(reducedMotion: false))
    }

    func testLayoutHoldsTogether() {
        let box = OpeningLayout.doddy
        for pose in OpeningPose.allCases {
            if let hand = OpeningLayout.hand(pose) {
                XCTAssertTrue((box.origin.x...(box.origin.x + box.width)).contains(hand.x))
                XCTAssertTrue((box.origin.y...(box.origin.y + box.height)).contains(hand.y))
                XCTAssertNotNil(pose.svgResourceName)
            }
        }
        XCTAssertNil(OpeningPose.ready.svgResourceName)
        XCTAssertEqual(OpeningPose.allCases.compactMap(\.svgResourceName).count, 4)
        XCTAssertEqual(box.origin.y + box.height, OpeningLayout.floorY, accuracy: 1e-9, "feet on the floor")
        let ready = OpeningLayout.ready
        XCTAssertEqual(ready.origin.y + ready.height * OpeningLayout.readyFeetFraction, OpeningLayout.floorY, accuracy: 0.001, "the ready Doddy's feet on the floor")
        XCTAssertEqual(OpeningLayout.ready.center.x, box.center.x, accuracy: 1e-9, "the ready Doddy stands where the shooter stood")
        XCTAssertLessThan(OpeningLayout.shotHand.y, OpeningLayout.gatherHand.y)
        XCTAssertLessThan(OpeningLayout.gatherHand.y, OpeningLayout.dribbleHand.y)
        XCTAssertLessThan(OpeningLayout.ringCenter.y, OpeningLayout.shotHand.y)
        XCTAssertGreaterThan(OpeningLayout.ringCenter.x, OpeningLayout.shotHand.x)
        // The bubble sits above the ready Doddy and left of the hoop.
        XCTAssertLessThan(OpeningLayout.bubbleAnchor.y, ready.origin.y + ready.height * OpeningLayout.readyHeadFraction, "above his head")
        XCTAssertGreaterThan(OpeningLayout.bubbleAnchor.y, ready.origin.y + ready.height * OpeningLayout.readyHeadFraction - 0.06, "but close to it")
        XCTAssertLessThan(OpeningLayout.bubbleAnchor.x + OpeningLayout.bubbleWidth, OpeningLayout.ringCenter.x - OpeningLayout.ringWidth / 2)
        XCTAssertGreaterThan(OpeningLayout.bubbleAnchor.x, 0.05)
    }

    func testEasingEndpoints() {
        XCTAssertEqual(Ease.progress(0.5, 1, 2), 0)
        XCTAssertEqual(Ease.progress(1.5, 1, 2), 0.5)
        XCTAssertEqual(Ease.progress(3, 1, 2), 1)
        XCTAssertEqual(Ease.progress(1, 1, 1), 1)
        for p in [0.0, 1.0] {
            XCTAssertEqual(Ease.out(p), p, accuracy: 1e-12)
            XCTAssertEqual(Ease.inOut(p), p, accuracy: 1e-12)
            XCTAssertEqual(Ease.backOut(p), p, accuracy: 1e-12)
        }
        XCTAssertGreaterThan(Ease.backOut(0.7), 1, "overshoots")
        XCTAssertEqual(StagePoint.bezierHeading(StagePoint(x: 0, y: 0), StagePoint(x: 1, y: 0), StagePoint(x: 2, y: 0), 0.5), 0, accuracy: 1e-9)
    }
}
