import Foundation

// Motion v2, MV4 (docs/design/MOTION_V2_PLAN.md section 6): he rides what moves. Home's stage and
// Ask's composer carry him for free (he is drawn inside them, option B); what the engine needs to
// know is how the Memories list is scrolling, so it can make a lily-pad hop as his card leaves the
// safe band or wait on the rail while the list moves fast, and where Ask's composer and the undo
// bar are when they come and go.

/// The Memories list's scroll, as the app measures it.
public struct MotionScroll: Equatable, Sendable {
    /// iOS 18's scroll phases (`ScrollPhase`), or `.unknown` on iOS 17.
    public enum Phase: String, Sendable {
        case idle, tracking, interacting, decelerating, animating, unknown
    }

    /// Content offset (pt), from iOS 18's scroll geometry; on iOS 17 summed from the cards' moves.
    public var offset = 0.0
    /// Content moving up is positive (pt/s), as the reference's list velocity.
    public var velocity = 0.0
    public var phase: Phase = .unknown
    /// iOS 18: phases and the offset come from the scroll view itself. iOS 17 (Q10): only the
    /// cards' frames say it moved, so he waits on the rail during any scroll.
    public var measured = false
    /// When it last moved, and when it last became slower than lily-pad settle speed.
    public var lastMove = -1e9
    public var slowSince: Double? = 0

    public init() {}

    public var isMoving: Bool { abs(velocity) > 1 }
    public var isFingerDown: Bool { phase == .tracking || phase == .interacting }
}

extension MotionHost {
    /// How long without a new offset before the list counts as stopped (one 60 Hz frame and a bit).
    public static let scrollStill = 50.0

    /// iOS 18: the Memories scroll view's content offset changed.
    public func listScrolled(to offset: Double) {
        scene.scroll.measured = true
        moveScroll(by: offset - scene.scroll.offset)
        scene.scroll.offset = offset
    }

    /// iOS 18: its phase changed.
    public func listPhaseChanged(_ phase: MotionScroll.Phase) {
        scene.scroll.measured = true
        scene.scroll.phase = phase
        if phase == .idle {
            scene.scroll.velocity = 0
            markSlow()
        }
    }

    /// iOS 17 (Q10): a card's frame moved by `dy` with nothing else changed, so the list scrolled.
    /// Used only while iOS 18's measurement isn't there.
    public func cardsMoved(by dy: Double) {
        guard !scene.scroll.measured, abs(dy) > 0.25 else { return }
        moveScroll(by: -dy)
    }

    private func moveScroll(by d: Double) {
        let t = engine.now
        let dt = t - scene.scroll.lastMove
        guard abs(d) > 0.01 else { return }
        // Several reports in one frame add up; a new frame measures the speed afresh.
        if dt > 0.5, dt < 200 {
            let v = d / (dt / 1000)
            scene.scroll.velocity = 0.5 * scene.scroll.velocity + 0.5 * v
        } else if dt >= 200 {
            scene.scroll.velocity = d / (MotionMath.clamp(dt, 8, 16.7) / 1000)
        }
        scene.scroll.lastMove = t
        if abs(scene.scroll.velocity) >= MotionTiming.lilySettleSpeed {
            scene.scroll.slowSince = nil
        } else {
            markSlow()
        }
    }

    private func markSlow() {
        if scene.scroll.slowSince == nil { scene.scroll.slowSince = engine.now }
    }

    /// Each frame: a list that hasn't reported a move for a frame has stopped.
    func settleScroll() {
        guard scene.scroll.isMoving, engine.now - scene.scroll.lastMove > Self.scrollStill else { return }
        let decelerating = scene.scroll.measured && scene.scroll.phase == .decelerating
        if !decelerating {
            scene.scroll.velocity = 0
            markSlow()
        }
    }

    /// The list he can ride now: Memories' own list, nothing over it, with cards on screen.
    var canRideList: Bool {
        isActive && scene.covers == 0 && pendingTab == nil && scene.screen == .memories && !scene.page.open
            && scene.ruleCount > 0 && scene.marks["memories.list"] != nil
    }

    /// The list's speed as the engine should see it. iOS 17 has no measured speed (Q10): any move
    /// counts as fast, so he waits on the rail and comes back once it has settled.
    var ridingVelocity: Double {
        let v = scene.scroll.velocity
        guard !scene.scroll.measured else { return v }
        guard scene.scroll.isMoving else { return 0 }
        return (v < 0 ? -1 : 1) * max(abs(v), MotionTiming.lilySlow + 1)
    }

    /// Whether the clock should keep running for the list: it is moving, or he is waiting on the
    /// rail for it to settle.
    public var wantsFrames: Bool {
        if scene.finger.isDown { return true }
        guard canRideList else { return false }
        return scene.scroll.isMoving || engine.scrollWait
    }

    /// The next moment the host needs a frame although he is still: the settle after a scroll,
    /// thinking 600 ms after a question, the session's playful moment after 8 s of idle.
    public var nextDue: Double? {
        var due: [Double] = []
        if canRideList, engine.scrollWait, let slow = scene.scroll.slowSince { due.append(slow + MotionTiming.lilySettleFor + 1) }
        if let sent = askSentAt, !engine.isThinking { due.append(sent + MotionHost.thinkingAfter + 1) }
        if let t = playfulDue { due.append(t) }
        if engine.followFinger, !scene.finger.isDown { due.append(elsewhereAt + MotionHost.fingerStaleAfter + 1) }
        return due.min()
    }

    // MARK: Ask's composer (Q2)

    /// Ask opened: its cover starts up from the bottom, and he comes up inside it, on its composer.
    /// He leaves Home's stage in this frame and is drawn in the composer once it has reported
    /// where it is: one Doddy all the way, carried, not hopping into a cover.
    public func talkOpened() {
        guard scene.screen != .talk else { return }
        returnScreen = scene.screen
        scene.screen = .talk
        pendingTab = nil
        talkPending = true
        relocatedFrom = nil
    }

    /// Ask is closing: its cover goes down over him; he is back on Home's stage under it,
    /// revealed where he stood.
    public func talkClosing() {
        guard scene.screen == .talk else { return }
        scene.screen = returnScreen
        talkPending = false
        relocatedFrom = nil
        guard isPlaced else { return }
        if let spot = preferredSpot(for: engine), scene.frames[spot.surface] != nil {
            engine.carried(to: spot, "Ask closed: back where he stood, under its cover")
        } else {
            pendingTab = (scene.screen, engine.now)
        }
    }

    func carryIntoTalkIfReady() {
        guard talkPending, scene.screen == .talk, let f = mountedFrame(.composer) else { return }
        talkPending = false
        let spot = MotionSpot(.composer, x: MotionLayout.composerSpotX(composer: f, send: scene.marks["send"]))
        if isPlaced {
            engine.carried(to: spot, "Ask opened: he comes up on its composer")
        } else {
            _ = placeOnCurrentScreen()
        }
    }

    // MARK: The undo bar ("the strip", Q3)

    /// The undo bar appeared or went, in one frame (it has no animation). Standing on the rail
    /// under it, he is lifted with it; standing on it as it goes, he is set down on the rail.
    public func panelChanged(shown: Bool) {
        guard isPlaced, engine.mode == .attached, let a = engine.anchor else { return }
        if shown, a.surface == .rail, let bar = scene.frames[.panel] {
            let range = MotionLayout.barStandRange(bar: bar, action: scene.marks["undo"])
            let x = MotionMath.clamp(a.x, range.lowerBound, range.upperBound)
            engine.carried(to: MotionSpot(.panel, x: x), "the undo bar appeared under him: he rides it up")
        } else if !shown, a.surface == .panel, let rail = scene.frames[.rail] {
            let range = MotionLayout.railStandRange(bar: rail)
            let x = MotionMath.clamp(a.x, range.lowerBound, range.upperBound)
            engine.carried(to: MotionSpot(.rail, x: x), "the undo bar went: he rides it down to the rail")
        }
    }
}
