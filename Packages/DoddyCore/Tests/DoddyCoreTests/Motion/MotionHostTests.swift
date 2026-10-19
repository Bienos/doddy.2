import XCTest
@testable import DoddyCore

/// MV3: the app's side of the motion world (`MotionHost`) on an iPhone-sized layout: tab hops,
/// where he is drawn in every frame, covers, pages and first visits. The surfaces are what the
/// app's screens report (MV2): Home's stage line, Memories cards, the Settings ledge, the rail.
final class MotionHostTests: XCTestCase {
    // A 393 pt iPhone. The tab bar capsule (the rail) at y 760; three tabs.
    static let rail = MotionRect(x: 24, y: 760, width: 345, height: 60)
    static let stage = MotionRect(x: 126.5, y: 430, width: 140, height: 1)
    static let settingsLedge = MotionRect(x: 60, y: 230, width: 60, height: 1)
    static let listViewport = MotionRect(x: 0, y: 59, width: 393, height: 693)
    static func card(_ i: Int) -> MotionRect { MotionRect(x: 24, y: 420 + 122 * Double(i), width: 345, height: 110) }

    var host: MotionHost!
    var stepCount = 0

    override func setUp() {
        host = MotionHost()
        var s = MotionScene()
        s.frames[.rail] = Self.rail
        s.frames[.stage] = Self.stage
        s.marks["tab.home"] = MotionRect(x: 32, y: 768, width: 110, height: 44)
        s.marks["tab.memories"] = MotionRect(x: 146, y: 768, width: 101, height: 44)
        s.marks["tab.settings"] = MotionRect(x: 251, y: 768, width: 110, height: 44)
        s.mounted = [.rail, .stage]
        host.scene = s
        XCTAssertTrue(host.placeOnCurrentScreen())
    }

    // MARK: Helpers

    func showMemories(cards n: Int = 4) {
        host.scene.mounted.remove(.stage)
        host.scene.marks["memories.list"] = Self.listViewport
        host.scene.ruleCount = n
        for i in 0..<n {
            host.scene.frames[.rule(i)] = Self.card(i)
            host.scene.mounted.insert(.rule(i))
        }
    }

    func hideMemories() {
        for i in 0..<host.scene.ruleCount { host.scene.mounted.remove(.rule(i)) }
    }

    /// Steps 4.1667 ms at a time (four per 60 Hz frame, as the reference does), recording where
    /// he is drawn, until `until` holds or `maxMs` passes.
    @discardableResult
    func run(maxMs: Double, until: ((MotionHost) -> Bool)? = nil, each: ((MotionHost) -> Void)? = nil) -> Double {
        var t = 0.0
        let dt = 1000.0 / 240
        while t < maxMs {
            host.step(dt)
            host.settle()
            t += dt
            each?(host)
            if let until, until(host) { break }
        }
        return t
    }

    var e: MotionEngine { host.engine }

    // MARK: Tests

    func testPlacedOnHomeStageAt1point4() {
        XCTAssertEqual(e.anchor, MotionSpot(.stage, x: 196.5))
        XCTAssertEqual(e.scale, 1.4, accuracy: 1e-9)
        XCTAssertEqual(host.placement, .slot(.stage))
    }

    /// Hosted run 39210073005: at launch the tab bar reported before Home's stage, he was placed
    /// on the rail and stayed there. He now waits for the screen's spot, and if he is ever left on
    /// the rail with nothing to wait for, he goes to it.
    func testAtLaunchHeWaitsForHomesStageNotTheRail() {
        let h = MotionHost()
        var s = MotionScene()
        s.frames[.rail] = Self.rail
        s.mounted = [.rail]
        h.scene = s
        XCTAssertFalse(h.placeOnCurrentScreen(), "Home hasn't reported its stage yet")
        h.step(20)
        XCTAssertFalse(h.placeOnCurrentScreen())
        h.scene.frames[.stage] = Self.stage
        h.scene.mounted.insert(.stage)
        XCTAssertTrue(h.placeOnCurrentScreen())
        XCTAssertEqual(h.engine.anchor?.surface, .stage)

        // A stage that doesn't report within 60 ms: he starts on the rail, and goes to the stage
        // once it is there (he has nothing to wait for on the rail).
        let late = MotionHost()
        late.scene = s
        XCTAssertFalse(late.placeOnCurrentScreen())
        late.step(70)
        XCTAssertTrue(late.placeOnCurrentScreen())
        XCTAssertEqual(late.engine.anchor?.surface, .rail)
        late.scene.frames[.stage] = Self.stage
        late.scene.mounted.insert(.stage)
        for _ in 0..<480 where !(late.engine.anchor?.surface == .stage && late.engine.mode == .attached) {
            late.step(1000.0 / 240)
            late.settle()
        }
        XCTAssertEqual(late.engine.anchor?.surface, .stage)
        XCTAssertEqual(late.engine.scale, 1.4, accuracy: 1e-9)
    }

    func testTabHopToMemoriesLandsOnTheFirstCardWithRoomAndOnTime() {
        let tap = e.now
        host.tabChanged(to: .memories, tapT: tap)
        showMemories()
        var placements: [MotionPlacement] = []
        var scaleChangedOnGround = false
        var lastScale = e.scale
        run(maxMs: 1500, until: { $0.engine.mode == .attached && $0.engine.anchor?.surface.isRule == true && $0.engine.now - $0.engine.lastLand > 300 }) { h in
            placements.append(h.placement)
            if abs(h.engine.scale - lastScale) > 1e-6, h.engine.mode != .flight { scaleChangedOnGround = true }
            lastScale = h.engine.scale
        }
        // Card 0's top edge is the list's top: his body would cover the heading and filters, so he
        // stands on card 1, at the right end, in the gutter.
        XCTAssertEqual(e.anchor, MotionSpot(.rule(1), x: 369 - 36))
        XCTAssertEqual(e.scale, 1, accuracy: 1e-9)
        XCTAssertFalse(scaleChangedOnGround, "his size changes only in the air")
        XCTAssertFalse(placements.contains(.hidden), "never zero Doddys during the hop")
        XCTAssertTrue(placements.contains(.overlay))
        XCTAssertEqual(placements.last, .slot(.rule(1)))
        let hop = try! XCTUnwrap(e.metrics.hops.last)
        XCTAssertTrue(hop.isTabHop)
        XCTAssertLessThanOrEqual(try! XCTUnwrap(hop.contactAfterTap), 484 + 5)
        XCTAssertGreaterThanOrEqual(try! XCTUnwrap(hop.contactAfterTap), 340)
        XCTAssertEqual(hop.anticipation, 80)
    }

    func testHopBackToHomeGrowsOnlyInTheAir() {
        host.tabChanged(to: .memories, tapT: e.now)
        showMemories()
        run(maxMs: 1500, until: { $0.engine.anchor?.surface.isRule == true && $0.engine.now - $0.engine.lastLand > 400 })
        host.tabChanged(to: .home, tapT: e.now)
        hideMemories()
        host.scene.mounted.insert(.stage)
        var scales: [(Double, MotionEngine.Mode)] = []
        run(maxMs: 1500, until: { $0.engine.anchor?.surface == .stage && $0.engine.now - $0.engine.lastLand > 300 }) { h in
            scales.append((h.engine.scale, h.engine.mode))
        }
        XCTAssertEqual(e.anchor, MotionSpot(.stage, x: 196.5))
        XCTAssertEqual(e.scale, 1.4, accuracy: 1e-9)
        for (i, s) in scales.enumerated().dropFirst() where abs(s.0 - scales[i - 1].0) > 1e-6 {
            XCTAssertEqual(s.1, .flight, "scale changed outside the flight")
        }
        XCTAssertEqual(host.placement, .slot(.stage))
    }

    func testACoverHidesHimAndHoldsHimStill() {
        host.scene.covers = 1
        XCTAssertEqual(host.placement, .hidden)
        XCTAssertTrue(host.isCovered)
        e.updateDestination(MotionReason("anything"))
        XCTAssertEqual(e.mode, .attached)
        host.scene.covers = 0
        XCTAssertEqual(host.placement, .slot(.stage))
    }

    func testFirstVisitWaitsForTheScreenToReportItsSpot() {
        host.scene.frames[.ledge("settings")] = nil
        host.tabChanged(to: .settings, tapT: e.now)
        host.scene.mounted.remove(.stage)
        // Settings hasn't reported its ledge yet: he waits, drawn where he was, never hidden.
        XCTAssertNotNil(host.pendingTab)
        XCTAssertEqual(host.placement, .overlay)
        run(maxMs: 50)
        XCTAssertEqual(e.mode, .attached)
        // The ledge reports; the hop starts on the next frame and lands on it.
        host.scene.frames[.ledge("settings")] = Self.settingsLedge
        host.scene.mounted.insert(.ledge("settings"))
        run(maxMs: 1500, until: { $0.engine.anchor?.surface == .ledge("settings") && $0.engine.mode == .attached })
        XCTAssertNil(host.pendingTab)
        XCTAssertEqual(e.anchor, MotionSpot(.ledge("settings"), x: 90))
        XCTAssertEqual(host.placement, .slot(.ledge("settings")))
    }

    func testAPageOverHisCardCoversHimInPlace() {
        host.tabChanged(to: .memories, tapT: e.now)
        showMemories()
        run(maxMs: 1500, until: { $0.engine.anchor?.surface.isRule == true && $0.engine.now - $0.engine.lastLand > 300 })
        let spot = e.anchor
        // Find is pushed: the list goes off screen under it.
        host.scene.pages[.memories] = MotionPage(open: true, detail: false)
        hideMemories()
        run(maxMs: 500)
        XCTAssertEqual(e.anchor, spot)
        XCTAssertEqual(e.mode, .attached)
        XCTAssertEqual(host.placement, .hidden)
        // Back: revealed where he stood.
        host.scene.pages[.memories] = MotionPage()
        showMemories()
        XCTAssertEqual(host.placement, .slot(spot!.surface))
    }

    func testANoteDetailPushedOverHisCardCoversHimThePopRevealsHim() {
        host.tabChanged(to: .memories, tapT: e.now)
        showMemories()
        run(maxMs: 1500, until: { $0.engine.anchor?.surface.isRule == true && $0.engine.now - $0.engine.lastLand > 300 })
        host.scene.pages[.memories] = MotionPage(open: true, detail: true)
        XCTAssertTrue(e.pagePushed())
        hideMemories()
        XCTAssertEqual(host.placement, .hidden)
        host.scene.pages[.memories] = MotionPage()
        e.pagePopped()
        showMemories()
        XCTAssertFalse(e.hiddenBehind)
        XCTAssertEqual(host.placement, .slot(.rule(1)))
    }

    func testWhenHisCardGoesAwayHeMovesOnce() {
        host.tabChanged(to: .memories, tapT: e.now)
        showMemories()
        run(maxMs: 1500, until: { $0.engine.anchor?.surface.isRule == true && $0.engine.now - $0.engine.lastLand > 300 })
        // The note is deleted: its card leaves; the list has one card fewer.
        host.scene.mounted.remove(.rule(3))
        host.scene.frames[.rule(3)] = nil
        host.scene.ruleCount = 3
        host.scene.mounted.remove(.rule(1))
        var started = false
        run(maxMs: 1500, until: { h in
            if h.engine.mode != .attached { started = true }
            return started && h.engine.mode == .attached && h.engine.now - h.engine.lastLand > 300
        })
        XCTAssertTrue(started)
        XCTAssertNotEqual(e.anchor?.surface, .rule(1))
        XCTAssertNotEqual(host.placement, .hidden)
    }

    func testFindWithNothingFoundBringsHimOutToShrugThere() {
        host.tabChanged(to: .memories, tapT: e.now)
        showMemories()
        run(maxMs: 1500, until: { $0.engine.anchor?.surface.isRule == true && $0.engine.now - $0.engine.lastLand > 300 })
        // Find is pushed over his card: covered in place.
        host.scene.pages[.memories] = MotionPage(open: true, detail: false)
        XCTAssertTrue(e.pagePushed())
        hideMemories()
        run(maxMs: 300)
        XCTAssertEqual(host.placement, .hidden)
        // Nothing found: the page shows his spot. He waits for its frame, then hops there once.
        let find = MotionSurfaceID.ledge(MotionHost.findLedge)
        host.scene.mounted.insert(find)
        host.surfaceAppeared(find)
        run(maxMs: 100)
        XCTAssertEqual(host.placement, .hidden, "no frame yet: he stays covered")
        host.scene.frames[find] = MotionRect(x: 135, y: 330, width: 96, height: 1)
        var drawnTwiceOrNever = false
        run(maxMs: 1500, until: { $0.engine.anchor?.surface == find && $0.engine.mode == .attached && $0.engine.now - $0.engine.lastLand > 300 }) { h in
            if h.placement == .hidden, h.engine.mode != .attached { drawnTwiceOrNever = true }
        }
        XCTAssertFalse(drawnTwiceOrNever)
        XCTAssertFalse(e.hiddenBehind)
        XCTAssertEqual(e.anchor, MotionSpot(find, x: 183))
        XCTAssertEqual(host.placement, .slot(find))
        // A search that finds something: the spot goes, and he is out of sight with the page.
        host.scene.mounted.remove(find)
        run(maxMs: 300)
        XCTAssertEqual(host.placement, .hidden)
        XCTAssertEqual(e.mode, .attached)
    }

    func testSettingsRowScrolledAwayTakesHimWithIt() {
        host.scene.frames[.ledge("settings")] = Self.settingsLedge
        host.tabChanged(to: .settings, tapT: e.now)
        host.scene.mounted = [.rail, .ledge("settings")]
        run(maxMs: 1500, until: { $0.engine.anchor?.surface == .ledge("settings") && $0.engine.now - $0.engine.lastLand > 300 })
        // The Form recycles the row once it has scrolled away: he doesn't hop to the rail.
        host.scene.mounted.remove(.ledge("settings"))
        run(maxMs: 800)
        XCTAssertEqual(e.anchor?.surface, .ledge("settings"))
        XCTAssertEqual(e.mode, .attached)
        XCTAssertEqual(host.placement, .hidden)
        host.scene.mounted.insert(.ledge("settings"))
        XCTAssertEqual(host.placement, .slot(.ledge("settings")))
    }

    func testEmptyMemoriesUsesItsLedge() {
        host.tabChanged(to: .memories, tapT: e.now)
        host.scene.mounted.remove(.stage)
        let empty = MotionSurfaceID.ledge("emptyMemories")
        host.scene.frames[empty] = MotionRect(x: 148.5, y: 400, width: 96, height: 1)
        host.scene.mounted.insert(empty)
        host.settle()
        run(maxMs: 1500, until: { $0.engine.anchor?.surface == empty && $0.engine.mode == .attached })
        XCTAssertEqual(e.anchor, MotionSpot(empty, x: 196.5))
    }

    func testRapidSwitchingWaitsOnTheRailThenHopsOnce() {
        host.scene.frames[.ledge("settings")] = Self.settingsLedge
        for i in 0..<4 { host.scene.frames[.rule(i)] = Self.card(i) }
        host.scene.marks["memories.list"] = Self.listViewport
        host.scene.ruleCount = 4
        func tap(_ s: MotionScreen) {
            host.tabChanged(to: s, tapT: e.now)
            host.scene.mounted = [.rail]
            switch s {
            case .home: host.scene.mounted.insert(.stage)
            case .memories: for i in 0..<4 { host.scene.mounted.insert(.rule(i)) }
            case .settings: host.scene.mounted.insert(.ledge("settings"))
            case .talk: break
            }
        }
        tap(.memories); run(maxMs: 150)
        tap(.settings); run(maxMs: 150)
        tap(.home); run(maxMs: 150)
        XCTAssertTrue(e.calm, "three changes within 900 ms: calm mode")
        run(maxMs: 2000, until: { $0.engine.mode == .attached && $0.engine.anchor?.surface == .stage && $0.engine.now - $0.engine.lastLand > 300 })
        XCTAssertFalse(e.calm)
        XCTAssertEqual(e.anchor?.surface, .stage)
        XCTAssertTrue(e.metrics.hops.contains { $0.to == "rail" }, "waited on the rail")
    }

    func testReduceMotionFadesAndChangesSizeOnlyUnseen() {
        e.setReduceMotion(true)
        host.tabChanged(to: .memories, tapT: e.now)
        showMemories()
        var flew = false, badScale = false
        var last = e.scale
        run(maxMs: 1000, until: { $0.engine.mode == .attached && $0.engine.anchor?.surface.isRule == true && $0.engine.opacity >= 1 }) { h in
            if h.engine.mode == .flight { flew = true }
            if abs(h.engine.scale - last) > 1e-6, h.engine.opacity > 0.01 { badScale = true }
            last = h.engine.scale
        }
        XCTAssertFalse(flew)
        XCTAssertFalse(badScale)
        XCTAssertEqual(e.anchor?.surface, .rule(1))
    }

    func testStillOnceSettledAndNothingDueOffHome() {
        // MV3 runs without breaths (MV5 turns them on).
        e.settings.noBreath = true
        host.tabChanged(to: .settings, tapT: e.now)
        host.scene.mounted = [.rail, .ledge("settings")]
        host.scene.frames[.ledge("settings")] = Self.settingsLedge
        host.settle()
        let t = run(maxMs: 3000, until: { $0.engine.mode == .attached && $0.engine.isStill })
        XCTAssertTrue(e.isStill)
        XCTAssertLessThan(t, 1500, "the landing settles within a second or so")
        XCTAssertNil(e.nextDue, "off Home nothing is due: the app's clock can stop")
    }

    func testBreathsKeepTheClockRunningThenStop() {
        host.tabChanged(to: .settings, tapT: e.now)
        host.scene.mounted = [.rail, .ledge("settings")]
        host.scene.frames[.ledge("settings")] = Self.settingsLedge
        host.settle()
        run(maxMs: 1500, until: { $0.engine.mode == .attached && $0.engine.now - $0.engine.lastLand > 1000 })
        // Three breaths start 2 s after the landing (4.2 s each), then he holds still. Before them
        // he is still, with the first breath due: the clock sleeps until then.
        XCTAssertTrue(e.isStill)
        XCTAssertEqual(try XCTUnwrap(e.nextDue), e.lastLand + 2000, accuracy: 1)
        run(maxMs: 2000, until: { $0.engine.breathPhase != nil })
        XCTAssertFalse(e.isStill, "breathing")
        let t = run(maxMs: 20_000, until: { $0.engine.isStill && $0.engine.now - $0.engine.lastLand > 2000 })
        XCTAssertTrue(e.isStill)
        XCTAssertGreaterThan(e.now - e.lastLand, 2000 + 3 * 4200 - 100, "after the three breaths, \(t) ms")
        XCTAssertNil(e.nextDue)
    }

    func testRailSpotIsUnderTheTab() {
        XCTAssertEqual(host.railSpot(.memories), MotionSpot(.rail, x: 196.5))
        XCTAssertEqual(host.railSpot(.talk).x, 87, accuracy: 1e-9)
    }

    // MARK: DEBUG checks

    func testChecksPassThroughTabHopsAndAHomeSizeChange() {
        var checks = MotionChecks()
        host.tabChanged(to: .memories, tapT: e.now)
        showMemories()
        run(maxMs: 1500, until: { $0.engine.anchor?.surface.isRule == true && $0.engine.now - $0.engine.lastLand > 400 }) { h in
            checks.check(h, drawn: h.placement == .hidden ? 0 : 1)
        }
        host.tabChanged(to: .home, tapT: e.now)
        hideMemories()
        host.scene.mounted.insert(.stage)
        run(maxMs: 1500, until: { $0.engine.anchor?.surface == .stage && $0.engine.now - $0.engine.lastLand > 400 }) { h in
            checks.check(h, drawn: h.placement == .hidden ? 0 : 1)
        }
        // Accessibility text sizes (Q12): Home's size changes while he is faded out.
        host.scene.homeScale = 1.0
        e.homeScaleChanged(1.0)
        run(maxMs: 600, each: { h in checks.check(h, drawn: 1) })
        XCTAssertEqual(e.scale, 1.0, accuracy: 1e-9)
        XCTAssertEqual(checks.count, 0, "\(checks.violations)")
    }

    /// Hosted run 39282487184: the checks ran before he was placed, read his default 1.0× and then
    /// flagged the first real size (1.4× on Home) as a size change on the ground.
    func testChecksWaitUntilHeIsPlacedAndOneFrameOfTwoDrawingsIsNotTwo() {
        let h = MotionHost()
        var s = MotionScene()
        s.frames[.rail] = Self.rail
        s.mounted = [.rail]
        h.scene = s
        var checks = MotionChecks()
        for _ in 0..<10 {
            h.step(1000.0 / 240)
            checks.check(h, drawn: 0)
        }
        h.scene.frames[.stage] = Self.stage
        h.scene.mounted.insert(.stage)
        XCTAssertTrue(h.placeOnCurrentScreen())
        h.step(1000.0 / 240)
        checks.check(h, drawn: 1)
        XCTAssertEqual(checks.count, 0, "\(checks.violations)")
        // SwiftUI swaps the drawings in one update: two for one check is not two.
        checks.check(h, drawn: 2)
        checks.check(h, drawn: 1)
        XCTAssertEqual(checks.count, 0)
        // Two that stay are.
        checks.check(h, drawn: 2)
        checks.check(h, drawn: 2)
        XCTAssertEqual(checks.count, 1)
        XCTAssertTrue(checks.lastDetail.hasPrefix("one Doddy"))
    }

    func testChecksCatchTwoDrawingsAndAZoneOverSend() {
        var checks = MotionChecks()
        checks.check(host, drawn: 2)
        checks.check(host, drawn: 2)
        XCTAssertEqual(checks.violations.last?.rule, "one Doddy")
        // A Send button right beside his spot on the stage.
        host.scene.marks["send"] = MotionRect(x: 200, y: 400, width: 40, height: 30)
        host.scene.mounted.insert(.composer)
        checks.check(host, drawn: 1)
        XCTAssertEqual(checks.count, 1, "one frame under Send isn't a finding yet")
        host.step(10)
        host.settle()
        checks.check(host, drawn: 1)
        XCTAssertEqual(checks.violations.last?.rule, "clear zone")
        XCTAssertEqual(checks.count, 2)
        XCTAssertTrue(checks.lastDetail.contains("covers send"), checks.lastDetail)
    }

    /// The app reports Send and his spot in separate callbacks: a frame in which only one of them
    /// has moved is not a finding; the next frame's agreement clears it.
    func testAZoneOverSendForOneFrameOnlyIsNotAFinding() {
        var checks = MotionChecks()
        host.scene.marks["send"] = MotionRect(x: 200, y: 400, width: 40, height: 30)
        host.scene.mounted.insert(.composer)
        checks.check(host, drawn: 1)
        host.scene.marks["send"] = MotionRect(x: 333, y: 712, width: 44, height: 44)
        host.step(10)
        host.settle()
        checks.check(host, drawn: 1)
        host.step(10)
        host.settle()
        checks.check(host, drawn: 1)
        XCTAssertEqual(checks.count, 0, "\(checks.violations)")
    }

    // MARK: Art

    func testArtFollowsTheHop() {
        XCTAssertEqual(MotionArt.choose(e).picture, .strip("idle", 1))
        host.tabChanged(to: .memories, tapT: e.now)
        showMemories()
        var seen: [MotionArt.Picture] = []
        run(maxMs: 1500, until: { $0.engine.mode == .attached && $0.engine.now - $0.engine.lastLand > 400 }) { h in
            let p = MotionArt.choose(h.engine).picture
            if seen.last != p { seen.append(p) }
        }
        XCTAssertEqual(seen, [.strip("jump", 1), .strip("jump", 2), .strip("jump", 3), .strip("jump", 4), .strip("jump", 5), .strip("idle", 1)])
        XCTAssertEqual(MotionArt.choose(e).marker, "doddy.motion.idle")
    }

    func testArtMirrorsAHopToTheLeft() {
        // From Memories' card (x 333) to Home's stage (x 196.5): leftwards.
        host.tabChanged(to: .memories, tapT: e.now)
        showMemories()
        run(maxMs: 1500, until: { $0.engine.anchor?.surface.isRule == true && $0.engine.now - $0.engine.lastLand > 400 })
        host.tabChanged(to: .home, tapT: e.now)
        hideMemories()
        host.scene.mounted.insert(.stage)
        var mirroredInFlight = false
        run(maxMs: 1500, until: { $0.engine.anchor?.surface == .stage && $0.engine.mode == .attached }) { h in
            if h.engine.mode == .flight, MotionArt.choose(h.engine).mirrored { mirroredInFlight = true }
        }
        XCTAssertTrue(mirroredInFlight)
    }

    func testArtStillPosesAndReduceMotion() {
        XCTAssertEqual(MotionArt.choose(e, still: "crosslegged").picture, .pose("crosslegged"))
        XCTAssertEqual(MotionArt.choose(e, still: "facepalm").marker, "doddy.pose.facepalm")
        e.setReduceMotion(true)
        let a = MotionArt.choose(e)
        XCTAssertEqual(a.scaleY, 1)
        XCTAssertEqual(a.tilt, 0)
    }
}
