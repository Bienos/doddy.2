import XCTest
@testable import DoddyCore

/// MV5: the behaviours the pack can draw and the app's real state can drive, on the same
/// iPhone-sized layout as `MotionHostTests`. Each checks the picture the app would show.
final class MotionBehaviourTests: XCTestCase {
    var host: MotionHost!
    var e: MotionEngine { host.engine }
    var opened = 0

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
        host.onOpenTalk = { [unowned self] _ in opened += 1 }
        XCTAssertTrue(host.placeOnCurrentScreen())
    }

    override func setUp() { makeHost() }

    /// Runs `ms`, recording each distinct picture in order.
    @discardableResult
    func run(_ ms: Double, until: ((MotionHost) -> Bool)? = nil) -> [MotionArt.Picture] {
        var seen: [MotionArt.Picture] = []
        var t = 0.0
        let dt = 1000.0 / 240
        while t < ms {
            host.step(dt)
            host.settle()
            t += dt
            let p = MotionArt.choose(e).picture
            if seen.last != p { seen.append(p) }
            if let until, until(host) { break }
        }
        return seen
    }

    func count(_ p: MotionArt.Picture, in seen: [MotionArt.Picture]) -> Int { seen.filter { $0 == p }.count }

    // MARK: Idle on Home

    func testBreathsThenTheSessionsWaveThenHeSitsCrossLegged() {
        let seen = run(20_000)
        // Three breaths on the pack's breathing strip (all four frames).
        for frame in 1...4 { XCTAssertTrue(seen.contains(.strip("idle", frame)), "breath frame \(frame)") }
        // The session's playful moment, once: the wave strip to its open hand.
        let waveStart = try! XCTUnwrap(seen.firstIndex(of: .strip("wave", 1)))
        XCTAssertTrue(seen.contains(.strip("wave", 5)))
        XCTAssertEqual(count(.strip("wave", 1), in: seen), 1, "one playful moment per session")
        // At 15 s idle he sits cross-legged, after the wave.
        let sit = try! XCTUnwrap(seen.firstIndex(of: .pose("crosslegged")))
        XCTAssertGreaterThan(sit, waveStart)
        XCTAssertEqual(MotionArt.choose(e).picture, .pose("crosslegged"))
    }

    /// Hosted run 39379870387: after a long time on Ask's composer he was carried back to Home's
    /// stage and sat down at once, because his 15 s of idle were counted from before he left.
    func testBeingCarriedBackToTheStageRestartsHisIdleSoHeDoesNotSitAtOnce() throws {
        host.behaviours = false
        var settings = e.settings
        settings.noBreath = true
        settings.autoWelcome = false
        e.settings = settings
        run(14_000)
        XCTAssertNotEqual(MotionArt.choose(e).picture, .pose("crosslegged"), "not yet: 14 s")
        e.carried(to: try XCTUnwrap(e.anchor), "back from Ask")
        let after = run(4_000)
        XCTAssertFalse(after.contains(.pose("crosslegged")), "his 15 s start again when he arrives")
        let later = run(14_000)
        XCTAssertTrue(later.contains(.pose("crosslegged")), "and he sits 15 s after arriving")
    }

    func testTheWelcomeIsTheWaveAndThereIsNoPlayfulMomentOnThatVisit() {
        makeHost(welcome: .standard)
        let seen = run(14_000)
        XCTAssertEqual(count(.strip("wave", 1), in: seen), 1, "the welcome, once")
        XCTAssertNotNil(e.metrics.events.first { $0.message.hasPrefix("daily welcome") })
        XCTAssertTrue(e.metrics.playful.isEmpty, "no playful moment on a visit that had the welcome")
    }

    func testAfterThreeDaysAwayTheWelcomeStartsWithAHopInPlace() {
        makeHost(welcome: .back)
        let spot = e.anchor
        let seen = run(4000)
        XCTAssertTrue(seen.contains(.strip("jump", 3)), "a hop")
        XCTAssertTrue(seen.contains(.strip("wave", 1)), "then the wave")
        XCTAssertEqual(e.anchor, spot, "in place")
    }

    func testWelcomePolicy() {
        let cal = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_792_400_000)
        let today = MorningWave.dayKey(now, calendar: cal)
        XCTAssertNil(MotionWelcome.decide(now: now, lastWelcomeDay: today, lastVisit: now, calendar: cal))
        XCTAssertEqual(MotionWelcome.decide(now: now, lastWelcomeDay: "2000-01-01", lastVisit: now.addingTimeInterval(-3600), calendar: cal)?.kind, .standard)
        XCTAssertEqual(MotionWelcome.decide(now: now, lastWelcomeDay: nil, lastVisit: now.addingTimeInterval(-3 * 86_400), calendar: cal)?.kind, .back)
        XCTAssertEqual(MotionWelcome.decide(now: now, lastWelcomeDay: nil, lastVisit: nil, calendar: cal)?.day, today)
    }

    // MARK: Touch

    func testATapOnHimOpensTalkAndAHoldDoesTooWhenReleased() {
        let soles = e.pos
        host.touchDown(x: soles.x, y: soles.y - 60)
        run(60)
        // Touch-down dip: a whole-picture squash, within 60 ms.
        XCTAssertLessThan(MotionArt.choose(e).scaleY, 1)
        host.touchUp(vx: 0, vy: 0)
        XCTAssertEqual(opened, 1, "a tap opens the voice screen")
        run(400)
        // A hold can't start capture on Home (plan section 5): released, it opens the voice screen.
        host.touchDown(x: soles.x, y: soles.y - 60)
        run(600)
        XCTAssertEqual(opened, 1, "nothing until he is let go")
        host.touchUp(vx: 0, vy: 0)
        XCTAssertEqual(opened, 2)
    }

    func testADragLeansHimAndAnUpwardFlickIsAHopInPlace() {
        let soles = e.pos
        host.touchDown(x: soles.x, y: soles.y - 60)
        host.touchMoved(x: soles.x + 40, y: soles.y - 60, vx: 300, vy: 0)
        run(300)
        XCTAssertGreaterThan(MotionArt.choose(e).tilt, 3, "leans with the drag")
        XCTAssertEqual(opened, 0)
        host.touchMoved(x: soles.x + 40, y: soles.y - 120, vx: 0, vy: -1500)
        host.touchUp(vx: 0, vy: -1500)
        XCTAssertEqual(opened, 0, "a drag isn't a tap")
        let seen = run(1500, until: { $0.engine.mode == .attached && $0.engine.now - $0.engine.lastLand > 300 })
        XCTAssertTrue(seen.contains(.strip("jump", 3)), "the flick: a hop")
        XCTAssertEqual(e.anchor?.surface, .stage)
    }

    // MARK: Ask and voice

    func testThinkingInAskOnlyWhileTheReplyHasNotCome() {
        host.talkOpened()
        host.scene.frames[.composer] = MotionRect(x: 0, y: 700, width: 393, height: 68)
        host.scene.mounted.insert(.composer)
        run(50)
        XCTAssertEqual(host.placement, .slot(.composer))
        host.askSending(true, failed: false)
        run(500)
        XCTAssertFalse(e.isThinking)
        XCTAssertNotNil(host.nextDue, "the clock wakes for it")
        run(200)
        XCTAssertTrue(e.isThinking)
        XCTAssertEqual(MotionArt.choose(e).picture, .pose("kneeling_inspect"))
        host.askSending(false, failed: false)
        XCTAssertFalse(e.isThinking)
        XCTAssertNotEqual(MotionArt.choose(e).picture, .pose("kneeling_inspect"))
    }

    func testListeningPoseOnlyWhileTheMicrophoneIsLive() {
        var checks = MotionChecks()
        run(300)
        XCTAssertFalse(e.pose.listening)
        host.voiceListening(true)
        let seen = run(500)
        XCTAssertTrue(seen.contains(.pose("listening")))
        host.voiceListening(false)
        run(500)
        XCTAssertFalse(e.pose.listening)
        checks.check(host, drawn: 1)
        XCTAssertEqual(checks.count, 0)
    }

    // MARK: Reduce Motion

    func testReduceMotionHasNoDipNoPlayfulMoment() {
        makeHost(reduceMotion: true)
        host.touchDown(x: e.pos.x, y: e.pos.y - 60)
        run(100)
        XCTAssertEqual(MotionArt.choose(e).scaleY, 1)
        host.touchUp(vx: 0, vy: 0)
        let seen = run(12_000)
        XCTAssertFalse(seen.contains(.strip("wave", 1)))
        XCTAssertFalse(seen.contains(.strip("idle", 2)), "no breaths with Reduce Motion")
    }
}
