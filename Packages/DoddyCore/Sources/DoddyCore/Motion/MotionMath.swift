import Foundation

// Motion v2 (docs/design/MOTION_V2_PLAN.md, MV1): the maths of Doddy's movement, ported from the
// owner's reference engine (`design/motion-v2/reference/engine-core.js`). Units are iPhone points
// and milliseconds of simulation time, so 60 Hz and 120 Hz produce the same path. Nothing here
// draws anything; the app turns the engine's numbers into whole-picture transforms of the
// owner's pack art (owner answer to Q7, 18 Oct 2026).

/// A point in screen points. y grows downwards.
public struct MotionPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = MotionPoint(x: 0, y: 0)
}

/// Small numeric helpers with the reference's exact semantics.
public enum MotionMath {
    public static func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double {
        v < a ? a : v > b ? b : v
    }

    public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    public static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = clamp((x - e0) / (e1 - e0), 0, 1)
        return t * t * (3 - 2 * t)
    }

    public static func hyp(_ x: Double, _ y: Double) -> Double {
        (x * x + y * y).squareRoot()
    }

    /// JavaScript's `Math.sign`: -1, 0 or 1 (NaN becomes 0, as `Math.sign(x) || 0` does).
    public static func sign(_ v: Double) -> Double {
        v > 0 ? 1 : v < 0 ? -1 : 0
    }

    /// The reference's `fmt`: "0" for |v| < 0.5 with no decimals, otherwise JavaScript's
    /// `toFixed` (which rounds an exact tie away from zero, unlike printf).
    public static func format(_ v: Double, digits: Int = 0) -> String {
        if abs(v) < 0.5 && digits == 0 { return "0" }
        return toFixed(v, digits)
    }

    static func toFixed(_ v: Double, _ digits: Int) -> String {
        let p = pow(10, Double(digits))
        let m = abs(v) * p
        if m - m.rounded(.down) == 0.5, (m / p) == abs(v) {
            // An exact tie in binary: JavaScript rounds it up, printf would round to even.
            let r = (m.rounded(.down) + 1) / p
            return String(format: "%.\(digits)f", v < 0 ? -r : r)
        }
        return String(format: "%.\(digits)f", v)
    }
}

/// SwiftUI-style spring (response in seconds, damping fraction), integrated with the
/// reference's fixed 4 ms semi-implicit Euler substeps so both produce the same numbers.
public final class MotionSpring {
    public var x: Double
    public var v: Double = 0
    public var target: Double
    /// An external force (the weight response pushes the crouch with it).
    public var force: Double = 0
    public private(set) var response: Double = 0.3
    public private(set) var damping: Double = 0.8
    private(set) var k: Double = 0
    private(set) var c: Double = 0

    public init(_ x: Double = 0, response: Double = 0.3, damping: Double = 0.8) {
        self.x = x
        self.target = x
        set(response, damping)
    }

    @discardableResult
    public func set(_ response: Double, _ damping: Double) -> MotionSpring {
        self.response = response
        self.damping = damping
        let w = (2 * Double.pi) / response
        k = w * w
        c = 2 * damping * w
        return self
    }

    /// Advances `dt` seconds.
    public func step(_ dt: Double) {
        if dt <= 0 { return }
        let n = max(1, (dt / 0.004).rounded(.up))
        let h = dt / n
        var i = 0.0
        while i < n {
            let a = -k * (x - target) - c * v + force
            v += a * h
            x += v * h
            i += 1
        }
    }

    public func snap(_ value: Double) {
        x = value
        v = 0
        target = value
    }

    public var isResting: Bool { abs(x - target) < 0.01 && abs(v) < 0.05 }

    /// Where this spring will be `dt` seconds from now, with the same integrator, without moving it.
    public func ahead(_ dt: Double) -> Double {
        if dt <= 0 { return x }
        var x = self.x, v = self.v
        let n = max(1, (dt / 0.004).rounded(.up))
        let h = dt / n
        var i = 0.0
        while i < n {
            let a = -k * (x - target) - c * v + force
            v += a * h
            x += v * h
            i += 1
        }
        return x
    }
}

/// The reference's deterministic random numbers (mulberry32), used only to spread Home glances.
public struct MotionRandom: Sendable {
    private var state: UInt32

    public init(seed: UInt32) { state = seed }

    public mutating func next() -> Double {
        state = state &+ 0x6D2B_79F5
        var t = (state ^ (state >> 15)) &* (1 | state)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

/// The brief's timing numbers (`M` in the reference), in milliseconds unless noted.
public enum MotionTiming {
    /// Crouch before a hop: 80 ms; 40 ms after a landing or when his surface moves his way;
    /// 140 ms from sitting. 0 ms when his surface is about to drop away.
    public static let anticipation = 80.0
    public static let anticipationFromLanding = 40.0
    public static let anticipationFromSit = 140.0
    /// Flight time for a hop of distance `d` with vertical change `dy`.
    public static func flight(_ d: Double, _ dy: Double) -> Double {
        MotionMath.clamp(220 + 0.4 * d + 0.2 * abs(dy), 260, 420)
    }
    /// Apex height above the higher end of the hop; flatter when stepping down more than 40 pt.
    public static func apex(_ d: Double, _ dy: Double) -> Double {
        dy > 40 ? MotionMath.clamp(6 + 0.04 * d, 10, 18) : MotionMath.clamp(12 + 0.08 * d, 16, 32)
    }
    /// Mid-air re-target flight time.
    public static func retargetFlight(_ d: Double) -> Double {
        MotionMath.clamp(180 + 0.5 * d, 200, 360)
    }
    public static let maxAirborne = 520.0
    public static let contact = 60.0
    public static let settle = 280.0
    /// Calm mode: 3 tab changes within 900 ms; released after 350 ms of quiet.
    public static let calmChanges = 3
    public static let calmWindow = 900.0
    public static let calmQuiet = 350.0
    /// Reduce Motion: fade out, one invisible 20 ms frame, fade in.
    public static let fadeOut = 120.0
    public static let fadeIn = 180.0
    public static let fadeGap = 20.0
    public static let shuffleOut = 90.0
    public static let shuffleIn = 120.0
    /// Tab content cross-fade in the reference (the app commits instantly).
    public static let uiFade = 120.0
    /// Shuffle: one side-step per 110 ms, then 120 ms settle.
    public static let step = 110.0
    public static let stepSettle = 120.0
    /// Press and hold on him; how far a touch may move and still be a tap.
    public static let hold = 450.0
    public static let tapSlop = 10.0
    /// Scroll riding: lily-pad hops only under 300 pt/s; the list counts as settled once it has
    /// moved slower than 150 pt/s for 200 ms; at most one lily-pad hop per 1.2 s; he looks
    /// 150 ms ahead to see his rule leaving the safe band.
    public static let lilySlow = 300.0
    public static let lilySettleSpeed = 150.0
    public static let lilySettleFor = 200.0
    public static let lilyGap = 1200.0
    public static let lilyLook = 150.0
    /// The latest a tab hop may land after the tap (DECISIONS.md "Tab hop to Memories").
    public static let tabHopLatest = 480.0
}

/// The flight path: a cubic Hermite curve from `p0` to `p1` with tangents `m0`, `m1`, plus a
/// parabolic lift `h` that peaks at mid-flight.
public struct MotionFlight: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case hop, retarget, flick
    }

    public var p0: MotionPoint
    public var p1: MotionPoint
    public var t0: Double
    public var m0: MotionPoint
    public var m1: MotionPoint
    public var h: Double
    /// Flight time in ms.
    public var T: Double
    public var t: Double = 0
    public var s0: Double
    public var s1: Double
    public var kind: Kind

    public init(p0: MotionPoint, p1: MotionPoint, t0: Double, m0: MotionPoint, m1: MotionPoint, h: Double, T: Double, s0: Double, s1: Double, kind: Kind) {
        self.p0 = p0
        self.p1 = p1
        self.t0 = t0
        self.m0 = m0
        self.m1 = m1
        self.h = h
        self.T = T
        self.s0 = s0
        self.s1 = s1
        self.kind = kind
    }

    /// Position at progress `s` (0…1).
    public func point(_ s: Double) -> MotionPoint {
        let s2 = s * s, s3 = s2 * s
        let h00 = 2 * s3 - 3 * s2 + 1, h10 = s3 - 2 * s2 + s, h01 = -2 * s3 + 3 * s2, h11 = s3 - s2
        return MotionPoint(
            x: h00 * p0.x + h10 * m0.x + h01 * p1.x + h11 * m1.x,
            y: h00 * p0.y + h10 * m0.y + h01 * p1.y + h11 * m1.y - 4 * h * s * (1 - s))
    }

    /// Velocity in pt/s at progress `s`.
    public func velocity(_ s: Double) -> MotionPoint {
        let s2 = s * s
        let d00 = 6 * s2 - 6 * s, d10 = 3 * s2 - 4 * s + 1, d01 = -6 * s2 + 6 * s, d11 = 3 * s2 - 2 * s
        let T = self.T / 1000
        return MotionPoint(
            x: (d00 * p0.x + d10 * m0.x + d01 * p1.x + d11 * m1.x) / T,
            y: (d00 * p0.y + d10 * m0.y + d01 * p1.y + d11 * m1.y - 4 * h * (1 - 2 * s)) / T)
    }

    /// The lift that makes the path's highest point `apex` points above the higher end.
    public static func lift(from p0: MotionPoint, to p1: MotionPoint, apex A: Double) -> Double {
        let c = p1.y - p0.y, m = min(p0.y, p1.y), K = p0.y - m + A
        return ((c + 2 * K) + 2 * max(0, K * (K + c)).squareRoot()) / 4
    }
}
