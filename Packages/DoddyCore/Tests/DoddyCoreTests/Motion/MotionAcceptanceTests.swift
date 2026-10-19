import XCTest
@testable import DoddyCore

/// MV6 evidence (docs/design/MOTION_V2_PLAN.md section 6): the brief's rules checked on one
/// scripted journey through the app's screens as the host sees them, with the DEBUG checks
/// (`MotionChecks`: one Doddy, soles on his edge, size only in the air or unseen, clear zones,
/// listening only while live) run on every frame. What this can't show, the screen itself, is in
/// the UI tests (`MotionEvidenceTests` and the MV2 to MV5 suites); what only a device shows is in
/// docs/design/MOTION_V2_DEVICE_CHECKLIST.md.
final class MotionAcceptanceTests: XCTestCase {
    var host: MotionHost!
    var e: MotionEngine { host.engine }
    var checks = MotionChecks()
    var placements: [MotionPlacement] = []
    var flights = 0

    func make(reduceMotion: Bool = false) {
        var settings = MotionSettings()
        settings.reduceMotion = reduceMotion
        host = MotionHost(settings: settings)
        var s = MotionScene()
        s.frames[.rail] = MotionHostTests.rail
        s.frames[.stage] = MotionHostTests.stage
        s.frames[.ledge("settings")] = MotionHostTests.settingsLedge
        s.marks["tab.home"] = MotionRect(x: 32, y: 768, width: 110, height: 44)
        s.marks["tab.memories"] = MotionRect(x: 146, y: 768, width: 101, height: 44)
        s.marks["tab.settings"] = MotionRect(x: 251, y: 768, width: 110, height: 44)
        s.mounted = [.rail, .stage]
        host.scene = s
        host.behaviours = true
        XCTAssertTrue(host.placeOnCurrentScreen())
        checks = MotionChecks()
        placements = []
        flights = 0
    }

    override func setUp() { make() }

    func run(_ ms: Double, before: ((MotionHost) -> Void)? = nil, until: ((MotionHost) -> Bool)? = nil) {
        var t = 0.0
        let dt = 1000.0 / 240
        var lastMode = e.mode
        while t < ms {
            before?(host)
            host.step(dt)
            host.settle()
            t += dt
            checks.check(host, drawn: host.placement == .hidden ? 0 : 1)
            placements.append(host.placement)
            if e.mode == .flight, lastMode != .flight { flights += 1 }
            lastMode = e.mode
            if let until, until(host) { break }
        }
    }

    func landed(on surface: MotionSurfaceID) -> (MotionHost) -> Bool {
        { $0.engine.anchor?.surface == surface && $0.engine.mode == .attached && $0.engine.now - $0.engine.lastLand > 300 }
    }

    func showCards(_ n: Int) {
        host.scene.marks["memories.list"] = MotionHostTests.listViewport
        host.scene.ruleCount = n
        for i in 0..<n {
            host.scene.frames[.rule(i)] = MotionHostTests.card(i)
            host.scene.mounted.insert(.rule(i))
        }
    }

    func hideCards() { for i in 0..<host.scene.ruleCount { host.scene.mounted.remove(.rule(i)) } }

    func tab(_ screen: MotionScreen) {
        host.scene.mounted = host.scene.mounted.filter { MotionScene.screen(of: $0) == nil }
        host.tabChanged(to: screen, tapT: e.now)
        switch screen {
        case .home: host.scene.mounted.insert(.stage)
        case .memories: showCards(6)
        case .settings: host.scene.mounted.insert(.ledge("settings"))
        case .talk: break
        }
    }

    // MARK: The journey

    func testAJourneyThroughEveryScreenKeepsEveryRule() {
        run(3000)
        // Home → Memories: lands on a card at 1.0×.
        tab(.memories)
        run(1500, until: { $0.engine.anchor?.surface.isRule == true && $0.engine.mode == .attached && $0.engine.now - $0.engine.lastLand > 300 })
        let card = try! XCTUnwrap(e.anchor)
        // A note's page covers him in place; Back reveals him there.
        host.scene.pages[.memories] = MotionPage(open: true, detail: true)
        XCTAssertTrue(e.pagePushed())
        hideCards()
        run(600)
        host.scene.pages[.memories] = MotionPage()
        e.pagePopped()
        showCards(6)
        run(300)
        XCTAssertEqual(e.anchor, card)
        // The list scrolls gently: he rides, then makes one lily-pad hop or waits on the rail.
        host.listPhaseChanged(.interacting)
        run(2500, before: { h in
            let d = 200.0 / 240
            for i in 0..<6 { if var f = h.scene.frames[.rule(i)] { f.y -= d; h.scene.frames[.rule(i)] = f } }
            h.listScrolled(to: h.scene.scroll.offset + d)
        })
        host.listPhaseChanged(.idle)
        run(1500)
        XCTAssertTrue(e.anchor?.surface.isRule == true || e.anchor?.surface == .rail)
        // Settings, then Home at 1.4×.
        tab(.settings)
        run(1500, until: landed(on: .ledge("settings")))
        tab(.home)
        run(1500, until: landed(on: .stage))
        XCTAssertEqual(e.scale, 1.4, accuracy: 1e-9)
        // Ask: carried up on the composer, the keyboard moves it, closing brings him home.
        host.talkOpened()
        host.scene.frames[.composer] = MotionRect(x: 0, y: 700, width: 393, height: 68)
        host.scene.marks["send"] = MotionRect(x: 333, y: 712, width: 44, height: 44)
        host.scene.mounted.insert(.composer)
        run(100)
        host.scene.keyboardUp = true
        host.scene.frames[.composer] = MotionRect(x: 0, y: 380, width: 393, height: 68)
        run(300)
        host.scene.mounted.remove(.composer)
        host.talkClosing()
        checks.check(host, drawn: 1)
        run(1000)

        XCTAssertEqual(checks.count, 0, "\(checks.violations)")
        // Rule 2: every tab hop lands within the cap after the tap.
        let tabHops = e.metrics.hops.filter(\.isTabHop)
        XCTAssertGreaterThanOrEqual(tabHops.count, 3)
        for hop in tabHops { XCTAssertLessThanOrEqual(hop.contactAfterTap ?? 0, 484 + 5, "\(hop.from) → \(hop.to)") }
        // Rule 1: drawn in one place every frame; hidden only under the page (and the cover's start).
        XCTAssertLessThan(placements.filter { $0 == .hidden }.count, 240, "hidden for under a second in all")
    }

    // MARK: Reduce Motion (brief rule 12)

    func testReduceMotionNeverLeavesTheGroundAndChangesSizeUnseen() {
        make(reduceMotion: true)
        for screen in [MotionScreen.memories, .settings, .home] {
            tab(screen)
            run(1500, until: { h in
                guard let a = h.engine.anchor, h.engine.mode == .attached else { return false }
                return MotionScene.screen(of: a.surface) == screen
            })
        }
        XCTAssertEqual(flights, 0, "fades only")
        XCTAssertEqual(e.anchor?.surface, .stage)
        XCTAssertEqual(checks.count, 0, "\(checks.violations)")
        XCTAssertTrue(e.metrics.playful.isEmpty)
    }

    // MARK: "Hide Doddy's pictures" (brief rule 12)

    func testWithThePicturesHiddenNothingIsDrawnAndTheClockSleeps() {
        host.isActive = false
        tab(.memories)
        run(1000)
        XCTAssertTrue(placements.allSatisfy { $0 == .hidden })
        XCTAssertFalse(host.wantsFrames)
        XCTAssertNil(host.ridingList())
    }
}
