import Foundation

// Motion v2, MV5 (docs/design/MOTION_V2_PLAN.md section 6): the living parts that the owner's
// pack can draw and the app's real state can drive. Touch on him on Home (the dip, a tap or a
// hold opens the voice screen, the drag-lean and the flick), three breaths, sitting cross-legged
// after 15 s idle, the listening pose only while a conversation's microphone is really live,
// thinking in Ask while the reply hasn't come, the wave or the stretch as the session's one
// playful moment, and the daily welcome (a hop in place first after three days away). Everything
// the pack can't draw (head roll, brace, shuffle, and gaze or blink on the three-quarter pictures)
// stays off and is listed in docs/design/MOTION_V2_ART_REQUESTS.md. Gaze and blink (MV7, ADR-547)
// are drawn on the pictures with a front-facing head.

/// The daily welcome (brief rule 9, Q15): once a day, on Home. After three days or more away it
/// starts with one hop in place. The welcome itself is the wave (Q15: the default and evening
/// welcomes are eyes and a head roll, which the pack can't draw yet).
public enum MotionWelcome {
    public static let backAfterDays = 3.0

    /// Today's welcome and the day to record for it, or nil if he has welcomed you today.
    /// `lastWelcomeDay` uses the morning wave's day key (ADR-380), so the two never both play.
    public static func decide(now: Date, lastWelcomeDay: String?, lastVisit: Date?,
                              calendar: Calendar = .current) -> (kind: WelcomeKind, day: String)? {
        let day = MorningWave.dayKey(now, calendar: calendar)
        guard day != lastWelcomeDay else { return nil }
        if let lastVisit, now.timeIntervalSince(lastVisit) >= backAfterDays * 86_400 { return (.back, day) }
        return (.standard, day)
    }
}

extension MotionHost {
    /// The first breaths start this long after he first appears (as after a landing).
    public static let firstBreathAfter = 2000.0
    /// Thinking starts when the reply hasn't come after this long (the brief's 600 ms).
    public static let thinkingAfter = 600.0

    // MARK: Touch on him (Home)

    /// A finger came down on him on Home's stage (the app's touch area covers his clear zone).
    public func touchDown(x: Double, y: Double) {
        guard isActive, scene.covers == 0, scene.screen == .home else { return }
        touchStart = MotionPoint(x: x, y: y)
        scene.finger = MotionFinger(isDown: true, x: x, y: y)
        scene.lastInput = engine.now
        engine.homeTouchDown(x: x, y: y)
    }

    /// The finger moved (window points, and its speed in pt/s).
    public func touchMoved(x: Double, y: Double, vx: Double, vy: Double) {
        guard scene.finger.isDown, let start = touchStart else { return }
        let moved = scene.finger.moved || MotionMath.hyp(x - start.x, y - start.y) > MotionTiming.tapSlop
        scene.finger = MotionFinger(isDown: true, x: x, y: y, vx: vx, vy: vy, moved: moved)
        scene.lastInput = engine.now
        engine.homeTouchMove(x: x, y: y)
    }

    /// The finger lifted: a tap (or a hold, which can only open the voice screen here, plan
    /// section 5) opens Talk; a drag springs back; a fast upward flick is a hop in place.
    public func touchUp(vx: Double, vy: Double) {
        guard scene.finger.isDown else { return }
        scene.finger.vx = vx
        scene.finger.vy = vy
        engine.homeTouchUp()
        scene.finger = MotionFinger(isDown: false, x: scene.finger.x, y: scene.finger.y)
        scene.lastTap = engine.now
        touchStart = nil
    }

    // MARK: Ask: thinking while the reply hasn't come

    /// Ask sent a question (`sending` true) or its reply (or failure) came.
    public func askSending(_ sending: Bool, failed: Bool) {
        if sending {
            askSentAt = engine.now
        } else if askSentAt != nil {
            askSentAt = nil
            engine.endThinking(failed: failed)
        }
    }

    // MARK: Voice: the listening pose, only while the microphone is really live

    /// A conversation's capture is live on screen (the session's real `.listening` phase).
    public func voiceListening(_ live: Bool) {
        scene.voiceLive = live
    }

    // MARK: The day

    /// The app came to the front: if today's welcome hasn't happened, it is due again (and the
    /// session's playful moment with it).
    public func newDay(welcome kind: WelcomeKind) {
        welcomeToday = kind
        engine.resetBudgets()
        engine.settings.autoWelcome = true
        engine.settings.welcomeKind = kind
    }

    // MARK: Each frame

    func settleBehaviours() {
        guard behaviours, isActive else { return }
        if scene.finger.isDown { engine.checkHold() }
        if let sent = askSentAt, scene.screen == .talk {
            engine.waitingForReply(sentAt: sent, thinkingAt: sent + Self.thinkingAfter, replyAt: .greatestFiniteMagnitude)
        }
        // The session's one playful moment (the engine keeps the budget and every rule: Home,
        // 8 s idle, no welcome this visit, not within 2 s of a tap, never with Reduce Motion).
        if scene.covers == 0, scene.screen == .home, engine.playfulRefusal(home: true) == nil {
            engine.playful(engine.pose.sit > 0.5 ? .stretch : .wave)
        }
    }

    /// When the playful moment could next happen (to wake the clock for it), nil if it can't.
    var playfulDue: Double? {
        guard behaviours, isActive, scene.screen == .home, engine.playfulUsed == 0, !engine.visit.hadWelcome,
              !engine.settings.reduceMotion, engine.anchor?.surface == .stage else { return nil }
        return max(engine.idleSince, scene.lastInput, scene.lastTap + 2000 - 8000) + 8000 + 1
    }
}
