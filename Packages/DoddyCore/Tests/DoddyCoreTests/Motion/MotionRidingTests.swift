import XCTest
@testable import DoddyCore

/// MV4: he rides what moves. The Memories list's scroll (iOS 18's measured scroll, and iOS 17's
/// rail-only fallback, Q10), Ask's composer coming up with its cover, and the undo bar appearing
/// under him. The same iPhone-sized layout as `MotionHostTests`.
final class MotionRidingTests: XCTestCase {
    var host: MotionHost!
    var e: MotionEngine { host.engine }
    static let composer = MotionRect(x: 0, y: 700, width: 393, height: 68)
    static let send = MotionRect(x: 333, y: 712, width: 44, height: 44)
    static let undoBar = MotionRect(x: 0, y: 696, width: 393, height: 52)
    static let undo = MotionRect(x: 300, y: 700, width: 70, height: 44)

    override func setUp() {
        host = MotionHost()
        var s = MotionScene()
        s.frames[.rail] = MotionHostTests.rail
        s.frames[.stage] = MotionHostTests.stage
        s.marks["tab.home"] = MotionRect(x: 32, y: 768, width: 110, height: 44)
        s.marks["tab.memories"] = MotionRect(x: 146, y: 768, width: 101, height: 44)
        s.marks["tab.settings"] = MotionRect(x: 251, y: 768, width: 110, height: 44)
        s.mounted = [.rail, .stage]
        host.scene = s
        XCTAssertTrue(host.placeOnCurrentScreen())
    }

    // MARK: Helpers

    func showMemories(cards n: Int = 6) {
        host.scene.mounted.remove(.stage)
        host.scene.marks["memories.list"] = MotionHostTests.listViewport
        host.scene.ruleCount = n
        for i in 0..<n {
            host.scene.frames[.rule(i)] = MotionHostTests.card(i)
            host.scene.mounted.insert(.rule(i))
        }
    }

    /// `before` runs ahead of each step (the app moving its surfaces), `each` after it (the
    /// app's frame: checks).
    @discardableResult
    func run(maxMs: Double, before: ((MotionHost) -> Void)? = nil, each: ((MotionHost) -> Void)? = nil,
             until: ((MotionHost) -> Bool)? = nil) -> Double {
        var t = 0.0
        let dt = 1000.0 / 240
        while t < maxMs {
            before?(host)
            host.step(dt)
            host.settle()
            t += dt
            each?(host)
            if let until, until(host) { break }
        }
        return t
    }

    /// Scrolls the list at `v` pt/s (content moving up positive) for `ms`: every card moves, and
    /// the scroll is reported as iOS 18 measures it, or (iOS 17) only by the cards' moves.
    func scroll(_ v: Double, for ms: Double, measured: Bool, until: ((MotionHost) -> Bool)? = nil) {
        let dt = 1000.0 / 240
        if measured { host.listPhaseChanged(.interacting) }
        run(maxMs: ms, before: { h in
            let d = v * dt / 1000
            for i in 0..<h.scene.ruleCount {
                if var f = h.scene.frames[.rule(i)] { f.y -= d; h.scene.frames[.rule(i)] = f }
            }
            if measured { h.listScrolled(to: h.scene.scroll.offset + d) } else { h.cardsMoved(by: -d) }
        }, until: until)
    }

    func onACard() {
        host.tabChanged(to: .memories, tapT: e.now)
        showMemories()
        run(maxMs: 1500, until: { $0.engine.anchor?.surface.isRule == true && $0.engine.now - $0.engine.lastLand > 300 })
        XCTAssertEqual(e.anchor?.surface, .rule(1))
    }

    // MARK: The Memories list

    func testRidingASlowScrollHisCardCarriesHimThenALilyPadHop() {
        onACard()
        XCTAssertNotNil(host.ridingList())
        // 200 pt/s: under lily-pad speed. His card carries him (he is drawn in it); as it nears
        // the top of the safe band he hops once to a card coming up from below.
        var hops = 0
        var lastMode = e.mode
        var rodeFor = 0.0
        scroll(200, for: 4000, measured: true) { h in
            if h.engine.mode != .attached, lastMode == .attached { hops += 1 }
            if hops == 0 { rodeFor += 1000.0 / 240 }
            lastMode = h.engine.mode
            return hops > 0 && h.engine.mode == .attached && h.engine.now - h.engine.lastLand > 200
        }
        XCTAssertEqual(hops, 1, "one lily-pad hop")
        // Card 1 starts at y 542: he rides it up until his head nears the list's top (y 59), about
        // 300 pt at 200 pt/s, not off at the first move.
        XCTAssertGreaterThan(rodeFor, 1200)
        let i = try! XCTUnwrap(e.anchor?.surface.ruleIndex)
        XCTAssertGreaterThan(i, 1, "onto a card coming up from below")
        XCTAssertEqual(host.placement, .slot(.rule(i)))
        // Soles on the card while it still moves.
        XCTAssertEqual(e.pos.y, host.scene.frames[.rule(i)]!.minY, accuracy: 0.5)
    }

    func testAFastScrollSendsHimToTheRailAndOneHopBackOnceItSettles() {
        onACard()
        scroll(1500, for: 400, measured: true)
        run(maxMs: 1000, until: { $0.engine.anchor?.surface == .rail && $0.engine.mode == .attached })
        XCTAssertEqual(e.anchor?.surface, .rail, "waits on the rail while the list is fast")
        // The finger lifts and the list stops: 200 ms slow, then one hop to a card in the band.
        host.listPhaseChanged(.idle)
        XCTAssertNotNil(host.nextDue, "the clock wakes for the settle")
        run(maxMs: 1500, until: { $0.engine.anchor?.surface.isRule == true && $0.engine.mode == .attached })
        XCTAssertTrue(e.anchor?.surface.isRule == true)
        XCTAssertFalse(host.wantsFrames)
    }

    func testOnIOS17AnyScrollIsTheRailThenBack() {
        onACard()
        // Only the cards' frames say the list moved, at a gentle 100 pt/s (Q10: no lily pads).
        scroll(100, for: 300, measured: false)
        run(maxMs: 1000, until: { $0.engine.anchor?.surface == .rail && $0.engine.mode == .attached })
        XCTAssertEqual(e.anchor?.surface, .rail)
        // Nothing moves for a while: settled, one hop back.
        run(maxMs: 1500, until: { $0.engine.anchor?.surface.isRule == true && $0.engine.mode == .attached })
        XCTAssertTrue(e.anchor?.surface.isRule == true)
    }

    func testNoRidingUnderAPageOrACover() {
        onACard()
        host.scene.pages[.memories] = MotionPage(open: true, detail: true)
        XCTAssertNil(host.ridingList())
        host.scene.pages[.memories] = MotionPage()
        host.scene.covers = 1
        XCTAssertNil(host.ridingList())
    }

    // MARK: Ask's composer

    func testAskCarriesHimUpOnItsComposerAndBackToTheStage() {
        var checks = MotionChecks()
        host.talkOpened()
        // The cover starts: he is off the stage in this frame, unseen until the composer reports.
        XCTAssertEqual(host.placement, .hidden)
        host.scene.frames[.composer] = Self.composer
        host.scene.marks["send"] = Self.send
        host.scene.mounted.insert(.composer)
        run(maxMs: 50, each: { h in checks.check(h, drawn: h.placement == .hidden ? 0 : 1) })
        XCTAssertEqual(host.placement, .slot(.composer))
        XCTAssertEqual(e.scale, 1, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(e.pos.x + 24 + 8, Self.send.minX, "his zone keeps clear of Send")
        // The keyboard comes up: the composer moves and he is drawn in it, soles on its edge.
        host.scene.keyboardUp = true
        host.scene.frames[.composer] = MotionRect(x: 0, y: 380, width: 393, height: 68)
        run(maxMs: 100, each: { h in checks.check(h, drawn: 1) })
        XCTAssertEqual(e.pos.y, 380, accuracy: 0.5)
        // Close: back on the stage under the closing cover, at Home's size.
        host.scene.mounted.remove(.composer)
        host.scene.mounted.insert(.stage)
        host.talkClosing()
        // The app checks in the same frame (the director's poke after the close button).
        checks.check(host, drawn: 1)
        run(maxMs: 50, each: { h in checks.check(h, drawn: 1) })
        XCTAssertEqual(host.placement, .slot(.stage))
        XCTAssertEqual(e.scale, 1.4, accuracy: 1e-9)
        XCTAssertEqual(checks.count, 0, "\(checks.violations)")
    }

    // MARK: The undo bar

    func testTheUndoBarLiftsHimOffTheRailAndSetsHimDownAgain() {
        // Waiting on the rail with no spot of his own on screen (otherwise he would go to it).
        host.scene.mounted.remove(.stage)
        e.carried(to: host.railSpot(.home), "test: waiting on the rail")
        XCTAssertEqual(e.anchor?.surface, .rail)
        let x = e.anchor!.x
        host.scene.frames[.panel] = Self.undoBar
        host.scene.marks["undo"] = Self.undo
        host.scene.mounted.insert(.panel)
        host.surfaceAppeared(.panel)
        run(maxMs: 20)
        XCTAssertEqual(e.anchor?.surface, .panel)
        XCTAssertEqual(host.placement, .slot(.panel))
        XCTAssertLessThanOrEqual(abs(e.anchor!.x - x), 80)
        // While it shows, it is where he waits (the strip), not the rail it stands over.
        XCTAssertEqual(host.railSpot(.memories).surface, .panel)
        host.scene.mounted.remove(.panel)
        host.surfaceGone(.panel)
        XCTAssertEqual(e.anchor?.surface, .rail)
        XCTAssertEqual(host.railSpot(.memories).surface, .rail)
    }
}
