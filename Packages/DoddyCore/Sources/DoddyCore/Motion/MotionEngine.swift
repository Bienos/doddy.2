import Foundation

// Motion v2 (docs/design/MOTION_V2_PLAN.md, MV1): the one persistent Doddy's behaviour engine, a
// port of the owner's reference engine (`design/motion-v2/reference/engine.js`, the character
// half; the prototype's mock screen stays in the tests). Time-based: the host advances it in
// milliseconds and reads his state; 60 Hz and 120 Hz give the same path.
//
// What it decides: where he stands, every hop (crouch, flight, contact, settle), mid-air
// re-targets, Reduce Motion fades with one invisible frame, calm mode during rapid switching,
// shuffles along a surface, riding a moving surface and stepping off it, scroll riding with
// lily-pad hops and the rail wait, brace, ducking, and his idle life (breaths, sitting, the
// daily welcome, glances, the playful moment). What it doesn't: drawing. The host turns
// `pose` into whole-picture transforms of the owner's pack art (Q7: move, scale, rotate and
// squash a whole picture; never redraw, recolour, cut up or generate).
//
// Gaze is kept as data (what he looks at and why) because the reference uses it to sequence
// reactions. Until MV7 the pack had no art that moves his eyes on their own (plan section 3), so
// the app didn't draw it; `MotionFace` now draws it on the pictures that have a front-facing
// head, from the pieces cut from the owner's sheets 007 and 008 (ADR-558).

public struct MotionSettings: Sendable {
    public var reduceMotion = false
    /// Low Power Mode: no breaths, no glances.
    public var lowPower = false
    /// His size on Home's stage (rule 13).
    public var homeScale = 1.4
    /// Brace on above this mean support acceleration (pt/s² over 100 ms), off below `braceOff`
    /// for 120 ms (DECISIONS.md "Brace threshold").
    public var braceOn = 24_000.0
    public var braceOff = 8_000.0
    /// Press and hold on him starts voice.
    public var voiceFromHome = true
    /// The daily welcome plays by itself when Home is idle.
    public var autoWelcome = true
    public var welcomeKind: WelcomeKind = .standard
    public var noBreath = false

    public init() {}
}

public enum WelcomeKind: String, Sendable {
    /// Eyes to you, 5° head roll.
    case standard = "default"
    /// After 21:00: a slow blink and a 3° roll.
    case evening
    /// After 3+ days away: one hop in place, pleased, then the default welcome.
    case back
}

/// What his eyes are on.
public struct MotionGaze: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case user, dir, point, anchor, finger
    }

    public var kind: Kind
    public var label: String
    public var point: MotionPoint?
    public var anchor: MotionSpot?
}

/// Everything the drawing needs, in rig units (points at 1.0×). The app maps only what pack
/// pictures can carry: position, scale, opacity, crouch (squash), lean, roll and the pose
/// choice; arms, gaze and feet are kept for the debug overlay and for future art.
public struct MotionPose: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var scale: Double
    public var opacity: Double
    public var crouch: Double
    public var sit: Double
    public var edge: Double
    public var tuck: Double
    public var squash: Double
    public var stretchUp: Double
    public var lean: Double
    public var roll: Double
    public var facing: Double
    public var toe: Double
    public var breath: Double
    public var mood: String
    public var activity: String
    public var listening: Bool
    public var bracing: Bool
}

public final class MotionEngine {
    public enum Mode: String, Sendable {
        case attached, anticipate, flight, fade, shuffle
    }

    public struct Event: Equatable, Sendable {
        public var t: Double
        public var message: String
    }

    public struct Metrics: Sendable {
        public var hops: [HopPlan] = []
        public var braces: [Brace] = []
        public var ridePeaks: [RidePeak] = []
        public var playful: [PlayfulMoment] = []
        public var listenFrames = 0.0
        public var events: [Event] = []
    }

    public struct Brace: Equatable, Sendable {
        public var t: Double
        public var acc: Double
    }

    /// The largest support acceleration during one ride (logged when it exceeded 1,000 pt/s²).
    public struct RidePeak: Equatable, Sendable {
        public var t: Double
        public var surface: String
        public var peak: Double
    }

    public struct PlayfulMoment: Equatable, Sendable {
        public var t: Double
        public var kind: String
        public var duringTask: Bool
    }

    struct Gesture {
        enum Kind: String {
            case introduce, wave, stretch, trace, welcome, welcomeEvening, look, edgeSit
        }

        var kind: Kind
        var t = 0.0
        var fromSit = false
        var up = false
        var down = false
        var blinked = false
    }

    struct Micro {
        var kind: String
        var t: Double
        var dur: Double
    }

    struct Reaction {
        var kind: String
        var until: Double
    }

    struct Shuffle {
        var x0, x1, dlt, dir, t: Double
        var single: Bool
        var fL, fR: Double
        var leadIsRight: Bool
        var settling = false
    }

    struct HomeTouch {
        enum Kind { case stroke, drag, voice, holdTap }
        var t0, x0, y0: Double
        var kind: Kind?
        var onHead: Bool
        var holdFired = false
        var lastX: Double
    }

    struct Visit {
        var start: Double
        var hadWelcome = false
        var glances = 0
        var lookAround = false
        var nextGlanceAt: Double
        var arrivalGlance = false
    }

    // MARK: Host and clock

    private weak var host: (any MotionWorld)?
    private var world: any MotionWorld { host! }
    public private(set) var now = 0.0
    private var timers: [(at: Double, fn: () -> Void)] = []
    private var rand = MotionRandom(seed: 7)
    public var settings = MotionSettings()
    public private(set) var metrics = Metrics()
    /// Called with every log line (the debug overlay's third line).
    public var onNote: ((Event) -> Void)?

    // MARK: Character state (the reference's `D`)

    public private(set) var mode: Mode = .attached
    public private(set) var anchor: MotionSpot?
    public private(set) var target: MotionSpot?
    public private(set) var pos = MotionPoint(x: 0, y: 0)
    public private(set) var vel = MotionPoint.zero
    public private(set) var scale = 1.0
    public private(set) var flight: MotionFlight?
    public private(set) var phaseT = 0.0
    var airborne = 0.0
    var airStart = 0.0
    var antDur = 80.0
    var retargets = 0
    var noInherit = false
    var recheckOnLand = false
    var surfaceVel = MotionPoint.zero
    public private(set) var opacity = 1.0
    var fadeMoved = false
    var fadeKind = "hop"
    var fadeOutMs = MotionTiming.fadeOut
    var fadeInMs = MotionTiming.fadeIn
    public private(set) var lastLand = -99_999.0
    var idleSince = 0.0
    // Springs (rig units). The reference's values, response / damping.
    let crouch = MotionSpring(0, response: 0.30, damping: 0.60)
    let duck = MotionSpring(0, response: 0.14, damping: 1.0)
    let dipSpring = MotionSpring(0, response: 0.06, damping: 1.0)
    let dragC = MotionSpring(0, response: 0.12, damping: 1.0)
    let sit = MotionSpring(0, response: 0.45, damping: 0.92)
    let edge = MotionSpring(0, response: 0.40, damping: 0.95)
    let lean = MotionSpring(0, response: 0.20, damping: 0.85)
    let roll = MotionSpring(0, response: 0.24, damping: 0.80)
    let facing = MotionSpring(0, response: 0.20, damping: 0.90)
    let gx = MotionSpring(0, response: 0.15, damping: 0.85)
    let gy = MotionSpring(0, response: 0.15, damping: 0.85)
    let armL1 = MotionSpring(30, response: 0.35, damping: 0.75)
    let armL2 = MotionSpring(20, response: 0.35, damping: 0.75)
    let armR1 = MotionSpring(30, response: 0.35, damping: 0.75)
    let armR2 = MotionSpring(20, response: 0.35, damping: 0.75)
    let tuck = MotionSpring(0, response: 0.12, damping: 0.9)
    let squash = MotionSpring(0, response: 0.10, damping: 0.8)
    let stretchUp = MotionSpring(0, response: 0.12, damping: 1.0)
    let xOff = MotionSpring(0, response: 0.28, damping: 0.70)
    let toe = MotionSpring(0, response: 0.42, damping: 1.0)
    let squint = MotionSpring(0, response: 0.05, damping: 1.0)
    let shut = MotionSpring(0, response: 0.06, damping: 1.0)
    var swing = 0.0
    var blink = 0.0
    var blinkT = -1.0
    var blinkDur = 210.0
    public private(set) var gaze = MotionGaze(kind: .user, label: "you")
    var reaction: Reaction?
    var userGazeAt = 0.0
    public private(set) var activity = "resting"
    public private(set) var mood = "calm"
    var moodUntil = 0.0
    var pendingTransfer: MotionSpot?
    var pendingPickup = false
    var pendingStepOff: (target: MotionSpot, reason: MotionReason?)?
    /// Covered in place by a page pushed over his spot.
    public internal(set) var hiddenBehind = false
    /// The spot he last stood on per screen.
    public internal(set) var memory: [String: MotionSpot] = [:]
    var welcomeBudget = 1
    var playfulUsed = 0
    var breathT = -1.0
    var breath = 0.0
    var gesture: Gesture?
    var micro: Micro?
    var typingArmed = true
    var lastTyping = -99_999.0
    var lastSendReact = -99_999.0
    public private(set) var calm = false
    var changes: [Double] = []
    var lastChange = -99_999.0
    /// Drawing order: just above the surface he is on, or above both ends of a flight.
    public private(set) var z = 1.2
    var curHop: HopPlan?
    var shuf: Shuffle?
    var visit = Visit(start: 0, nextGlanceAt: 25_000)
    var satThisIdle = false
    var edgeThisIdle = false
    var thinking: (t0: Double, blinked: Bool)?
    public private(set) var listenOn = false
    var ducking = false
    var brace = (on: false, done: false, peak: 0.0, lowSince: 0.0)
    var supAcc = 0.0
    var accHist: [(t: Double, vx: Double, vy: Double)] = []
    var homeTouch: HomeTouch?
    var rub = (active: false, starts: [Double](), lastEnd: -99_999.0, lastStart: -99_999.0, smileOnly: false)
    var lastFlick = -99_999.0
    var scrollWait = false
    var lastLily = -99_999.0
    var welcomeAfterHop = false
    var justLanded = false
    var followFinger = false
    var bannerConcern = false
    var dips: [MotionSurfaceID: MotionSpring] = [:]

    public init(settings: MotionSettings = MotionSettings()) {
        self.settings = settings
        scale = settings.homeScale
    }

    public func attach(to world: any MotionWorld) {
        host = world
    }

    // MARK: Clock and log

    /// Runs `fn` `ms` from now, at the start of the first step at or after that time.
    public func after(_ ms: Double, _ fn: @escaping () -> Void) {
        timers.append((now + ms, fn))
    }

    /// Advances the clock and fires due timers, newest first (the reference's order).
    public func beginStep(_ dtMs: Double) {
        now += dtMs
        var i = timers.count - 1
        while i >= 0 {
            if i < timers.count, timers[i].at <= now {
                let tm = timers.remove(at: i)
                tm.fn()
            }
            i -= 1
        }
    }

    public func note(_ message: String) {
        let e = Event(t: now.rounded(), message: message)
        metrics.events.append(e)
        onNote?(e)
    }

    // MARK: Surfaces

    func S(_ id: MotionSurfaceID) -> any MotionSurface { world.surface(id) }

    /// The surface's dip spring: it gives a little under his landing.
    public func dip(_ id: MotionSurfaceID) -> MotionSpring {
        if let s = dips[id] { return s }
        let s = MotionSpring(0, response: 0.22, damping: 0.5)
        dips[id] = s
        return s
    }

    /// The host steps the dips with its own surfaces (before the character).
    public func stepSurfaceDips(_ dt: Double) {
        for (_, s) in dips {
            s.target = 0
            s.step(dt)
        }
    }

    public func surfaceDip(_ id: MotionSurfaceID) -> Double { dips[id]?.x ?? 0 }

    public func anchorPoint(_ a: MotionSpot) -> MotionPoint {
        let s = S(a.surface)
        return MotionPoint(x: a.x + s.dx(), y: s.top() + dip(a.surface).x)
    }

    func pointAt(_ a: MotionSpot, _ dt: Double) -> MotionPoint {
        S(a.surface).pointAhead(x: a.x, dt: dt) ?? anchorPoint(a)
    }

    func predictedPoint(_ a: MotionSpot) -> MotionPoint {
        S(a.surface).predictedPoint(x: a.x) ?? anchorPoint(a)
    }

    func supportMovingNow() -> Bool {
        guard let a = anchor else { return false }
        return S(a.surface).isMoving()
    }

    func supportSettleY() -> Double? {
        guard let a = anchor else { return nil }
        return S(a.surface).settleY()
    }

    func scaleFor(_ a: MotionSpot) -> Double { S(a.surface).scale }

    // MARK: Gaze and reactions

    func gazeAt(_ kind: MotionGaze.Kind, _ label: String? = nil, point: MotionPoint? = nil, anchor spot: MotionSpot? = nil) {
        gaze = MotionGaze(kind: kind, label: label ?? kind.rawValue, point: point, anchor: spot)
    }

    func headPos() -> MotionPoint {
        MotionPoint(x: pos.x + xOff.x, y: pos.y - 77.5 * scale)
    }

    func gazeVector() -> MotionPoint {
        switch gaze.kind {
        case .user: return .zero
        case .dir: return gaze.point ?? .zero
        default:
            let head = headPos()
            var t = gaze.point ?? .zero
            if gaze.kind == .anchor, let a = gaze.anchor { t = anchorPoint(a) }
            if gaze.kind == .finger { t = MotionPoint(x: world.finger.x, y: world.finger.y) }
            let dx = t.x - head.x, dy = t.y - head.y, d = max(1, MotionMath.hyp(dx, dy))
            return MotionPoint(x: dx / d, y: dy / d)
        }
    }

    public func setMood(_ m: String, _ ms: Double = 0) {
        mood = m
        moodUntil = ms != 0 ? now + ms : 0
    }

    public func attendContent() {
        if let f = world.focusPoint() { gazeAt(.point, f.label, point: f.point) } else { gazeAt(.user) }
        userGazeAt = now + 1200
    }

    /// One gaze-only reaction at a time; the latest event wins; each lasts at most 600 ms.
    public func notice(_ kind: String, _ pt: MotionPoint, _ dur: Double, mood m: String? = nil, moodMs: Double = 0) {
        if mode == .flight || mode == .anticipate { return }
        if let g = gesture, g.kind != .welcome { return }
        reaction = Reaction(kind: kind, until: now + min(600, dur))
        gazeAt(.point, kind, point: pt)
        if let m { setMood(m, moodMs) }
        note("notices: \(kind) (eyes, \(MotionMath.format(min(600, dur))) ms)")
    }

    public func clearReaction() { reaction = nil }

    public func look(at pt: MotionPoint, _ label: String) { gazeAt(.point, label, point: pt) }

    public func lookAtUser() { gazeAt(.user) }

    // MARK: Hops

    func stopIdlePoses() {
        breathT = -1
        gesture = nil
        micro = nil
        resetArms()
        edge.target = 0
        sit.target = 0
    }

    func gazeAtTab(_ tab: String) {
        gazeAt(.point, "\(tab) tab", point: world.gazePoint(.tab(tab)))
    }

    public func startHop(_ target: MotionSpot, _ reason: MotionReason?, immediate: Bool = false) {
        if settings.reduceMotion { return startFade(target, reason) }
        if mode == .shuffle { endShuffle(false) }
        let fromSit = sit.x > 0.3 || edge.x > 0.3
        let fromLanding = now - lastLand < 340
        let goY = predictedPoint(target).y - pos.y
        var away = 0.0, toward = false
        if let a = anchor, mode == .attached {
            var ys: [Double] = []
            for k in 1...10 { ys.append(pointAt(a, Double(k) * 0.016).y) }
            if let settle = supportSettleY() { ys.append(settle) }
            for y in ys {
                let dy = y - pos.y
                if abs(dy) > 0.5 {
                    if MotionMath.sign(dy) != MotionMath.sign(goY) { away = max(away, abs(dy)) } else { toward = true }
                }
            }
        }
        let leaving = away > 4
        noInherit = leaving && !(MotionMath.sign(vel.y) == MotionMath.sign(goY) && abs(vel.y) > 30)
        antDur = HopPlan.anticipation(immediate: immediate, leaving: leaving, fromSit: fromSit, fromLanding: fromLanding, surfaceMovesHisWay: toward)
        if leaving { note("his surface is about to move away, so he steps off at once (0 ms crouch)") }
        curHop = HopPlan(
            requestedAt: now, tapAt: reason?.tapT ?? now, why: reason?.why ?? "navigation",
            from: anchor.map { $0.surface.description } ?? "?", to: target.surface.description,
            anticipation: antDur, startScale: scale, endScale: scaleFor(target), isTabHop: reason?.tab != nil)
        mode = .anticipate
        phaseT = 0
        self.target = target
        retargets = 0
        activity = "anticipating"
        stopIdlePoses()
        let p1 = predictedPoint(target)
        let dir = MotionMath.sign(p1.x - pos.x)
        // Eyes at 0 ms; head and body follow one frame later.
        if let tab = reason?.tab { gazeAtTab(tab) } else { gazeAt(.anchor, "landing spot", anchor: target) }
        let depth = 5.0 // rig units: 5 pt at 1.0×, 7 pt at 1.4×
        let body = { [self] in
            guard mode == .anticipate else { return }
            crouch.set(fromSit ? 0.16 : 0.12, 1.0)
            crouch.target = depth
            sit.set(0.16, 1.0)
            edge.set(0.16, 1.0)
            lean.set(0.20, 0.85)
            lean.target = -3 * dir
            facing.target = 0.8 * dir
            roll.target = 0
        }
        if antDur > 0 { after(16, body) } else { body() }
        note("hop requested → \(target.surface) (\(curHop!.why))")
        if antDur == 0 {
            surfaceVel = vel
            takeOff()
        }
    }

    func takeOff() {
        guard let target else { return }
        let cap = curHop.map { HopPlan.flightCap(isTabHop: $0.isTabHop, tapAt: $0.tapAt, now: now) } ?? 420
        curHop?.cappedFrom = nil
        let timeFor = { [self] (d: Double, dy: Double) -> Double in
            let T0 = MotionTiming.flight(d, dy)
            if T0 > cap, curHop != nil { curHop!.cappedFrom = T0.rounded() }
            return min(T0, cap)
        }
        let p0 = MotionPoint(x: pos.x + xOff.x, y: pos.y)
        let aim = HopPlan.aim(from: p0, predicted: predictedPoint(target), timeFor: timeFor, pointAt: { pointAt(target, $0) })
        let p1 = aim.end
        xOff.snap(0)
        let dx = p1.x - p0.x, dy = p1.y - p0.y, Dd = MotionMath.hyp(dx, dy)
        let T = aim.time, A = MotionTiming.apex(Dd, dy), h = MotionFlight.lift(from: p0, to: p1, apex: A)
        let vS0 = noInherit ? MotionPoint.zero : surfaceVel
        let vS = MotionPoint(x: vS0.x * 0.5, y: vS0.y * 0.5)
        flight = MotionFlight(
            p0: p0, p1: p1, t0: now,
            m0: MotionPoint(x: dx + vS.x * T / 1000, y: dy + vS.y * T / 1000), m1: MotionPoint(x: dx, y: dy),
            h: h, T: T, s0: scale, s1: scaleFor(target), kind: .hop)
        mode = .flight
        phaseT = 0
        airborne = 0
        airStart = now
        activity = "flying"
        z = max(anchor.map { S($0.surface).layer } ?? 1, S(target.surface).layer) + 0.2
        crouch.set(0.10, 0.9)
        crouch.target = 0
        squash.x = 1
        squash.target = 0
        sit.snap(0)
        edge.snap(0)
        toe.snap(0)
        lean.target = 6 * MotionMath.sign(dx)
        // Arms rise during the first 40 % of the flight; legs tuck toward the apex.
        let armR = MotionMath.clamp(T / 1000 * 0.9, 0.12, 0.34)
        for s in [armL1, armL2, armR1, armR2] { s.set(armR, 0.9) }
        armL1.target = 105
        armL2.target = 135
        armR1.target = 105
        armR2.target = 135
        tuck.set(MotionMath.clamp(T / 1000, 0.18, 0.4), 0.9)
        tuck.target = 0.85
        gazeAt(.anchor, "landing spot", anchor: target)
        if curHop != nil {
            curHop!.takeoffAt = now
            curHop!.crouch = now - curHop!.requestedAt
            curHop!.flightTime = T
            curHop!.distance = Dd
            curHop!.apex = A
            curHop!.start = p0
            curHop!.end = p1
        }
        anchor = nil
    }

    public func retarget(_ target: MotionSpot, _ reason: MotionReason?, force: Bool = false) {
        if settings.reduceMotion { return startFade(target, reason) }
        if mode == .anticipate {
            if let a = anchor, target.isSame(as: a) {
                mode = .attached
                self.target = nil
                activity = "resting"
                crouch.set(0.30, 0.60)
                crouch.target = 0
                lean.target = 0
                facing.target = 0
                gazeAt(.user)
                if curHop != nil {
                    curHop!.cancelledAt = now
                    metrics.hops.append(curHop!)
                    curHop = nil
                }
                note("reversed during the crouch, so the hop is cancelled and he never leaves the ground")
                return
            }
            self.target = target
            let dir = MotionMath.sign(anchorPoint(target).x - pos.x)
            lean.target = -3 * dir
            facing.target = 0.8 * dir
            if curHop != nil {
                curHop!.to = target.surface.description
                curHop!.endScale = scaleFor(target)
                curHop!.reaimedInCrouch = true
            }
            if let tab = reason?.tab { gazeAtTab(tab) }
            note("re-aimed during the crouch → \(target.surface)")
            return
        }
        if mode == .flight {
            let left = MotionTiming.maxAirborne - airborne
            if !force, left < 160, let t = self.target, S(t.surface).isVisible() {
                recheckOnLand = true
                note("less than 160 ms of air left, so he lands first and hops on")
                return
            }
            let timeFor = { (d: Double, _: Double) -> Double in
                max(min(MotionTiming.retargetFlight(d), max(160, left)), d / 1.2)
            }
            let p = pos, v = vel
            let aim = HopPlan.aim(from: p, predicted: predictedPoint(target), timeFor: timeFor, pointAt: { pointAt(target, $0) })
            let p1 = aim.end
            let dx = p1.x - p.x, dy = p1.y - p.y
            let T = aim.time
            let h = min(MotionFlight.lift(from: p, to: p1, apex: 8), 40)
            flight = MotionFlight(
                p0: p, p1: p1, t0: now,
                m0: MotionPoint(x: v.x * T / 1000, y: v.y * T / 1000 + 4 * h), m1: MotionPoint(x: dx, y: dy),
                h: h, T: T, s0: scale, s1: scaleFor(target), kind: .retarget)
            self.target = target
            phaseT = 0
            retargets += 1
            z = max(z, S(target.surface).layer + 0.2)
            lean.target = 6 * MotionMath.sign(dx)
            facing.target = 0.8 * MotionMath.sign(dx)
            gazeAt(.anchor, "new landing spot", anchor: target)
            if curHop != nil {
                curHop!.to = target.surface.description
                curHop!.endScale = scaleFor(target)
                curHop!.retargets = retargets
                curHop!.retargetAt = now
                curHop!.retargetFlightTime = T
            }
            note("re-targeted mid-air → \(target.surface) (keeps \(MotionMath.format(MotionMath.hyp(v.x, v.y))) pt/s, new flight \(MotionMath.format(T)) ms)")
        }
    }

    func land() {
        guard let f = flight, let target else { return }
        let v = f.velocity(1)
        mode = .attached
        anchor = target
        self.target = nil
        flight = nil
        lastLand = now
        activity = "landing"
        resetSupportVel(target)
        scale = f.s1
        z = S(target.surface).layer + 0.2
        pos = anchorPoint(target)
        let impact = MotionMath.clamp(max(0, v.y) / 1800, 0, 1)
        let sq = HopPlan.contactSquash(vy: v.y)
        crouch.set(0.30, 0.60)
        crouch.v += sq * 41.9
        crouch.target = 0
        satThisIdle = false
        edgeThisIdle = false
        tuck.target = 0
        tuck.x = 0
        squash.target = 0
        let peak = MotionMath.clamp(abs(v.x) / 50, 0, 4) * MotionMath.sign(v.x) * scale
        xOff.set(0.28, 0.70)
        xOff.x = 0
        xOff.v = peak * (2 * Double.pi / 0.28) * 2.18
        lean.target = 0
        resetArms()
        dip(target.surface).v += 38 + 38 * impact
        after(200) { [self] in if mode == .attached { facing.target = 0 } }
        after(150) { [self] in if mode == .attached, gesture == nil, micro == nil, thinking == nil { attendContent() } }
        memory[world.screenKey] = target
        breathT = now + 2000
        idleSince = now
        if f.kind == .flick {
            setMood("pleased", 700)
            note("flick hop lands on the same spot, pleased")
        }
        if curHop != nil {
            curHop!.contactAt = now
            curHop!.contactAfterTap = now - curHop!.tapAt
            curHop!.impact = v.y.rounded()
            curHop!.squash = ((sq * scale) * 100).rounded() / 100
            curHop!.landScale = scale
            metrics.hops.append(curHop!)
            curHop = nil
        }
        if target.surface == .stage { startVisit() }
        if target.surface.isRule { scrollWait = false }
        if recheckOnLand {
            recheckOnLand = false
            after(0) { [self] in updateDestination(MotionReason("landed; on to the newest destination")) }
        }
        note("contact on \(target.surface) at \(MotionMath.format(MotionMath.hyp(v.x, v.y))) pt/s; squash \(MotionMath.format(sq * scale, digits: 1)) pt, settle")
    }

    /// After he changes support, his velocity is that support's velocity (no false acceleration spike).
    func resetSupportVel(_ a: MotionSpot) {
        let pA = pointAt(a, 0), pB = pointAt(a, 0.008)
        vel = MotionPoint(x: (pB.x - pA.x) / 0.008, y: (pB.y - pA.y) / 0.008)
        accHist = []
        justLanded = true
    }

    /// Reduce Motion (and shuffles under it): fade out, move unseen, fade in.
    public func startFade(_ target: MotionSpot, _ reason: MotionReason?, kind: String = "hop") {
        if let tab = reason?.tab { gazeAtTab(tab) } else { gazeAt(.anchor, "destination", anchor: target) }
        let out = kind == "shuffle" ? MotionTiming.shuffleOut : MotionTiming.fadeOut
        if mode == .fade {
            if phaseT >= fadeOutMs, !target.isSame(as: anchor) {
                phaseT = (1 - opacity) * fadeOutMs
                fadeMoved = false
            }
            self.target = target
            note("fade re-aimed → \(target.surface)")
            return
        }
        if mode == .shuffle { endShuffle(false) }
        stopIdlePoses()
        mode = .fade
        self.target = target
        phaseT = 0
        activity = "fading"
        fadeKind = kind
        fadeOutMs = out
        fadeInMs = kind == "shuffle" ? MotionTiming.shuffleIn : MotionTiming.fadeIn
        curHop = nil
        note("Reduce Motion: fade to \(target.surface) (\(MotionMath.format(out)) ms out, \(MotionMath.format(fadeInMs)) ms in)")
    }

    func resetArms(_ r: Double = 0.35) {
        armL1.target = 30
        armL2.target = 20
        armR1.target = 30
        armR2.target = 20
        for s in [armL1, armL2, armR1, armR2] { s.set(r, 0.75) }
    }

    // MARK: Shuffle (same surface, up to 40 pt)

    func startShuffle(_ x1: Double, _ why: String) {
        guard let a = anchor else { return }
        let x0 = a.x, dlt = x1 - x0
        if abs(dlt) < 0.5 {
            anchor!.x = x1
            return
        }
        if settings.reduceMotion { return startFade(MotionSpot(a.surface, x: x1), MotionReason(why), kind: "shuffle") }
        if abs(dlt) > 40 { return startHop(MotionSpot(a.surface, x: x1), MotionReason(why)) }
        let dir = MotionMath.sign(dlt), s = scale
        stopIdlePoses()
        mode = .shuffle
        shuf = Shuffle(x0: x0, x1: x1, dlt: dlt, dir: dir, t: 0, single: abs(dlt) < 8, fL: x0 - 7.5 * s, fR: x0 + 7.5 * s, leadIsRight: dir > 0)
        gazeAt(.point, "new spot", point: MotionPoint(x: x1, y: S(a.surface).top()))
        after(16) { [self] in
            if mode == .shuffle {
                facing.target = 0.4 * dir
                lean.target = 1.5 * dir
            }
        }
        activity = "shuffling"
        note("shuffle \(MotionMath.format(abs(dlt))) pt along \(a.surface) (\(shuf!.single ? "one side-step" : "two steps"), \(why))")
    }

    func endShuffle(_ complete: Bool) {
        guard let sh = shuf else { return }
        if complete, anchor != nil {
            anchor!.x = sh.x1
            memory[world.screenKey] = anchor
        }
        shuf = nil
        if mode == .shuffle {
            mode = .attached
            activity = "resting"
        }
    }

    func stepShuffle(_ dtMs: Double) {
        guard var sh = shuf else { return }
        sh.t += dtMs
        let t = sh.t
        let ease = { (u: Double) in MotionMath.smoothstep(0, 1, u) }
        var bodyX: Double
        if sh.single {
            let u = MotionMath.clamp(t / MotionTiming.step, 0, 1)
            bodyX = sh.x0 + sh.dlt * ease(u)
        } else if t < MotionTiming.step {
            let u = t / MotionTiming.step
            bodyX = sh.x0 + sh.dlt / 2 * ease(u)
        } else {
            let u = MotionMath.clamp((t - MotionTiming.step) / MotionTiming.step, 0, 1)
            bodyX = sh.x0 + sh.dlt / 2 + sh.dlt / 2 * ease(u)
        }
        anchor?.x = bodyX
        let stepsDone = sh.single ? MotionTiming.step : 2 * MotionTiming.step
        if t >= stepsDone, !sh.settling {
            sh.settling = true
            facing.target = 0
            lean.set(0.25, 0.55)
            lean.target = 0
        }
        if sh.settling { anchor?.x = sh.x1 }
        shuf = sh
        if t >= stepsDone + MotionTiming.stepSettle {
            endShuffle(true)
            after(0) { [self] in attendContent() }
        }
    }

    // MARK: Where he should be

    /// The best rule on a list to stand on: the remembered one if it still fits, else the first
    /// that fits (his head inside the list, his feet above its bottom, no finger on its row),
    /// else the rail.
    public func bestRuleSpot(prefer: Int?, in list: any MotionList) -> MotionSpot {
        let hz = 108.0
        let fits = { (i: Int) -> Bool in
            let y = list.ruleY(i, ahead: 0)
            return y - hz >= list.top - 0.5 && y <= list.bottom - 2 && !list.isUnderFinger(i)
        }
        if let prefer, prefer < list.ruleCount, fits(prefer) { return MotionSpot(.rule(prefer), x: list.ruleX) }
        for i in 0..<list.ruleCount where fits(i) { return MotionSpot(.rule(i), x: list.ruleX) }
        return list.waitSpot
    }

    /// The screen changed (a tab, a page, a panel): go to his spot on it.
    public func updateDestination(_ reason: MotionReason?) {
        if world.isCovered { return }
        guard let pref = world.preferredSpot(for: self) else { return }
        pendingTransfer = nil
        pendingPickup = false
        pendingStepOff = nil
        if reason?.tab != nil, !settings.reduceMotion {
            changes = changes.filter { now - $0 < MotionTiming.calmWindow }
            changes.append(now)
            lastChange = now
            if changes.count >= MotionTiming.calmChanges, !calm {
                calm = true
                note("rapid switching: wait on the rail")
            }
        }
        if calm, !settings.reduceMotion {
            let wait = world.waitSpot(for: self)
            if mode == .attached, world.isWaitSpot(anchor), wait.isSame(as: anchor) {
                if let tab = reason?.tab { gazeAtTab(tab) }
                return
            }
            if mode == .attached || mode == .shuffle {
                return startHop(wait, MotionReason("calm mode", tab: reason?.tab, tapT: reason?.tapT))
            }
            if let t = target, world.isWaitSpot(t), wait.isSame(as: t) {
                if let tab = reason?.tab { gazeAtTab(tab) }
                return
            }
            return retarget(wait, MotionReason("calm mode"))
        }
        if mode == .fade {
            if !pref.isSame(as: target) { startFade(pref, reason) }
            return
        }
        if mode == .shuffle { endShuffle(false) }
        if mode == .attached, let a = anchor {
            if pref.isSame(as: a) {
                if let tab = reason?.tab { gazeAtTab(tab) }
                after(260) { [self] in if mode == .attached { attendContent() } }
                return
            }
            if hiddenBehind, pref == a { return }
            let sameSize = abs(scaleFor(pref) - scale) < 0.001
            if sameSize, a.surface == .panel, let c = world.carrier, c.target > c.top, pref.surface != .panel {
                let s = S(pref.surface), top = s.top(), xr = s.standRange()
                if top > c.top, top <= c.target + 1, pos.x >= xr.lowerBound, pos.x <= xr.upperBound {
                    pendingTransfer = MotionSpot(pref.surface, x: pos.x)
                    activity = "riding"
                    note("riding the panel down; will step onto \(pref.surface)")
                    return
                }
            }
            if sameSize, pref.surface == .panel, let c = world.carrier, c.target < c.top {
                let top = pos.y, settle = supportSettleY()
                let staying = settle == nil || settle! - top <= 4
                if staying, top < c.top, top >= c.target - 1 {
                    pendingPickup = true
                    activity = "waiting for pickup"
                    gazeAt(.point, "rising panel", point: MotionPoint(x: pos.x, y: c.top))
                    note("the rising panel will pick him up")
                    return
                }
            }
            let goY = predictedPoint(pref).y - pos.y
            if MotionMath.sign(vel.y) != MotionMath.sign(goY), abs(vel.y) >= 150 {
                pendingStepOff = (pref, reason)
                activity = "riding"
                if let tab = reason?.tab { gazeAtTab(tab) }
                note("his surface is already speeding away: ride until it slows, then step off")
                return
            }
            return startHop(pref, reason)
        }
        if mode == .anticipate || mode == .flight {
            if let t = target, t.isSame(as: pref) { return }
            return retarget(pref, reason)
        }
    }

    // MARK: Home visits, welcomes, glances

    func startVisit() {
        visit = Visit(start: now, nextGlanceAt: now + 25_000 + rand.next() * 20_000)
        if world.hasWaitingStrip, !settings.lowPower {
            visit.arrivalGlance = true
            after(750) { [self] in _ = glance(world.gazePoint(.draftStrip), "draft strip", 520) }
        }
    }

    func glance(_ pt: MotionPoint, _ label: String, _ ms: Double) -> Bool {
        guard mode == .attached, let a = anchor, a.surface == .stage, gesture == nil, homeTouch == nil else { return false }
        if visit.glances >= 3 { return false }
        visit.glances += 1
        reaction = Reaction(kind: "glance", until: now + ms)
        gazeAt(.point, "glance: \(label)", point: pt)
        if !settings.reduceMotion {
            let dir = MotionMath.sign(pt.x - pos.x)
            facing.target = 0.25 * dir
            roll.target = MotionMath.clamp(dir * 3, -5, 5)
            after(ms) { [self] in
                if mode == .attached {
                    facing.target = 0
                    roll.target = 0
                }
            }
        }
        note("glance at the \(label) (\(MotionMath.format(ms)) ms, \(visit.glances)/3 this visit)")
        return true
    }

    func lookAround() {
        if visit.lookAround { return }
        visit.lookAround = true
        visit.glances += 1
        gesture = Gesture(kind: .look)
        note("look-around: eyes left, right, back to you (1.4 s)")
    }

    /// The daily welcome (once per day, on Home, once Home is interactive).
    public func welcome(_ kind: WelcomeKind? = nil) {
        if welcomeBudget <= 0 { return }
        welcomeBudget -= 1
        visit.hadWelcome = true
        let kind = kind ?? settings.welcomeKind
        if kind == .back, !settings.reduceMotion {
            flickHopInPlace(10 * 1.4, "welcome back")
            welcomeAfterHop = true
            note("welcome back (3+ days away): one hop in place, pleased, then the default welcome")
            return
        }
        gesture = Gesture(kind: kind == .evening ? .welcomeEvening : .welcome)
        gazeAt(.user)
        activity = "welcoming"
        note(kind == .evening ? "welcome after 21:00: one slow 280 ms blink and a 3° roll" : "daily welcome: eyes to you, 5° head roll")
    }

    // MARK: Playful moments

    public enum Playful: String, Sendable {
        case wave, stretch, trace
    }

    /// Why a playful moment can't happen now, or nil if it can.
    public func playfulRefusal(home: Bool) -> String? {
        if settings.reduceMotion { return "Playful moments are off with Reduce Motion." }
        if playfulUsed >= 1 { return "One playful moment per session; this session has had it." }
        if world.isTaskOpen || world.isKeyboardUp || world.isVoiceLive { return "Not during a task." }
        if now - world.lastTap < 2000 { return "Not within 2 s of a tap." }
        if mode != .attached { return "Not while he is moving." }
        if home, !world.isOnHome || anchor?.surface != .stage { return "This one only happens on Home." }
        if home, visit.hadWelcome { return "Not on a visit that already had the daily welcome." }
        if home, now - max(idleSince, world.lastInput) < 8000 { return "Needs at least 8 s of idle first." }
        return nil
    }

    @discardableResult
    public func playful(_ kind: Playful, force: Bool = false) -> Bool {
        if !force, let why = playfulRefusal(home: kind != .trace) {
            note("\(kind.rawValue) refused: \(why)")
            return false
        }
        playfulUsed += 1
        metrics.playful.append(PlayfulMoment(t: now, kind: kind.rawValue, duringTask: world.isTaskOpen || world.isKeyboardUp || world.isVoiceLive))
        switch kind {
        case .wave:
            gesture = Gesture(kind: .wave)
            gazeAt(.user)
            activity = "waving"
            note("wave (fixed): arm in front of the head, glove ≥ 5 pt outside it")
        case .stretch:
            gesture = Gesture(kind: .stretch, fromSit: sit.x > 0.3)
            breathT = -1
            activity = "stretching"
            note("stretch: arms up, onto his toes, eyes closed 200 ms, back down")
        case .trace:
            gesture = Gesture(kind: .trace)
            activity = "tracing the source"
            gazeAt(.point, "SOURCE", point: world.gazePoint(.sourceLabel))
            note("trace the source: eyes to SOURCE, then the arm")
        }
        return true
    }

    public func resetBudgets() {
        welcomeBudget = 1
        playfulUsed = 0
        visit.hadWelcome = false
        note("budgets reset: one welcome, one playful moment")
    }

    // MARK: Events from the screen

    /// The user typed a character.
    public func userTyped() {
        if typingArmed, mode == .attached, gesture == nil, thinking == nil {
            typingArmed = false
            microReact("typing")
        }
        lastTyping = now
    }

    /// Re-arms the typing reaction after 3 s without typing.
    public func rearmTyping() {
        if now - lastTyping > 3000 { typingArmed = true }
    }

    /// A message went to Doddy.
    public func userSent() {
        if now - lastSendReact > 5000, mode == .attached {
            lastSendReact = now
            microReact("send")
        }
    }

    func microReact(_ kind: String) {
        if kind == "typing" {
            micro = Micro(kind: kind, t: 0, dur: 240)
            gazeAt(.point, "your text", point: world.gazePoint(.composerText))
            if !settings.reduceMotion { roll.target = -3 }
            note("typing starts: eyes to your text, 3° dip (240 ms)")
        }
        if kind == "send" {
            micro = Micro(kind: kind, t: 0, dur: 280)
            gazeAt(.point, "sent bubble", point: world.gazePoint(.sentBubble))
            if !settings.reduceMotion { roll.target = 4 }
            note("send: eyes follow the bubble up, 4° nod (280 ms)")
        }
    }

    func startBlink(_ dur: Double = 210) {
        blinkT = 0
        blinkDur = dur
    }

    /// Waiting for Doddy's reply on Talk: thinking from 600 ms (only while he stands on the
    /// composer), one slow blink and a look to the upper left at 4 s.
    public func waitingForReply(sentAt: Double, thinkingAt: Double, replyAt: Double) {
        if thinking == nil, now >= thinkingAt, now < replyAt, mode == .attached, anchor?.surface == .composer {
            thinking = (now, false)
            micro = nil
            gazeAt(.dir, "thinking (up and right)", point: MotionPoint(x: 0.78, y: -0.68))
            if !settings.reduceMotion {
                roll.set(0.28, 0.9)
                roll.target = 4
            }
            activity = "thinking"
            note("no reply after 600 ms: thinking pose (eyes up right, head 4°), held still")
        }
        if let th = thinking, !th.blinked, now >= sentAt + 4000 {
            thinking!.blinked = true
            startBlink(280)
            after(140) { [self] in if thinking != nil { gazeAt(.dir, "thinking (up and left)", point: MotionPoint(x: -0.78, y: -0.66)) } }
            note("still waiting at 4 s: one slow blink, eyes to the upper left once")
        }
    }

    public func endThinking(failed: Bool) {
        guard thinking != nil else { return }
        thinking = nil
        roll.set(0.32, 1.0)
        roll.target = 0
        activity = "resting"
        note(failed ? "thinking ends: the request failed" : "thinking ends: eyes snap to the reply (88 ms), head straightens (240 ms)")
    }

    /// Voice is starting from a hold on Home: curious, no listening pose until capture is live.
    public func voiceStarting() {
        squint.target = 0
        dipSpring.target = 0
        setMood("curious", 0)
    }

    public func voiceEnded() {
        if listenOn { exitListen() }
        setMood("calm")
    }

    func exitListen() {
        listenOn = false
        // The arm leaves the ear in the same frame the microphone turns off.
        armR1.x = min(armR1.x, 75)
        armR2.x = min(armR2.x, 55)
        armR1.set(0.22, 0.9)
        armR2.set(0.22, 0.9)
        armR1.target = 30
        armR2.target = 20
        roll.target = 0
    }

    /// A list row was inserted above row `index` (a memory was saved): his rule numbers move down.
    public func rulesShifted(insertedAt index: Int = 0, by n: Int = 1) {
        func shift(_ s: MotionSpot?) -> MotionSpot? {
            guard let s, let i = s.surface.ruleIndex, i >= index else { return s }
            return MotionSpot(.rule(i + n), x: s.x)
        }
        anchor = shift(anchor)
        target = shift(target)
        if let m = memory["memories"], let i = m.surface.ruleIndex, i >= index { memory["memories"] = MotionSpot(.rule(i + n), x: 330) }
    }

    /// A page is pushed over the screen. If he stands on a list rule he stays and is covered in
    /// place (returns true); otherwise he goes to the page's spot.
    @discardableResult
    public func pagePushed() -> Bool {
        if mode == .attached, anchor?.surface.isRule == true {
            hiddenBehind = true
            activity = "behind the page"
            reaction = Reaction(kind: "incoming page", until: now + 100)
            gazeAt(.point, "incoming page", point: MotionPoint(x: 390, y: 300))
            note("detail page pushed over him: he stays where he is and is covered")
            return true
        }
        updateDestination(MotionReason("detail opened"))
        return false
    }

    /// The page pops: uncovered where he stood, or he leaves the page as it goes.
    public func pagePopped() {
        if hiddenBehind {
            hiddenBehind = false
            activity = "resting"
            after(120) { [self] in attendContent() }
            note("page pops: the left edge uncovers first; he is revealed where he stood")
        } else if mode == .attached, anchor?.surface == .detail, let pref = world.preferredSpot(for: self) {
            startHop(pref, MotionReason("page leaving"), immediate: true)
        } else {
            updateDestination(MotionReason("detail closed"))
        }
    }

    /// The tab changed away from the screen he was hidden behind.
    public func leftCoveredScreen() { hiddenBehind = false }

    /// When he was last moved without a hop (`carried`): his size may change in that frame,
    /// because he is unseen or the thing that carries him appears with him.
    public private(set) var lastCarried = -1.0
    /// How many times he has been carried (the DEBUG checks compare it between frames: the engine's
    /// clock doesn't move between a carry made outside a step and the next check).
    public private(set) var carries = 0

    /// Moves him at once onto `spot`, with no hop (motion v2, MV4): the app carries him there,
    /// either unseen (a cover going up hides him on Home while Ask's composer, inside it, brings
    /// him up) or on a surface that appears or goes in one frame under him (the undo bar). Any
    /// hop in progress ends; he stands on the new spot at its size.
    public func carried(to spot: MotionSpot, _ why: String) {
        flight = nil
        target = nil
        pendingStepOff = nil
        resetArms()
        tuck.target = 0
        crouch.target = 0
        lean.target = 0
        hiddenBehind = false
        anchor = spot
        mode = .attached
        scale = scaleFor(spot)
        pos = anchorPoint(spot)
        vel = MotionPoint(x: 0, y: 0)
        z = S(spot.surface).layer + 0.2
        memory[world.screenKey] = spot
        lastCarried = now
        carries += 1
        activity = "resting"
        // Arriving restarts his idle (a landing does the same): after a long time on Ask's
        // composer he stood back on Home's stage and sat down at once, because the 15 s were
        // counted from before he left (hosted run 39379870387, MotionRideTests).
        idleSince = now
        note("carried to \(spot.surface): \(why)")
    }

    public func bannerChanged(showing: Bool, at point: MotionPoint) {
        if showing {
            notice("offline banner", point, 600, mood: "concerned")
            bannerConcern = true
            note("offline banner: eyes to it, concerned brow while it is up")
        } else {
            bannerConcern = false
            if mood == "concerned" { setMood("calm") }
            if mode == .attached, thinking == nil, gesture == nil, reaction == nil || reaction?.kind == "offline banner" {
                reaction = nil
                attendContent()
            }
            note("banner gone: calm")
        }
    }

    /// Whether he is standing still on the carrier, ready to introduce what it shows.
    public var canIntroduce: Bool {
        mode == .attached && anchor?.surface == .panel && now - lastLand >= 600 && !supportMovingNow()
    }

    /// Introduces what the open carrier shows (the reference's draft): eyes, head, then arm.
    /// Returns false when he isn't standing on it.
    @discardableResult
    public func introduceDraft() -> Bool {
        guard mode == .attached, anchor?.surface == .panel, world.carrier?.mode == .open else { return false }
        gesture = Gesture(kind: .introduce)
        activity = "introducing the draft"
        reaction = nil
        gazeAt(.point, "draft, first line", point: world.gazePoint(.draftFirstLine))
        note("introduce the draft: eyes 0 ms → head 60 ms → arm 200 ms → hold → rest")
        return true
    }

    /// Editing always wins over the introduction.
    public func userEditedDraft(at point: MotionPoint) {
        if gesture?.kind == .introduce {
            gesture = nil
            armL1.set(0.12, 1)
            armL2.set(0.12, 1)
            armL1.target = 30
            armL2.target = 20
            roll.target = 0
            gazeAt(.point, "your edit", point: point)
            note("editing wins: the gesture ends within 180 ms")
        }
    }

    /// Reduce Motion changed. Mid-hop, the hop becomes a fade to the same place.
    public func setReduceMotion(_ on: Bool) {
        settings.reduceMotion = on
        note("Reduce Motion \(on ? "on: hops become fades; eyes still lead" : "off")")
        if on, mode == .flight || mode == .anticipate, let t = target {
            flight = nil
            resetArms()
            tuck.target = 0
            crouch.target = 0
            lean.target = 0
            startFade(t, MotionReason("Reduce Motion turned on mid-hop"))
        }
    }

    /// Home's size changed: he fades to the new size (scale changes only unseen or in the air).
    public func homeScaleChanged(_ v: Double) {
        settings.homeScale = v
        if mode == .attached, anchor?.surface == .stage, abs(scale - v) > 1e-3 {
            startFade(MotionSpot(.stage, x: anchor!.x), MotionReason("Home size changed"))
        }
    }

    // MARK: Touch

    /// A finger came down somewhere on Home that isn't him: his eyes follow it.
    public func fingerDownElsewhereOnHome() {
        if mode == .attached {
            reaction = nil
            gazeAt(.finger, "your finger")
            followFinger = true
        }
    }

    public func fingerLifted() {
        if followFinger {
            followFinger = false
            after(300) { [self] in if gaze.kind == .finger, !world.finger.isDown { gazeAt(.user) } }
        }
    }

    public func homeTouchDown(x: Double, y: Double) {
        let hp = headPos(), s = scale
        homeTouch = HomeTouch(t0: now, x0: x, y0: y, kind: nil, onHead: MotionMath.hyp(x - hp.x, y - hp.y) <= (17.5 + 10) * s, lastX: x)
        guard mode == .attached, anchor?.surface == .stage else { return }
        reaction = nil
        gesture = nil
        breathT = -1
        squint.set(0.05, 1.0)
        squint.target = 1
        if !settings.reduceMotion {
            dipSpring.set(0.06, 1.0)
            dipSpring.target = 3 / s
        }
        note("touch down on him: squints and dips 3 pt within 60 ms")
    }

    public func homeTouchMove(x: Double, y: Double) {
        guard var ht = homeTouch else { return }
        let finger = world.finger
        if ht.kind == nil, finger.moved {
            ht.kind = ht.onHead ? .stroke : .drag
            squint.target = 0
            dipSpring.target = 0
            if world.voicePhaseIsStarting {
                world.cancelStartingVoice()
                setMood("calm")
            }
            note(ht.kind == .stroke ? "stroke across his head" : "drag on his body")
        }
        if ht.kind == .drag {
            let dx = x - ht.x0, dy = y - ht.y0, s = scale
            lean.set(0.12, 1.0)
            lean.target = 12 * tanh(dx / 60)
            dragC.set(0.10, 1.0)
            dragC.target = dy > 0 ? 6 * tanh(dy / 50) / s : 0
            stretchUp.set(0.10, 1.0)
            stretchUp.target = dy < 0 ? 0.06 * tanh(-dy / 60) : 0
            gazeAt(.finger, "your finger")
        }
        if ht.kind == .stroke {
            let hp = headPos(), s = scale
            let speed = MotionMath.hyp(finger.vx, finger.vy)
            let over = MotionMath.hyp(x - hp.x, y - hp.y) <= (17.5 + 14) * s
            let dxm = x - ht.lastX
            ht.lastX = x
            homeTouch = ht
            if over, speed < 600 {
                if !rub.active { startRub() }
                if rub.active, !rub.smileOnly, !settings.reduceMotion, abs(dxm) > 0.2 {
                    roll.set(0.16, 0.9)
                    roll.target = 6 * MotionMath.sign(dxm)
                }
            } else if rub.active {
                endRub()
            }
            return
        }
        homeTouch = ht
    }

    func startRub() {
        rub.starts = rub.starts.filter { now - $0 < 60_000 }
        if now - rub.lastStart < 1500 { return } // one per 1.5 s
        rub.active = true
        rub.lastStart = now
        rub.starts.append(now)
        rub.smileOnly = rub.starts.count > 5
        setMood("pleased", 0)
        if !rub.smileOnly {
            shut.target = 1
            gazeAt(.user)
        }
        activity = "head rub"
        note(rub.smileOnly ? "head rub (6th in a minute): only a smile" : "head rub: eyes close, pleased, head tips with the stroke")
    }

    func endRub() {
        guard rub.active else { return }
        rub.active = false
        rub.lastEnd = now
        roll.set(0.24, 0.8)
        roll.target = 0
        after(300) { [self] in
            if !rub.active {
                shut.target = 0
                gazeAt(.user)
                after(400) { [self] in if !rub.active, mood == "pleased" { setMood("calm") } }
            }
        }
        activity = "resting"
    }

    public func homeTouchUp() {
        let ht = homeTouch
        homeTouch = nil
        squint.target = 0
        dipSpring.target = 0
        guard let ht else { return }
        let vy = world.finger.vy
        if world.voicePhaseIsStarting || world.isVoiceLive {
            world.endVoice("released")
            return
        }
        if rub.active { endRub() }
        if ht.kind == .drag || ht.kind == .stroke {
            let rm = settings.reduceMotion
            for sp in [lean, dragC, stretchUp] { sp.set(0.30, rm ? 1.0 : 0.55) }
            lean.target = 0
            dragC.target = 0
            stretchUp.target = 0
            if vy < -900, now - lastFlick >= 3000, !rm, mode == .attached, anchor?.surface == .stage {
                lastFlick = now
                lean.snap(0)
                dragC.snap(0)
                flickHopInPlace(MotionMath.clamp(-vy / 80, 8, 24) * 1.4, "upward flick")
            } else {
                note("released: springs back with one overshoot (0.30/0.55)")
            }
            return
        }
        if ht.kind == .holdTap || (ht.kind == nil && now - ht.t0 < MotionTiming.hold) || (ht.kind == nil && !settings.voiceFromHome) {
            note("tap on him: Talk opens")
            world.openTalkFromHome(tapT: now)
        }
    }

    /// Press and hold: at 450 ms voice starts (or, if it can't, the hold acts as a tap).
    public func checkHold() {
        guard var ht = homeTouch else { return }
        let f = world.finger
        if f.isDown, ht.kind == nil, !f.moved, now - ht.t0 >= MotionTiming.hold, !ht.holdFired {
            ht.holdFired = true
            if world.startVoice() {
                ht.kind = .voice
            } else {
                ht.kind = .holdTap
                note("hold: voice can’t start from Home here, so it acts as a tap on release")
            }
            homeTouch = ht
        }
    }

    func flickHopInPlace(_ A: Double, _ why: String) {
        guard mode == .attached, let a = anchor else { return }
        stopIdlePoses()
        let p = anchorPoint(a)
        target = a
        curHop = HopPlan(requestedAt: now, tapAt: now, why: why, from: a.surface.description, to: a.surface.description, anticipation: 0, startScale: scale, endScale: scale, isTabHop: false)
        curHop!.inPlace = true
        flight = MotionFlight(p0: p, p1: p, t0: now, m0: .zero, m1: .zero, h: A, T: MotionTiming.flight(0, 0), s0: scale, s1: scale, kind: .flick)
        curHop!.takeoffAt = now
        curHop!.crouch = 0
        curHop!.flightTime = flight!.T
        curHop!.distance = 0
        curHop!.apex = A
        mode = .flight
        airStart = now
        airborne = 0
        activity = "hop in place"
        stretchUp.target = 0
        squash.x = 1
        squash.target = 0
        armL1.target = 105
        armL2.target = 135
        armR1.target = 105
        armR2.target = 135
        for s in [armL1, armL2, armR1, armR2] { s.set(0.14, 0.9) }
        tuck.set(0.18, 0.9)
        tuck.target = 0.7
        anchor = nil
        setMood("pleased", 1200)
        note("\(why): hop in place, apex \(MotionMath.format(A, digits: 1)) pt")
    }

    // MARK: Scroll riding

    /// Doddy in a scrolling list: ride his rule, make a lily-pad hop as it leaves the safe band,
    /// or wait on the rail while it moves fast, then one hop back once it settles.
    func stepScrollRiding() {
        if calm { return }
        guard let list = world.ridingList() else { return }
        let speed = abs(list.velocity)
        if mode == .attached, let i = anchor?.surface.ruleIndex {
            let fast = speed > MotionTiming.lilySlow || list.isScrollingToTop || list.isFlinging
            if fast {
                scrollWait = true
                startHop(list.waitSpot, MotionReason(list.isScrollingToTop ? "scroll to top" : "fast scroll"))
                return
            }
            let yNow = list.ruleY(i, ahead: 0), yp = yNow - list.velocity * (MotionTiming.lilyLook / 1000)
            let leaving = yp - 96 < list.top || yp > list.bottom
            if leaving, speed > 1 {
                let incomingBelow = -list.velocity < 0
                if now - lastLily >= MotionTiming.lilyGap, speed < MotionTiming.lilySlow {
                    let vh = list.bottom - list.top, b0 = list.top + 0.2 * vh, b1 = list.top + 0.8 * vh
                    var cands: [(j: Int, d: Int)] = []
                    for j in 0..<list.ruleCount {
                        if j == i || list.isUnderFinger(j) { continue }
                        let y = list.ruleY(j, ahead: 0.45)
                        if y >= b0, y <= b1, incomingBelow ? j > i : j < i { cands.append((j, abs(j - i))) }
                    }
                    cands.sort { $0.d < $1.d }
                    if let c = cands.first {
                        lastLily = now
                        startHop(MotionSpot(.rule(c.j), x: list.ruleX), MotionReason("lily-pad hop (rule leaving the safe band)"))
                        return
                    }
                }
                scrollWait = true
                startHop(list.waitSpot, MotionReason("rule leaving and no lily pad allowed: wait on the rail"))
            }
            return
        }
        if mode == .attached, anchor?.surface == .rail, scrollWait, !list.isFingerDown {
            if let slow = list.slowSince, now - slow >= MotionTiming.lilySettleFor {
                let vh = list.bottom - list.top, b0 = list.top + 0.2 * vh, b1 = list.top + 0.8 * vh
                var pick: Int?
                for j in 0..<list.ruleCount {
                    let y = list.ruleY(j, ahead: 0.45)
                    if y >= b0, y <= b1 {
                        pick = j
                        break
                    }
                }
                scrollWait = false
                if let pick {
                    startHop(MotionSpot(.rule(pick), x: list.ruleX), MotionReason("list settled: one hop to the best rule"))
                } else {
                    note("list settled but no rule fits: he stays on the rail")
                }
            }
        }
    }

    // MARK: Step

    /// The second half of a step, after the host has moved its surfaces: calm-mode release,
    /// scroll riding, then the character.
    public func finishStep(_ dtMs: Double) {
        if calm, now - lastChange > MotionTiming.calmQuiet, mode == .attached {
            calm = false
            changes = []
            note("input settled for 350 ms: one hop to the final spot")
            updateDestination(MotionReason("calm mode over"))
        }
        stepScrollRiding()
        stepDoddy(dtMs, dtMs / 1000)
    }

    func stepDoddy(_ dtMs: Double, _ dt: Double) {
        var prevPos = pos
        surfaceVel = .zero
        if mode == .attached || mode == .anticipate || mode == .shuffle, anchor != nil {
            if pendingPickup, let c = world.carrier {
                let top = c.top, footNow = anchorPoint(anchor!).y
                if c.previousTop - pos.y > -0.5, top - footNow <= 0.5 {
                    pendingPickup = false
                    anchor = MotionSpot(.panel, x: MotionMath.clamp(pos.x, 40, 330))
                    z = 2.2
                    activity = "riding"
                    resetSupportVel(anchor!)
                    crouch.set(0.25, 0.55)
                    crouch.v += MotionMath.clamp(abs((c.previousTop - top) / dt) * 0.012, 0, 30)
                    gazeAt(.anchor, "panel edge", anchor: anchor)
                    note("picked up by the panel edge")
                }
            }
            if let pt = pendingTransfer, anchor?.surface == .panel, let c = world.carrier {
                let top = S(pt.surface).top()
                if c.top >= top - 0.5 {
                    anchor = pt
                    pendingTransfer = nil
                    z = S(pt.surface).layer + 0.2
                    activity = "resting"
                    resetSupportVel(pt)
                    crouch.set(0.25, 0.55)
                    crouch.v += 18
                    dip(pt.surface).v += 25
                    memory[world.screenKey] = pt
                    after(150) { [self] in attendContent() }
                    note("stepped across onto \(pt.surface) as the panel passed")
                }
            }
            if mode == .shuffle { stepShuffle(dtMs) }
            if let a = anchor { pos = anchorPoint(a) }
        }
        if mode == .anticipate {
            phaseT += dtMs
            if phaseT >= antDur {
                surfaceVel = MotionPoint(x: (pos.x - prevPos.x) / max(dt, 1e-4), y: (pos.y - prevPos.y) / max(dt, 1e-4))
                takeOff()
            }
        }
        if mode == .flight, flight != nil {
            flight!.t = now - flight!.t0
            airborne = now - airStart
            phaseT = flight!.t
            if flight!.kind != .flick, let t = target {
                let touch = pointAt(t, max(0, (flight!.T - flight!.t) / 1000))
                if MotionMath.hyp(touch.x - flight!.p1.x, touch.y - flight!.p1.y) > 2 {
                    retarget(t, MotionReason("its surface changed course"), force: true)
                }
            }
            var f = flight!
            f.t = now - f.t0
            let s = MotionMath.clamp(f.t / f.T, 0, 1)
            if f.kind != .flick, let t = target {
                let p1 = pointAt(t, max(0, (f.T - f.t) / 1000))
                f.p1 = p1
                f.m1 = MotionPoint(x: p1.x - f.p0.x, y: p1.y - f.p0.y)
            }
            flight = f
            pos = f.point(s)
            vel = f.velocity(s)
            scale = HopPlan.scale(from: f.s0, to: f.s1, progress: s)
            if s > 0.55 {
                for sp in [armL1, armL2, armR1, armR2] { sp.set(0.2, 0.9) }
                armL1.target = 32
                armL2.target = 30
                armR1.target = 32
                armR2.target = 30
                tuck.target = 0.2
            }
            if s >= 1 {
                land()
                if welcomeAfterHop {
                    welcomeAfterHop = false
                    after(420) { [self] in
                        gesture = Gesture(kind: .welcome)
                        gazeAt(.user)
                    }
                }
            }
        }
        if mode == .fade {
            phaseT += dtMs
            if phaseT < fadeOutMs {
                opacity = min(opacity, 1 - phaseT / fadeOutMs)
            } else {
                if !fadeMoved, let t = target {
                    fadeMoved = true
                    anchor = t
                    scale = scaleFor(t)
                    pos = anchorPoint(t)
                    z = S(t.surface).layer + 0.2
                    memory[world.screenKey] = t
                    if t.surface == .stage { startVisit() }
                }
                if let t = target, t != anchor {
                    anchor = t
                    scale = scaleFor(t)
                }
                if let a = anchor { pos = anchorPoint(a) }
                // One fully invisible frame (20 ms) between the fade out and the fade in, so size
                // and place change unseen.
                opacity = MotionMath.clamp((phaseT - fadeOutMs - MotionTiming.fadeGap) / fadeInMs, 0, 1)
                if phaseT >= fadeOutMs + MotionTiming.fadeGap + fadeInMs {
                    mode = .attached
                    target = nil
                    fadeMoved = false
                    vel = .zero
                    accHist = []
                    justLanded = true
                    opacity = 1
                    activity = "resting"
                    lastLand = now
                    idleSince = now
                    breathT = now + 2000
                    attendContent()
                }
            }
        }
        if mode == .attached || mode == .shuffle {
            if justLanded {
                justLanded = false
                prevPos = MotionPoint(x: pos.x - vel.x * dt, y: pos.y - vel.y * dt)
            }
            if opacity < 1, mode == .attached { opacity = min(1, opacity + dtMs / 150) }
            let vy = (pos.y - prevPos.y) / max(dt, 1e-4)
            let ay = (vy - vel.y) / max(dt, 1e-4)
            vel = MotionPoint(x: (pos.x - prevPos.x) / max(dt, 1e-4), y: vy)
            // Weight response (rig units; up to 3 pt at 1.0×).
            if !settings.reduceMotion, abs(vy) > 1 {
                crouch.set(0.25, 0.55)
                let kw = pow(2 * Double.pi / 0.25, 2)
                crouch.force = MotionMath.clamp(-ay * 0.026 / scale, -3 * kw, 3 * kw)
            } else {
                crouch.force = 0
            }
            // Brace: mean acceleration of his support over the last 100 ms (list rules excluded:
            // overscroll gets the weight response only).
            accHist.append((now, vel.x, vel.y))
            while accHist.count > 1, now - accHist[0].t > 100 { accHist.removeFirst() }
            let h0 = accHist[0], span = (now - h0.t) / 1000
            supAcc = span >= 0.05 ? MotionMath.hyp(vel.x - h0.vx, vel.y - h0.vy) / span : 0
            let moving = supportMovingNow()
            let braceable = anchor != nil && !anchor!.surface.isRule
            if moving { brace.peak = max(brace.peak, supAcc) }
            if !settings.reduceMotion, braceable, moving, !brace.done, !brace.on, supAcc > settings.braceOn {
                brace.on = true
                brace.done = true
                for s in [armL1, armL2, armR1, armR2] { s.set(0.12, 0.8) }
                armL1.target = 55
                armL2.target = 45
                armR1.target = 55
                armR2.target = 45
                metrics.braces.append(Brace(t: now, acc: supAcc.rounded()))
                note("brace: support accelerating at \(MotionMath.format(supAcc / 1000, digits: 1))k pt/s², arms out 25°")
            }
            if brace.on {
                if supAcc < settings.braceOff {
                    if brace.lowSince == 0 { brace.lowSince = now }
                } else {
                    brace.lowSince = 0
                }
                if (brace.lowSince != 0 && now - brace.lowSince >= 120) || !moving {
                    brace.on = false
                    brace.lowSince = 0
                    resetArms(0.3)
                    note("brace released: the push has passed")
                }
            }
            if !moving, activity != "riding", brace.done || brace.peak != 0 {
                if brace.peak > 1000 { metrics.ridePeaks.append(RidePeak(t: now, surface: anchor?.surface.description ?? "?", peak: brace.peak.rounded())) }
                brace.done = false
                brace.peak = 0
            }
            if moving, activity == "resting" || activity == "landing" { activity = "riding" }
            if !moving, activity == "riding", pendingTransfer == nil, !pendingPickup {
                activity = "resting"
                brace.done = false
                if brace.peak > 1000 { metrics.ridePeaks.append(RidePeak(t: now, surface: anchor?.surface.description ?? "?", peak: brace.peak.rounded())) }
                brace.peak = 0
            }
            if activity == "landing", now - lastLand > 340 { activity = "resting" }
            if let ps = pendingStepOff, abs(vel.y) < 150 {
                pendingStepOff = nil
                startHop(ps.target, ps.reason)
            }
            // Shuffle trigger: his spot is no longer inside this surface's clear range.
            if mode == .attached, let a = anchor, !hiddenBehind {
                let xr = S(a.surface).standRange()
                if a.x < xr.lowerBound - 0.5 || a.x > xr.upperBound + 0.5 {
                    if !moving { startShuffle(MotionMath.clamp(a.x, xr.lowerBound, xr.upperBound), "clear zone") }
                }
            }
        } else {
            crouch.force = 0
        }
        stepGesture(dtMs)
        if var m = micro {
            m.t += dtMs
            micro = m
            if m.t > m.dur * 0.5 { roll.target = thinking != nil ? 4 : 0 }
            if m.t > m.dur {
                micro = nil
                after(700) { [self] in if mode == .attached, gesture == nil, thinking == nil, micro == nil { attendContent() } }
            }
        }
        if let r = reaction, now >= r.until {
            reaction = nil
            if thinking == nil, gesture == nil, mode == .attached {
                if r.kind == "offline banner", world.isBannerShowing { gazeAt(.point, "banner", point: world.gazePoint(.banner)) } else { attendContent() }
            }
        }
        if userGazeAt != 0, now >= userGazeAt, mode == .attached, reaction == nil, gesture == nil, thinking == nil, micro == nil, gaze.kind == .point, !followFinger, !world.isBannerShowing {
            userGazeAt = 0
            gazeAt(.user)
        }
        if bannerConcern, world.isBannerShowing, mood != "concerned", thinking == nil { setMood("concerned") }
        if moodUntil != 0, now >= moodUntil {
            moodUntil = 0
            mood = bannerConcern ? "concerned" : "calm"
        }
        // Listening: only while capture is live (rule 10, honest always).
        let live = world.isVoiceLive
        if live, !listenOn, mode == .attached {
            listenOn = true
            setMood("calm")
            armR1.set(0.2, 0.85)
            armR2.set(0.2, 0.85)
            armR1.target = 130
            armR2.target = 137
            if !settings.reduceMotion {
                roll.set(0.24, 0.85)
                roll.target = 6
            }
            gazeAt(.user)
            activity = "listening"
        }
        if !live, listenOn { exitListen() }
        if listenOn { metrics.listenFrames += dtMs / (1000 / 60) }
        stepDuck(dtMs)
        if blinkT >= 0 {
            blinkT += dtMs
            let t = blinkT, d = blinkDur, a = d * 0.43
            blink = t < a ? t / a : t < d ? 1 - (t - a) / (d - a) : 0
            if t > d {
                blinkT = -1
                blink = 0
            }
        }
        stepIdle(dtMs)
        let gv = gazeVector()
        gx.target = gv.x
        gy.target = gv.y
        if mode == .flight, let f = flight, f.kind != .flick {
            facing.target = MotionMath.clamp(0.8 * MotionMath.sign(vel.x) * min(1, abs(vel.x) / 60), -0.8, 0.8)
        }
        let rm = settings.reduceMotion
        if rm {
            crouch.snap(0)
            lean.target = homeTouch != nil ? lean.target : 0
            roll.snap(0)
            xOff.snap(0)
            squash.snap(0)
            tuck.snap(0)
            duck.snap(0)
            toe.snap(0)
        }
        for s in [crouch, duck, dipSpring, dragC, sit, edge, lean, roll, facing, gx, gy, armL1, armL2, armR1, armR2, tuck, squash, stretchUp, xOff, toe, squint, shut] {
            s.step(dt)
            if s.force == 0, abs(s.x - s.target) < 0.003, abs(s.v) < 0.02 {
                s.x = s.target
                s.v = 0
            }
        }
        if sit.target == 0, sit.x < 0.02 { sit.set(0.45, 0.92) }
        var b = 0.0
        let idle = mode == .attached && gesture == nil && micro == nil && (activity == "resting" || activity == "sitting") && homeTouch == nil && thinking == nil && !listenOn
        if !rm, !settings.lowPower, !settings.noBreath, idle, breathT > 0, now > breathT {
            let ph = (now - breathT) / 4200
            if ph < 3 { b = 0.6 * sin(ph * 2 * Double.pi) * (ph > 2.5 ? (3 - ph) * 2 : 1) }
        }
        if !idle, breathT > 0, mode != .attached { breathT = -1 }
        breath = b
    }

    func stepDuck(_ dtMs: Double) {
        let movers = world.overheadMovers(dtMs: dtMs)
        if mode != .attached || settings.reduceMotion {
            if ducking {
                ducking = false
                duck.set(0.22, 1.0)
                duck.target = 0
            }
            return
        }
        let s = scale, hx = pos.x, headTop = pos.y - 96 * s, r = 17.5 * s
        var hit: MotionMover?
        for m in movers {
            let hOver = m.x1 > hx - r - 4 && m.x0 < hx + r + 4
            let vNear = m.y1 >= headTop - 12 && m.y0 < headTop + r
            if hOver, vNear {
                hit = m
                break
            }
        }
        if let hit, !ducking, hit.speed > 30 {
            ducking = true
            duck.set(0.14, 1.0)
            duck.target = 1
            reaction = Reaction(kind: "duck", until: now + 100_000)
            gazeAt(.dir, "up (ducking)", point: MotionPoint(x: 0, y: -1))
            note("something passes within 12 pt above his head: ducks 6 pt and looks up (140 ms)")
        }
        if hit == nil, ducking {
            ducking = false
            duck.set(0.22, 1.0)
            duck.target = 0
            reaction = nil
            after(220) { [self] in if !ducking { attendContent() } }
            note("it has passed: rises in 220 ms")
        }
    }

    func stepIdle(_ dtMs: Double) {
        guard mode == .attached, let a = anchor else { return }
        let resting = gesture == nil && micro == nil && homeTouch == nil && thinking == nil && !listenOn && reaction == nil && (activity == "resting" || activity == "sitting")
        let idleFor = now - max(idleSince, world.lastInput, lastLand)
        if a.surface == .stage, world.isOnHome {
            if settings.autoWelcome, welcomeBudget > 0, now > 500, resting {
                welcome()
                if mode != .attached || anchor == nil { return }
            }
            if resting, !settings.reduceMotion, idleFor > 15_000, !satThisIdle {
                satThisIdle = true
                sit.set(0.45, 0.92)
                sit.target = 1
                breathT = -1
                activity = "sitting"
                note("15 s idle: sits once, cross-legged, then still")
            }
            if resting, !settings.lowPower, now >= visit.nextGlanceAt, visit.glances < 3 {
                visit.nextGlanceAt = now + 25_000 + rand.next() * 20_000
                if world.hasWaitingStrip {
                    _ = glance(world.gazePoint(.draftStrip), "draft strip", 520)
                } else if world.hasMemoriesBadge {
                    _ = glance(world.gazePoint(.tab("memories")), "Memories tab", 520)
                } else if !visit.lookAround {
                    lookAround()
                }
            }
        }
        if a.surface == .panel, world.carrier?.mode == .strip, world.isOnMemories, resting, idleFor > 10_000, !edgeThisIdle, !settings.reduceMotion {
            edgeThisIdle = true
            gesture = Gesture(kind: .edgeSit)
            breathT = -1
            activity = "sitting on the strip"
            note("10 s idle on the strip: sits on its edge, legs hanging, swings twice")
        }
        if resting, !satThisIdle, !edgeThisIdle { activity = sit.x > 0.5 ? "sitting" : activity }
    }

    func stepGesture(_ dtMs: Double) {
        guard var g = gesture else { return }
        g.t += dtMs
        gesture = g
        let t = g.t, rm = settings.reduceMotion
        switch g.kind {
        case .introduce:
            if !rm, t > 60 {
                roll.set(0.24, 0.8)
                roll.target = -8
            }
            if !rm, t > 200, t < 1040 {
                armL1.set(0.41, 0.85)
                armL2.set(0.41, 0.85)
                armL1.target = 50
                armL2.target = 54
            }
            if t > 1040 {
                armL1.target = 30
                armL2.target = 20
                armL1.set(0.41, 0.9)
                armL2.set(0.41, 0.9)
                roll.target = 0
            }
            if t > 1300, activity == "introducing the draft" { activity = "resting" }
            if t > 1700 {
                gesture = nil
                activity = "resting"
                gazeAt(.user)
            }
            if world.carrier?.mode != .open || mode != .attached {
                gesture = nil
                resetArms()
                roll.target = 0
            }
        case .wave:
            if t < 260 {
                armR1.set(0.22, 0.85)
                armR2.set(0.22, 0.85)
                armR1.target = 100
                armR2.target = 116
            } else if t < 710 {
                let ph = (t - 260) / 450
                armR2.set(0.08, 0.9)
                armR2.target = 116 + 12 * sin(ph * 3 * Double.pi)
            } else if t < 1100 {
                armR1.set(0.28, 0.9)
                armR2.set(0.28, 0.9)
                armR1.target = 30
                armR2.target = 20
            } else {
                gesture = nil
                activity = "resting"
                resetArms()
            }
        case .stretch:
            let o = g.fromSit ? 140.0 : 0
            if g.fromSit, t < o {
                sit.set(0.14, 1.0)
                sit.target = 0
            }
            if t >= o, t < o + 500, !g.up {
                gesture?.up = true
                for s in [armL1, armL2, armR1, armR2] { s.set(0.36, 0.95) }
                armL1.target = 110
                armL2.target = 138
                armR1.target = 110
                armR2.target = 138
                toe.set(0.36, 1.0)
                toe.target = 1
                breathT = -1
            }
            if t >= o + 470, t < o + 700 { shut.target = 1 }
            if t >= o + 700, !g.down {
                gesture?.down = true
                shut.target = 0
                resetArms(0.30)
                for s in [armL1, armL2, armR1, armR2] { s.set(0.30, 0.95) }
                toe.set(0.30, 1.0)
                toe.target = 0
            }
            if t >= o + 960, t < o + 1100 {
                // A small wobble: clumsy offline.
                lean.set(0.14, 0.35)
                lean.target = t < o + 1030 ? 2.2 : 0
            }
            if t >= o + 1160 {
                gesture = nil
                lean.set(0.2, 0.85)
                lean.target = 0
                activity = "resting"
            }
        case .trace:
            if t > 80 {
                roll.set(0.24, 0.8)
                roll.target = -6
            }
            if t > 220, t < 900 {
                armL1.set(0.41, 0.85)
                armL2.set(0.41, 0.85)
                armL1.target = 55
                armL2.target = 55
            }
            if t >= 900 {
                armL1.target = 30
                armL2.target = 20
                roll.target = 0
            }
            if t > 1300 {
                gesture = nil
                activity = "resting"
                gazeAt(.user)
            }
        case .welcome:
            if !rm, t > 200, t < 700 {
                roll.set(0.2, 0.9)
                roll.target = 5
            }
            if t >= 700 {
                roll.set(0.24, 0.95)
                roll.target = 0
            }
            if t > 940 {
                gesture = nil
                activity = "resting"
            }
        case .welcomeEvening:
            if t > 60, !g.blinked {
                gesture?.blinked = true
                startBlink(280)
            }
            if !rm, t > 200, t < 700 {
                roll.set(0.24, 0.9)
                roll.target = 3
            }
            if t >= 700 {
                roll.set(0.26, 0.95)
                roll.target = 0
            }
            if t > 960 {
                gesture = nil
                activity = "resting"
            }
        case .look:
            if t < 450 {
                gazeAt(.dir, "look around (left)", point: MotionPoint(x: -0.95, y: 0.05))
            } else if t < 950 {
                gazeAt(.dir, "look around (right)", point: MotionPoint(x: 0.95, y: 0.05))
            } else {
                gazeAt(.user)
            }
            if t > 1400 { gesture = nil }
        case .edgeSit:
            if t < 400 {
                edge.set(0.32, 0.95)
                edge.target = 1
            }
            if t >= 450, t < 1050 { swing = sin(((t - 450) / 600) * 4 * Double.pi) * (1 - (t - 450) / 600 * 0.3) }
            if t >= 1050 { swing *= 0.8 }
            if t > 1200 {
                swing = 0
                gesture = nil
                activity = "sitting"
            }
        }
    }

    // MARK: Placement and reading

    /// Puts him on a spot at once (a screen opening, a study's first frame), with no hop.
    public struct Placement: Sendable {
        public var spot: MotionSpot
        public var memory: [String: MotionSpot] = [:]
        /// How long he has already been idle (ms).
        public var idle = 0.0
        public var welcome = false
        public var welcomeKind: WelcomeKind?
        public var hadWelcome = false
        public var glances = 0
        public var glanceAt: Double?
        public var breathAt: Double?
        public var sitting = false
        public var noSit = false
        public var noEdge = false
        /// A resting look (eyes only).
        public var gaze: MotionPoint?

        public init(spot: MotionSpot) { self.spot = spot }
    }

    public func place(_ p: Placement, lastInputWillBe lastInput: inout Double, lastTapWillBe lastTap: inout Double) {
        anchor = p.spot
        mode = .attached
        scale = scaleFor(p.spot)
        pos = anchorPoint(p.spot)
        z = S(p.spot.surface).layer + 0.2
        memory = ["home": MotionSpot(.stage, x: 195)].merging(p.memory) { $1 }
        memory[world.screenKey] = p.spot
        lastLand = -99_999
        idleSince = now - p.idle
        lastInput = now - p.idle
        lastTap = now - (p.idle != 0 ? p.idle : 99_999)
        welcomeBudget = p.welcome ? 1 : 0
        settings.autoWelcome = p.welcome
        if let k = p.welcomeKind { settings.welcomeKind = k }
        playfulUsed = 0
        visit = Visit(start: now - p.idle, hadWelcome: p.hadWelcome, glances: p.glances, nextGlanceAt: p.glanceAt.map { now + $0 } ?? now + 25_000)
        breathT = p.breathAt.map { now + $0 } ?? -1
        if p.sitting {
            sit.snap(1)
            satThisIdle = true
            activity = "sitting"
        } else {
            sit.snap(0)
            satThisIdle = p.noSit
            activity = "resting"
        }
        edgeThisIdle = p.noEdge
        gazeAt(.user)
        gx.snap(0)
        gy.snap(0)
        if let g = p.gaze {
            gazeAt(.dir, "resting look", point: g)
            gx.snap(g.x)
            gy.snap(g.y)
        }
        vel = .zero
        accHist = []
    }

    /// His pose for the drawing this frame.
    public var pose: MotionPose {
        MotionPose(
            x: pos.x + xOff.x, y: pos.y, scale: scale, opacity: opacity,
            crouch: max(-1.2, crouch.x) + duck.x * 6 + dipSpring.x + dragC.x,
            sit: MotionMath.clamp(sit.x, 0, 1), edge: MotionMath.clamp(edge.x, 0, 1), tuck: MotionMath.clamp(tuck.x, 0, 1),
            squash: squash.x, stretchUp: max(0, stretchUp.x), lean: lean.x, roll: roll.x, facing: facing.x,
            toe: MotionMath.clamp(toe.x, 0, 1), breath: breath, mood: mood, activity: activity,
            listening: listenOn, bracing: brace.on)
    }

    /// His eyes this frame (MV7): where they point, a blink or shut eyes, a squint. Read only.
    public var eyeState: MotionEyeState {
        MotionEyeState(gazeX: gx.x, gazeY: gy.x, closed: MotionMath.clamp(max(blink, shut.x), 0, 1),
                       squint: MotionMath.clamp(squint.x, 0, 1))
    }

    /// The reference's listening-pose test (an arm at the ear and the head rolled).
    public var looksLikeListening: Bool { armR1.x > 100 && armR2.x > 110 && roll.x > 3 }

    var isGesturing: Bool { gesture != nil }

    public var squashAmount: Double { squash.x }
    public var slideOffset: Double { xOff.x }

    // MARK: For the app's clock (MV3): read only, they change nothing

    /// The gesture playing now ("wave", "stretch", "welcome", …) and how long it has played (ms).
    public var gestureName: String? { gesture?.kind.rawValue }
    /// Waiting for a reply on Talk, past 600 ms (motion v2, MV5: the thinking pose).
    public var isThinking: Bool { thinking != nil }
    public var gestureElapsed: Double { gesture?.t ?? 0 }

    /// Breathing now: the phase in breaths since it started (0 ..< 3), nil when not breathing.
    public var breathPhase: Double? {
        breath != 0 && breathT > 0 ? (now - breathT) / 4200 : nil
    }

    /// Nothing about him changes until `nextDue` unless the screen calls in: he is standing on a
    /// surface, not breathing or gesturing, and every spring has come to rest. The app stops its
    /// display link then (the plan: the link runs only while he moves).
    public var isStill: Bool {
        guard mode == .attached, flight == nil, shuf == nil, gesture == nil, micro == nil, homeTouch == nil,
              !ducking, blinkT < 0, opacity >= 1, !justLanded,
              pendingStepOff == nil, pendingTransfer == nil, !pendingPickup, !brace.on else { return false }
        if breath != 0 { return false }
        let springs = [crouch, duck, dipSpring, dragC, sit, edge, lean, roll, facing, gx, gy,
                       armL1, armL2, armR1, armR2, tuck, squash, stretchUp, xOff, toe, squint, shut]
        for s in springs where s.x != s.target || s.v != 0 || s.force != 0 { return false }
        // Surface dips decay without being snapped; at rest within the springs' own tolerance.
        for (_, s) in dips where abs(s.x) >= 0.003 || abs(s.v) >= 0.02 { return false }
        return true
    }

    /// The next moment (engine time, ms) his state changes by itself: a timer, a breath starting,
    /// a reaction or mood ending, calm mode releasing, Home's daily welcome, glance or 15 s sit.
    /// Nil: nothing is due; only the screen can move him.
    public var nextDue: Double? {
        var due = timers.map(\.at)
        let breathes = !settings.reduceMotion && !settings.lowPower && !settings.noBreath
        if breathes, breathT > now { due.append(breathT) }
        if let r = reaction { due.append(r.until) }
        if moodUntil != 0 { due.append(moodUntil) }
        if calm { due.append(lastChange + MotionTiming.calmQuiet + 1) }
        if thinking != nil { due.append(now + 16) }
        if mode == .attached, let a = anchor, a.surface == .stage, host != nil, world.isOnHome {
            if settings.autoWelcome, welcomeBudget > 0 { due.append(now + 16) }
            if !satThisIdle, !settings.reduceMotion {
                due.append(max(idleSince, world.lastInput, lastLand) + 15_001)
            }
            if visit.glances < 3, !settings.lowPower { due.append(visit.nextGlanceAt) }
        }
        return due.min()
    }
}
