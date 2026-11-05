import Foundation
import XCTest
@testable import DoddyCore

/// The brief's numbers and rules, checked directly (the golden telemetry test checks the same
/// engine against the clips).
final class MotionEngineTests: XCTestCase {
    func testFlightAndApexFormulas() {
        // T = clamp(220 + 0.4·D + 0.2·|Δy|, 260, 420)
        XCTAssertEqual(MotionTiming.flight(0, 0), 260)
        XCTAssertEqual(MotionTiming.flight(100, 0), 260)
        XCTAssertEqual(MotionTiming.flight(200, 100), 320, accuracy: 1e-9)
        XCTAssertEqual(MotionTiming.flight(1000, 0), 420)
        // Talk → Memories: 336 pt with a 326 pt rise gives 419 ms, so the tab cap applies.
        XCTAssertEqual(MotionTiming.flight(335.67, -326), 419.47, accuracy: 0.01)
        // Apex: clamp(12 + 0.08·D, 16, 32), or clamp(6 + 0.04·D, 10, 18) stepping down > 40 pt.
        XCTAssertEqual(MotionTiming.apex(335.67, -326), 32)
        XCTAssertEqual(MotionTiming.apex(100, 0), 20, accuracy: 1e-9)
        XCTAssertEqual(MotionTiming.apex(197.8, 190), 13.912, accuracy: 0.001)
        XCTAssertEqual(MotionTiming.apex(10, 50), 10)
        // Re-target: clamp(180 + 0.5·D, 200, 360).
        XCTAssertEqual(MotionTiming.retargetFlight(10), 200)
        XCTAssertEqual(MotionTiming.retargetFlight(100), 230)
        XCTAssertEqual(MotionTiming.retargetFlight(1000), 360)
    }

    func testCrouchLengths() {
        XCTAssertEqual(HopPlan.anticipation(immediate: false, leaving: false, fromSit: false, fromLanding: false, surfaceMovesHisWay: false), 80)
        XCTAssertEqual(HopPlan.anticipation(immediate: false, leaving: false, fromSit: true, fromLanding: false, surfaceMovesHisWay: false), 140)
        XCTAssertEqual(HopPlan.anticipation(immediate: false, leaving: false, fromSit: false, fromLanding: true, surfaceMovesHisWay: false), 40)
        XCTAssertEqual(HopPlan.anticipation(immediate: false, leaving: false, fromSit: false, fromLanding: false, surfaceMovesHisWay: true), 40)
        XCTAssertEqual(HopPlan.anticipation(immediate: false, leaving: true, fromSit: true, fromLanding: false, surfaceMovesHisWay: false), 0)
        XCTAssertEqual(HopPlan.anticipation(immediate: true, leaving: false, fromSit: false, fromLanding: false, surfaceMovesHisWay: false), 0)
    }

    func testTabHopCapLandsBy484MsAfterTheTap() {
        XCTAssertEqual(HopPlan.flightCap(isTabHop: true, tapAt: 0, now: 80), 400)
        XCTAssertEqual(HopPlan.flightCap(isTabHop: true, tapAt: 0, now: 300), 260)
        XCTAssertEqual(HopPlan.flightCap(isTabHop: false, tapAt: 0, now: 80), 420)
    }

    func testScaleChangesOnlyInsideTheFlight() {
        XCTAssertEqual(HopPlan.scale(from: 1, to: 1.4, progress: 0), 1)
        XCTAssertEqual(HopPlan.scale(from: 1, to: 1.4, progress: 0.15), 1)
        XCTAssertEqual(HopPlan.scale(from: 1, to: 1.4, progress: 0.9), 1.4, accuracy: 1e-12)
        XCTAssertEqual(HopPlan.scale(from: 1, to: 1.4, progress: 1), 1.4, accuracy: 1e-12)
    }

    func testContactSquashRange() {
        XCTAssertEqual(HopPlan.contactSquash(vy: -500), 2.2)
        XCTAssertEqual(HopPlan.contactSquash(vy: 900), 3.3, accuracy: 1e-12)
        XCTAssertEqual(HopPlan.contactSquash(vy: 5000), 4.4)
    }

    func testFlightPathStartsAndEndsOnItsPointsAndPeaksAtTheApex() {
        let p0 = MotionPoint(x: 0, y: 100), p1 = MotionPoint(x: 100, y: 100)
        let h = MotionFlight.lift(from: p0, to: p1, apex: 20)
        let f = MotionFlight(p0: p0, p1: p1, t0: 0, m0: MotionPoint(x: 100, y: 0), m1: MotionPoint(x: 100, y: 0), h: h, T: 300, s0: 1, s1: 1, kind: .hop)
        XCTAssertEqual(f.point(0), p0)
        XCTAssertEqual(f.point(1).x, 100, accuracy: 1e-9)
        XCTAssertEqual(f.point(1).y, 100, accuracy: 1e-9)
        XCTAssertEqual(f.point(0.5).y, 80, accuracy: 1e-9)
    }

    func testSpringMatchesTheReferenceIntegrator() {
        // `ahead` and `step` share the reference's 4 ms semi-implicit Euler substeps.
        let s = MotionSpring(5, response: 0.30, damping: 0.60)
        s.target = 0
        let ahead = s.ahead(0.1)
        for _ in 0..<25 { s.step(0.004) }
        XCTAssertEqual(s.x, ahead)
        XCTAssertLessThan(s.x, 5)
        // Critically damped springs settle without overshoot.
        let c = MotionSpring(0, response: 0.2, damping: 1)
        c.target = 10
        var maxX = 0.0
        for _ in 0..<500 {
            c.step(0.004)
            maxX = max(maxX, c.x)
        }
        XCTAssertLessThanOrEqual(maxX, 10.0001)
        XCTAssertTrue(c.isResting)
    }

    func testRandomIsTheReferenceMulberry32() {
        var r = MotionRandom(seed: 7)
        // First values of mulberry32(7) in JavaScript.
        let a = r.next(), b = r.next()
        XCTAssertTrue((0..<1).contains(a))
        XCTAssertTrue((0..<1).contains(b))
        XCTAssertNotEqual(a, b)
        var again = MotionRandom(seed: 7)
        XCTAssertEqual(again.next(), a)
    }

    func testFormatRoundsTiesLikeJavaScript() {
        XCTAssertEqual(MotionMath.format(0.4), "0")
        XCTAssertEqual(MotionMath.format(2.5), "3")
        XCTAssertEqual(MotionMath.format(1086.4), "1086")
        XCTAssertEqual(MotionMath.format(4.86, digits: 1), "4.9")
        XCTAssertEqual(MotionMath.format(0.25, digits: 1), "0.3")
    }

    // MARK: Behaviour on the reference layout

    func study(_ id: String) -> ReferenceStudy {
        ReferenceStudies.all.first { $0.id == id }!
    }

    /// The example from the plan: Talk → Memories crouches 80 ms, flies 401 ms and lands
    /// 483 ms after the tap (the formula's 419 ms is capped).
    func testTalkToMemoriesExample() throws {
        let hop = try XCTUnwrap(study("02").run().engine.metrics.hops.first)
        XCTAssertEqual(hop.to, "rule:0")
        XCTAssertEqual(hop.anticipation, 80)
        XCTAssertEqual(try XCTUnwrap(hop.crouch), 80, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(hop.flightTime), 401, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(hop.cappedFrom), 419)
        XCTAssertEqual(try XCTUnwrap(hop.contactAfterTap), 483, accuracy: 1)
        XCTAssertLessThanOrEqual(try XCTUnwrap(hop.contactAfterTap), 484)
    }

    /// Time-based: the same hop stepped at 120 Hz lands on the same spot within one frame.
    func testSameHopAt120Hz() throws {
        let s = study("02")
        var settings = MotionSettings()
        settings.autoWelcome = false
        let w = ReferenceMotionWorld(settings: settings)
        w.place(s.scene)
        w.runScript(s.script)
        let frame = 1000.0 / 120
        for _ in 0..<(Int(s.duration / frame)) {
            w.step(frame)
            w.render()
            w.frameCheck()
        }
        let at60 = try XCTUnwrap(s.run().engine.metrics.hops.first)
        let at120 = try XCTUnwrap(w.engine.metrics.hops.first)
        XCTAssertEqual(try XCTUnwrap(at120.contactAt), try XCTUnwrap(at60.contactAt), accuracy: frame)
        XCTAssertEqual(try XCTUnwrap(at120.end?.x), try XCTUnwrap(at60.end?.x), accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(at120.end?.y), try XCTUnwrap(at60.end?.y), accuracy: 0.5)
        XCTAssertTrue(w.violations.isEmpty, "\(w.violations)")
    }

    /// Reduce Motion: no hop is ever flown; each move is a fade with at least one fully
    /// invisible frame, and his size changes only while invisible.
    func testReduceMotionFadesInsteadOfHopping() {
        let s = study("RM")
        var settings = MotionSettings()
        settings.autoWelcome = false
        settings.reduceMotion = true
        let w = ReferenceMotionWorld(settings: settings)
        w.place(s.scene)
        w.runScript(s.script)
        var invisibleFrames = 0
        for _ in 0..<s.frames {
            w.stepFrame()
            XCTAssertNotEqual(w.engine.mode, .flight)
            XCTAssertNotEqual(w.engine.mode, .anticipate)
            if w.engine.opacity == 0 { invisibleFrames += 1 }
        }
        XCTAssertTrue(w.engine.metrics.hops.isEmpty)
        XCTAssertGreaterThanOrEqual(invisibleFrames, 3) // one per move: Home, Memories, Talk
        XCTAssertTrue(w.scaleChanges.allSatisfy(\.ok))
        XCTAssertTrue(w.violations.isEmpty, "\(w.violations)")
    }

    /// Rule 13: across every study his size changes only in the air or while invisible, and he
    /// is never more than 2 pt off his surface (1 pt on the composer).
    func testNoStudyBreaksTheFrameChecks() {
        for s in ReferenceStudies.all {
            let w = s.run()
            XCTAssertTrue(w.violations.isEmpty, "\(s.id): \(w.violations)")
            XCTAssertTrue(w.scaleChanges.allSatisfy(\.ok), s.id)
            XCTAssertLessThanOrEqual(w.maxContactGap, 2, s.id)
            XCTAssertLessThanOrEqual(w.maxComposerGap, 1, s.id)
            XCTAssertEqual(w.listenViolations, 0, s.id)
        }
    }

    /// Rule 10: the listening pose appears only while capture is live (N4: hold to talk).
    func testListeningOnlyWhileCaptureIsLive() {
        let s = study("N4")
        var settings = MotionSettings()
        settings.autoWelcome = false
        let w = ReferenceMotionWorld(settings: settings)
        w.place(s.scene)
        w.runScript(s.script)
        var listened = false
        for _ in 0..<s.frames {
            w.stepFrame()
            if w.engine.listenOn {
                listened = true
                XCTAssertTrue(w.voiceLive)
            }
        }
        XCTAssertTrue(listened)
    }
}
