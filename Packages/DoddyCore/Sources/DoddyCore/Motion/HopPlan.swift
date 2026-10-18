import Foundation

/// One hop, as planned and as flown (rule 5: free travel is one hop). The engine fills it in
/// as the hop happens: the request, the crouch, take-off, the flight and the contact. Tests
/// compare it with the reference clips' telemetry (`design/motion-v2/telemetry/*.json`, "hops").
public struct HopPlan: Equatable, Sendable {
    /// When the hop was requested, and the tap that caused it.
    public var requestedAt: Double
    public var tapAt: Double
    public var why: String
    public var from: String
    public var to: String
    /// Crouch length chosen at the request (ms).
    public var anticipation: Double
    /// Scale at take-off and on the target surface.
    public var startScale: Double
    public var endScale: Double
    /// Caused by a tab tap: such hops are capped to land by `MotionTiming.tabHopLatest`.
    public var isTabHop: Bool
    /// The formula's flight time when the tab cap shortened it (rounded), nil if not capped.
    public var cappedFrom: Double?
    public var takeoffAt: Double?
    /// The crouch as flown: take-off minus request (ms).
    public var crouch: Double?
    public var flightTime: Double?
    public var distance: Double?
    public var apex: Double?
    public var start: MotionPoint?
    public var end: MotionPoint?
    public var contactAt: Double?
    public var contactAfterTap: Double?
    /// Vertical speed at contact (pt/s, rounded).
    public var impact: Double?
    /// Contact squash in points at his scale (2.2–4.4 pt × scale).
    public var squash: Double?
    public var landScale: Double?
    /// Reversed during the crouch: he never left the ground.
    public var cancelledAt: Double?
    public var reaimedInCrouch = false
    public var retargets: Int?
    public var retargetAt: Double?
    public var retargetFlightTime: Double?
    /// A hop in place (a flick or the welcome-back hop).
    public var inPlace = false

    public init(requestedAt: Double, tapAt: Double, why: String, from: String, to: String, anticipation: Double, startScale: Double, endScale: Double, isTabHop: Bool) {
        self.requestedAt = requestedAt
        self.tapAt = tapAt
        self.why = why
        self.from = from
        self.to = to
        self.anticipation = anticipation
        self.startScale = startScale
        self.endScale = endScale
        self.isTabHop = isTabHop
    }

    // MARK: Planning (pure functions of the brief's numbers)

    /// Crouch length before take-off: 0 when told to go at once or when his surface is about
    /// to drop away; 140 ms from sitting; 40 ms just after a landing or when his surface moves
    /// his way; 80 ms otherwise.
    public static func anticipation(immediate: Bool, leaving: Bool, fromSit: Bool, fromLanding: Bool, surfaceMovesHisWay: Bool) -> Double {
        if immediate || leaving { return 0 }
        if fromSit { return MotionTiming.anticipationFromSit }
        if fromLanding || surfaceMovesHisWay { return MotionTiming.anticipationFromLanding }
        return MotionTiming.anticipation
    }

    /// The longest flight a tab hop may take so it lands by 480 ms after the tap (never under
    /// 260 ms). Other hops: 420 ms, the formula's own ceiling.
    public static func flightCap(isTabHop: Bool, tapAt: Double, now: Double) -> Double {
        isTabHop ? max(260, MotionTiming.tabHopLatest - (now - tapAt)) : 420
    }

    /// Aims at where the target will be at touchdown: three passes of "flight time for this
    /// distance, then where the spot will be after that long".
    public static func aim(from p0: MotionPoint, predicted: MotionPoint, timeFor: (_ distance: Double, _ dy: Double) -> Double, pointAt: (_ dtSeconds: Double) -> MotionPoint) -> (end: MotionPoint, time: Double) {
        var p1 = predicted
        var T = 0.0
        for _ in 0..<3 {
            T = timeFor(MotionMath.hyp(p1.x - p0.x, p1.y - p0.y), p1.y - p0.y)
            p1 = pointAt(T / 1000)
        }
        return (p1, T)
    }

    /// Contact squash in rig units (2.2–4.4 pt at 1.0×) for a landing at `vy` pt/s.
    public static func contactSquash(vy: Double) -> Double {
        let impact = MotionMath.clamp(max(0, vy) / 1800, 0, 1)
        return 2.2 + 2.2 * impact
    }

    /// Size during a flight: start + (end − start) × smoothstep(0.15, 0.9, progress).
    public static func scale(from s0: Double, to s1: Double, progress s: Double) -> Double {
        s0 + (s1 - s0) * MotionMath.smoothstep(0.15, 0.9, s)
    }
}
