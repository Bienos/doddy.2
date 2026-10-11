import Foundation

// The opening (ADR-225): a pen sketches Doddy in, he dribbles, crouches, hops and shoots, the
// ball arcs into the ring ("SWISH!", confetti), he pops up ready to talk, and then jumps into
// his place on Home: the last frame puts him exactly where Home's own picture of him
// is, so the hand-over has no jump (`OpeningHandover`). Everything in this file is a pure
// function of time, so the renderer only draws what `OpeningScene.frame(at:)` returns and
// decides nothing itself: no timers, no state, no side effects. The policy that says whether
// the opening plays at all, and whether a conversation starts afterwards, is `OpeningPolicy`.
// The drawings themselves come from `SVGPoseReader` (OpeningArt.swift).

/// A point on the opening's stage. Units: the screen's width is 1; y grows downwards from the
/// top of a stage `OpeningScene.stageHeight` tall, which the renderer centres on the screen.
public struct StagePoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static func lerp(_ a: StagePoint, _ b: StagePoint, _ p: Double) -> StagePoint {
        StagePoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p)
    }

    /// Quadratic Bézier: from `a` to `c`, pulled towards `b`.
    public static func bezier(_ a: StagePoint, _ b: StagePoint, _ c: StagePoint, _ u: Double) -> StagePoint {
        let v = 1 - u
        return StagePoint(
            x: v * v * a.x + 2 * v * u * b.x + u * u * c.x,
            y: v * v * a.y + 2 * v * u * b.y + u * u * c.y)
    }

    /// Direction of travel along that curve, in radians (0 = right, π/2 = down).
    public static func bezierHeading(_ a: StagePoint, _ b: StagePoint, _ c: StagePoint, _ u: Double) -> Double {
        let dx = 2 * (1 - u) * (b.x - a.x) + 2 * u * (c.x - b.x)
        let dy = 2 * (1 - u) * (b.y - a.y) + 2 * u * (c.y - b.y)
        return atan2(dy, dx)
    }
}

public struct StageRect: Equatable, Sendable {
    public var origin: StagePoint
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        origin = StagePoint(x: x, y: y)
        self.width = width
        self.height = height
    }

    public var center: StagePoint { StagePoint(x: origin.x + width / 2, y: origin.y + height / 2) }
    /// Where the feet are: squash and stretch happen about this point.
    public var bottomCenter: StagePoint { StagePoint(x: origin.x + width / 2, y: origin.y + height) }
}

/// The poses, in the order they are shown. The first four are the supplied v1.3-r1 basketball
/// drawings, read as strokes (`SVGPoseReader`); `ready` is the app's own listening artwork
/// (`UploadedDoddy_Listening`), the same one Home then shows.
public enum OpeningPose: Hashable, Sendable, CaseIterable {
    case dribble, gather, shot, followThrough, ready

    /// The bundled SVG's file name (without extension), or nil for the ready artwork.
    public var svgResourceName: String? {
        switch self {
        case .dribble: "doddy-pose-basketball-dribble-light-v1.3-r1"
        case .gather: "doddy-pose-basketball-gather-light-v1.3-r1"
        case .shot: "doddy-pose-basketball-shot-light-v1.3-r1"
        case .followThrough: "doddy-pose-basketball-follow-through-light-v1.3-r1"
        case .ready: nil
        }
    }

    /// The group in the drawing that holds the ball; the opening draws its own instead.
    public static let ballGroup = "basketball"
}

/// Where the ball is drawn inside a pose's artwork, as fractions of the square image, so the
/// animated ball starts and ends exactly in the hand. Measured on the supplied files (and
/// checked against the vector ball in the tests).
public struct BallInArt: Equatable, Sendable {
    public let centerX: Double
    public let centerY: Double
}

public struct OpeningCamera: Equatable, Sendable {
    public var scale: Double
    /// The stage point that stays put while the scale changes.
    public var anchor: StagePoint
    /// A short shake on the score, in stage units; zero otherwise.
    public var shake: StagePoint
}

public enum ParticleKind: Equatable, Sendable {
    /// A puff where the ball or the feet hit the floor.
    case dust
    case confettiOrange, confettiInk
}

public struct OpeningParticle: Equatable, Sendable {
    public var center: StagePoint
    /// Diameter (dust) or long side (confetti), stage units.
    public var size: Double
    /// Radians.
    public var rotation: Double
    public var opacity: Double
    public var kind: ParticleKind
}

public struct OpeningDoddy: Equatable, Sendable {
    /// The drawing shown. Outside a change of pose `nextPose` is the same and `blend` is 0.
    public var pose: OpeningPose
    /// The drawing coming in, at opacity `blend`, while `pose` fades out.
    public var nextPose: OpeningPose
    public var blend: Double
    /// How much of the drawing the pen has drawn so far (0…1); 1 once the sketch is done.
    /// Per-stroke progress comes from `OpeningScene.strokeProgress(index:count:at:)`.
    public var sketch: Double
    /// How far the whole figure is lifted (the hop into the shot), in stage units.
    public var hop: Double
    /// Squash and stretch about the feet: (1, 1) at rest; wider and shorter in the crouch,
    /// narrower and taller in the jump.
    public var squashX: Double
    public var squashY: Double
    /// The ready artwork's pop: 0 before it appears, overshooting a little past 1, then 1.
    public var readyPop: Double
}

public struct OpeningBall: Equatable, Sendable {
    public var center: StagePoint
    public var radius: Double
    /// Vertical scale on the floor: 1 round, less flattened.
    public var squash: Double
    /// Stretch along the direction of travel, 1 or more (a cartoon speed cue).
    public var stretch: Double
    /// Direction of travel, radians (0 = right, π/2 = down), for the stretch.
    public var heading: Double
    /// Radians, clockwise.
    public var spin: Double
    public var scale: Double
    public var opacity: Double
    /// Earlier positions along the flight, nearest first, drawn as fading ghosts.
    public var trail: [StagePoint]
}

public struct OpeningBurst: Equatable, Sendable {
    public var opacity: Double
    public var scale: Double
    /// How far the rays around the ring have shot out (0…1).
    public var rays: Double
    /// Ring wobble, radians.
    public var ringWobble: Double
}

/// Everything the renderer draws at one moment.
public struct OpeningFrame: Equatable, Sendable {
    public var camera: OpeningCamera
    public var doddy: OpeningDoddy
    public var ball: OpeningBall
    /// Vertical stretch of the net, 1 at rest.
    public var netStretch: Double
    public var burst: OpeningBurst
    public var particles: [OpeningParticle]
    public var hintOpacity: Double
    /// The court, hoop, burst and particles: they fade at the hand-over.
    public var setOpacity: Double
    /// The paper behind everything. As it fades, Home shows through; Doddy is drawn separately
    /// and is never faded while he has a place on Home to land in (`OpeningHandover`).
    public var backdropOpacity: Double
    public var scored: Bool
}

/// Fixed positions on the stage. The scene is composed for a 1 × 2 stage: on a tall iPhone a
/// little canvas shows above and below it, on a short one the top and bottom edges are cropped.
public enum OpeningLayout {
    public static let floorY = 1.42
    /// The square the basketball drawings fill. Its bottom is on the floor.
    public static let doddy = StageRect(x: 0.11, y: 0.84, width: 0.58, height: 0.58)
    /// The ready artwork (2:3), centred under the same spot, placed so its feet (not the image's
    /// transparent bottom margin) stand on the floor.
    public static let ready = StageRect(x: 0.1665, y: 0.7977, width: 0.467, height: 0.70)
    /// In `UploadedDoddy_Listening` (1024 × 1536), the soles end at 88.9% of the height
    /// (measured on the image's alpha).
    public static let readyFeetFraction = 0.889
    public static let ringCenter = StagePoint(x: 0.80, y: 0.62)
    public static let ringWidth = 0.12
    public static let ringHeight = 0.036
    public static let netDepth = 0.10
    public static let backboard = StageRect(x: 0.865, y: 0.46, width: 0.03, height: 0.22)
    /// Free-throw arc: a half circle on the floor under the hoop.
    public static let keyArcRadius = 0.30
    /// "SWISH!" and its rays, centred here.
    public static let burstAt = StagePoint(x: 0.64, y: 0.47)
    public static let burstRayLength = 0.09
    /// The flight's pull point: above and between the hand and the ring.
    public static let flightControl = StagePoint(x: 0.60, y: 0.30)

    /// Nil for a pose that holds no ball.
    public static func ballInArt(_ pose: OpeningPose) -> BallInArt? {
        switch pose {
        case .dribble: BallInArt(centerX: 0.728, centerY: 0.720)
        case .gather: BallInArt(centerX: 0.597, centerY: 0.578)
        case .shot: BallInArt(centerX: 0.724, centerY: 0.156)
        case .followThrough, .ready: nil
        }
    }

    /// The ball's resting spot on the stage for a pose that holds it (the hand); nil otherwise.
    public static func hand(_ pose: OpeningPose) -> StagePoint? {
        ballInArt(pose).map { StagePoint(x: doddy.origin.x + $0.centerX * doddy.width, y: doddy.origin.y + $0.centerY * doddy.height) }
    }

    public static var dribbleHand: StagePoint { hand(.dribble) ?? doddy.center }
    public static var gatherHand: StagePoint { hand(.gather) ?? doddy.center }
    public static var shotHand: StagePoint { hand(.shot) ?? doddy.center }

    /// The ball's size: the vector ball is 0.064 of the drawing when dribbled; held up for the
    /// shot it is further away, so a little smaller.
    public static let lowBallRadius = 0.037
    public static let highBallRadius = 0.031
}

public enum OpeningScene {
    public static let stageHeight = 2.0

    /// The timeline, in seconds from the start. Quick on purpose: 2.3 s, and a tap ends it.
    public enum Beat {
        /// The pen draws the dribble pose, one stroke after another.
        public static let sketchStart = 0.00
        public static let sketchEnd = 0.50
        /// How long each stroke takes; strokes overlap, so the whole sketch fits the window.
        public static let strokeDuration = 0.14
        /// The ball pops into the hand and bounces twice, fast.
        public static let dribbleStart = 0.42
        public static let dribbleEnd = 0.78
        public static let bouncePeriod = 0.18
        /// Dribble → gather: the crouch (the wind-up), squashed.
        public static let gatherStart = 0.78
        public static let gatherEnd = 0.86
        public static let crouchPeak = 0.88
        /// Gather → shot: up, stretched, and the hop.
        public static let shotStart = 0.94
        public static let shotEnd = 1.00
        public static let hopStart = 0.96
        public static let hopEnd = 1.32
        public static let hopHeight = 0.06
        public static let stretchPeak = 1.02
        /// The ball leaves the hand; the arm follows through.
        public static let release = 1.04
        public static let followStart = 1.04
        public static let followEnd = 1.12
        /// The ball reaches the ring.
        public static let score = 1.40
        public static let throughNet = 1.52
        /// "SWISH!", rays, the ring wobbles.
        public static let burstStart = 1.40
        public static let burstEnd = 1.90
        /// Follow-through → ready, with a pop; the camera is back to 1:1 by `cameraSettled`.
        public static let readyStart = 1.58
        public static let readyEnd = 1.76
        public static let cameraSettled = 1.74
        /// The hand-over: the court fades, Home shows through, and Doddy jumps along an arc into
        /// his place on Home, landing with a squash.
        public static let handoverStart = 1.95
        public static let arrive = 2.25
        public static let end = 2.40
        /// The still picture (Reduce Motion): Doddy already in his place, the hello, then the paper fades.
        public static let stillEnd = 1.10
        /// How long a dust puff and the confetti last.
        public static let puffLength = 0.30
        public static let confettiLength = 0.90
    }

    public static func duration(reducedMotion: Bool) -> TimeInterval {
        reducedMotion ? Beat.stillEnd : Beat.end
    }

    public static func isFinished(at t: TimeInterval, reducedMotion: Bool) -> Bool {
        t >= duration(reducedMotion: reducedMotion)
    }

    public static func frame(at t: TimeInterval, reducedMotion: Bool) -> OpeningFrame {
        reducedMotion ? still(at: max(0, t)) : animated(at: max(0, t))
    }

    /// How much of stroke `index` of `count` the pen has drawn at `t` (0…1). Strokes start one
    /// after another across the sketch window and each takes `Beat.strokeDuration`.
    public static func strokeProgress(index: Int, count: Int, at t: Double) -> Double {
        guard count > 0 else { return 1 }
        let span = Beat.sketchEnd - Beat.sketchStart - Beat.strokeDuration
        let start = Beat.sketchStart + (count > 1 ? span * Double(index) / Double(count - 1) : 0)
        return Ease.out(Ease.progress(t, start, start + Beat.strokeDuration))
    }

    // MARK: - The animated opening

    static func animated(at t: Double) -> OpeningFrame {
        let hop = hop(at: t)
        let backdrop = 1 - Ease.inOut(Ease.progress(t, Beat.handoverStart, Beat.arrive))
        return OpeningFrame(
            camera: camera(at: t),
            doddy: figure(at: t, hop: hop),
            ball: ball(at: t, hop: hop),
            netStretch: 1 + 0.45 * sin(.pi * Ease.progress(t, Beat.score, Beat.score + 0.30)),
            burst: burst(at: t),
            particles: dust(at: t) + confetti(at: t),
            hintOpacity: Ease.progress(t, 0.30, 0.50) * backdrop,
            setOpacity: 1 - Ease.inOut(Ease.progress(t, Beat.handoverStart, Beat.handoverStart + 0.20)),
            backdropOpacity: backdrop,
            scored: t >= Beat.score)
    }

    /// Dust where the ball hits the floor (twice) and where Doddy lands from the hop.
    static func dust(at t: Double) -> [OpeningParticle] {
        let floor = OpeningLayout.floorY
        let puffs: [(Double, Double)] = [
            (Beat.dribbleStart + Beat.bouncePeriod * 0.5, OpeningLayout.dribbleHand.x),
            (Beat.dribbleStart + Beat.bouncePeriod * 1.5, OpeningLayout.dribbleHand.x),
            (Beat.hopEnd, OpeningLayout.doddy.bottomCenter.x),
        ]
        var result: [OpeningParticle] = []
        for (time, x) in puffs {
            let age = t - time
            guard age >= 0, age < Beat.puffLength else { continue }
            let u = age / Beat.puffLength
            for i in 0..<5 {
                let dir = -1 + 2 * Double(i) / 4
                result.append(OpeningParticle(
                    center: StagePoint(
                        x: x + dir * 0.06 * Ease.out(u),
                        y: floor - 0.008 - 0.02 * Ease.out(u) * (1 - abs(dir) * 0.5)),
                    size: 0.012 + 0.018 * u, rotation: 0, opacity: 0.55 * (1 - u), kind: .dust))
            }
        }
        return result
    }

    public static let confettiCount = 16

    /// Confetti thrown up out of the ring on the score, falling back with gravity. The same every
    /// time: each piece's direction, speed, spin and size come from its index.
    static func confetti(at t: Double) -> [OpeningParticle] {
        let age = t - Beat.score
        guard age >= 0, age < Beat.confettiLength else { return [] }
        let ring = OpeningLayout.ringCenter
        return (0..<confettiCount).map { i in
            let angle = -Double.pi / 2 + (-0.9 + 1.8 * unit(i, 1))
            let speed = 0.5 + 0.4 * unit(i, 2)
            return OpeningParticle(
                center: StagePoint(
                    x: ring.x + cos(angle) * speed * age,
                    y: ring.y + sin(angle) * speed * age + 0.5 * 1.6 * age * age),
                size: 0.012 + 0.006 * unit(i, 4),
                rotation: (unit(i, 3) * 2 - 1) * 12 * age,
                opacity: 1 - Ease.progress(age, 0.6, Beat.confettiLength),
                kind: i.isMultiple(of: 2) ? .confettiOrange : .confettiInk)
        }
    }

    /// A fixed pseudo-random number in 0..<1 for piece `i` (xorshift), so the confetti is the same each time.
    static func unit(_ i: Int, _ salt: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: i &* 7919 &+ salt &* 104_729 &+ 1)
        for _ in 0..<3 {
            x ^= x << 13
            x ^= x >> 7
            x ^= x << 17
        }
        return Double(x % 10_000) / 10_000
    }

    static func hop(at t: Double) -> Double {
        Beat.hopHeight * sin(.pi * Ease.progress(t, Beat.hopStart, Beat.hopEnd))
    }

    /// Which drawing is up, how much of it is sketched, and its squash and stretch.
    static func figure(at t: Double, hop: Double) -> OpeningDoddy {
        let changes: [(from: OpeningPose, to: OpeningPose, start: Double, end: Double)] = [
            (.dribble, .gather, Beat.gatherStart, Beat.gatherEnd),
            (.gather, .shot, Beat.shotStart, Beat.shotEnd),
            (.shot, .followThrough, Beat.followStart, Beat.followEnd),
            (.followThrough, .ready, Beat.readyStart, Beat.readyEnd),
        ]
        var pose = OpeningPose.dribble
        var next = pose
        var blend = 0.0
        for change in changes {
            // At the very start of a change nothing of the next drawing shows yet.
            if t <= change.start { break }
            if t < change.end {
                pose = change.from
                next = change.to
                blend = Ease.inOut(Ease.progress(t, change.start, change.end))
                break
            }
            pose = change.to
            next = change.to
        }
        // The crouch: wide and short, peaking as the gather settles; then the jump: tall and narrow.
        let crouch = sin(.pi * Ease.progress(t, Beat.gatherStart, Beat.crouchPeak + (Beat.crouchPeak - Beat.gatherStart)))
        let stretch = sin(.pi * Ease.progress(t, Beat.shotStart, Beat.stretchPeak + (Beat.stretchPeak - Beat.shotStart)))
        let readyPop = Ease.backOut(Ease.progress(t, Beat.readyStart, Beat.readyEnd))
        return OpeningDoddy(
            pose: pose, nextPose: next, blend: blend,
            sketch: Ease.progress(t, Beat.sketchStart, Beat.sketchEnd),
            hop: hop,
            squashX: 1 + 0.10 * crouch - 0.07 * stretch,
            squashY: 1 - 0.12 * crouch + 0.10 * stretch,
            readyPop: t <= Beat.readyStart ? 0 : readyPop)
    }

    /// Wide for the sketch, a punch in for the shot, a drift after the ball, a shake on the
    /// score, then back to 1:1 before the hand-over, so the hand-over happens on the plain screen.
    static func camera(at t: Double) -> OpeningCamera {
        let punch = Ease.out(Ease.progress(t, Beat.gatherStart, Beat.shotEnd))
        let follow = Ease.inOut(Ease.progress(t, Beat.shotEnd, 1.45))
        let settle = Ease.inOut(Ease.progress(t, Beat.readyStart, Beat.cameraSettled))
        let wide = StagePoint(x: 0.50, y: 1.10)
        let onDoddy = StagePoint(x: 0.44, y: 1.08)
        let afterBall = StagePoint(x: 0.52, y: 1.00)
        let scale = lerp(lerp(lerp(0.82, 1.18, punch), 1.12, follow), 1.0, settle)
        let anchor = StagePoint.lerp(StagePoint.lerp(StagePoint.lerp(wide, onDoddy, punch), afterBall, follow), wide, settle)
        let since = t - Beat.score
        let decay = since < 0 ? 0 : 1 - Ease.progress(since, 0, 0.28)
        let shake = StagePoint(x: 0.006 * sin(2 * .pi * 23 * since) * decay, y: 0.005 * sin(2 * .pi * 17 * since + 1) * decay)
        return OpeningCamera(scale: scale, anchor: anchor, shake: shake)
    }

    /// Where the ball leaves the hand: the shot hand, lifted by the hop at that moment.
    public static var releasePoint: StagePoint {
        let hand = OpeningLayout.shotHand
        return StagePoint(x: hand.x, y: hand.y - hop(at: Beat.release))
    }

    static func ball(at t: Double, hop: Double) -> OpeningBall {
        let turns = 3.0 * 2 * Double.pi
        let low = OpeningLayout.lowBallRadius, high = OpeningLayout.highBallRadius
        let down = Double.pi / 2
        func still(_ center: StagePoint, radius: Double, scale: Double = 1, opacity: Double = 1) -> OpeningBall {
            OpeningBall(center: center, radius: radius, squash: 1, stretch: 1, heading: down, spin: 0, scale: scale, opacity: opacity, trail: [])
        }
        if t < Beat.dribbleStart {
            return still(OpeningLayout.dribbleHand, radius: low, scale: 0, opacity: 0)
        }
        if t < Beat.dribbleEnd {
            // Pops into the hand, then between the hand and the floor twice: flattened on the
            // floor, stretched when moving fast.
            let pop = Ease.backOut(Ease.progress(t, Beat.dribbleStart, Beat.dribbleStart + 0.10))
            let phase = ((t - Beat.dribbleStart) / Beat.bouncePeriod).truncatingRemainder(dividingBy: 1)
            let drop = 1 - pow(2 * phase - 1, 2)
            let hand = OpeningLayout.dribbleHand
            let bottom = OpeningLayout.floorY - low
            return OpeningBall(
                center: StagePoint(x: hand.x, y: hand.y + (bottom - hand.y) * drop),
                radius: low,
                squash: 1 - 0.28 * Ease.progress(drop, 0.82, 1.0),
                stretch: 1 + 0.18 * abs(2 * phase - 1) * (1 - Ease.progress(drop, 0.82, 1.0)),
                heading: down, spin: 0, scale: pop, opacity: 1, trail: [])
        }
        if t < Beat.shotStart {
            let carried = Ease.out(Ease.progress(t, Beat.gatherStart, Beat.gatherEnd))
            return still(StagePoint.lerp(OpeningLayout.dribbleHand, OpeningLayout.gatherHand, carried), radius: low)
        }
        if t < Beat.release {
            let carried = Ease.out(Ease.progress(t, Beat.shotStart, Beat.shotEnd))
            let held = StagePoint.lerp(OpeningLayout.gatherHand, OpeningLayout.shotHand, carried)
            return still(StagePoint(x: held.x, y: held.y - hop), radius: lerp(low, high, carried))
        }
        if t < Beat.score {
            // In the air: a constant-speed arc, spinning, stretched along its path, ghosts behind.
            let u = Ease.progress(t, Beat.release, Beat.score)
            let start = releasePoint, control = OpeningLayout.flightControl, end = OpeningLayout.ringCenter
            let trail = [0.07, 0.14, 0.21].compactMap { lag -> StagePoint? in
                u - lag > 0 ? StagePoint.bezier(start, control, end, u - lag) : nil
            }
            return OpeningBall(
                center: StagePoint.bezier(start, control, end, u), radius: high, squash: 1,
                stretch: 1.3, heading: StagePoint.bezierHeading(start, control, end, u),
                spin: u * turns, scale: 1 - 0.08 * u, opacity: 1, trail: trail)
        }
        // Through the net and gone.
        let u = Ease.progress(t, Beat.score, Beat.throughNet)
        return still(
            StagePoint(x: OpeningLayout.ringCenter.x, y: OpeningLayout.ringCenter.y + OpeningLayout.netDepth * u),
            radius: high, scale: 0.92, opacity: 1 - Ease.progress(t, Beat.throughNet - 0.08, Beat.throughNet))
    }

    static func burst(at t: Double) -> OpeningBurst {
        let opacity = Ease.progress(t, Beat.burstStart, Beat.burstStart + 0.06) * (1 - Ease.progress(t, Beat.burstEnd - 0.12, Beat.burstEnd))
        let since = t - Beat.burstStart
        let wobble = t < Beat.burstStart ? 0 : 0.08 * sin(since * 2 * .pi * 5) * (1 - Ease.progress(t, Beat.burstStart, Beat.burstStart + 0.45))
        return OpeningBurst(
            opacity: opacity,
            scale: t <= Beat.burstStart ? 0 : 0.3 + 0.7 * Ease.backOut(Ease.progress(t, Beat.burstStart, Beat.burstStart + 0.18)),
            rays: Ease.out(Ease.progress(t, Beat.burstStart, Beat.burstStart + 0.22)),
            ringWobble: wobble)
    }

    // MARK: - The still picture (Reduce Motion)

    /// Doddy already in his place on Home; nothing moves. The paper covers Home
    /// from the first frame and fades at the end, so Home appears around him.
    static func still(at t: Double) -> OpeningFrame {
        let fadeOut = Ease.progress(t, 0.85, Beat.stillEnd)
        let shown = Ease.progress(t, 0.15, 0.40) * (1 - fadeOut)
        return OpeningFrame(
            camera: OpeningCamera(scale: 1, anchor: StagePoint(x: 0.5, y: 1.1), shake: StagePoint(x: 0, y: 0)),
            doddy: OpeningDoddy(pose: .ready, nextPose: .ready, blend: 0, sketch: 1, hop: 0, squashX: 1, squashY: 1, readyPop: 1),
            ball: OpeningBall(center: OpeningLayout.shotHand, radius: OpeningLayout.highBallRadius, squash: 1, stretch: 1, heading: .pi / 2, spin: 0, scale: 1, opacity: 0, trail: []),
            netStretch: 1,
            burst: OpeningBurst(opacity: 0, scale: 0, rays: 0, ringWobble: 0),
            particles: [],
            hintOpacity: shown,
            setOpacity: 0,
            backdropOpacity: 1 - fadeOut,
            scored: false)
    }

    static func lerp(_ a: Double, _ b: Double, _ p: Double) -> Double { a + (b - a) * p }
}

/// Easing, each taking and returning 0…1.
enum Ease {
    /// 0 before `from`, 1 after `to`, linear in between.
    static func progress(_ t: Double, _ from: Double, _ to: Double) -> Double {
        guard to > from else { return t >= to ? 1 : 0 }
        return min(1, max(0, (t - from) / (to - from)))
    }

    static func out(_ p: Double) -> Double { 1 - pow(1 - p, 3) }

    static func inOut(_ p: Double) -> Double {
        p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
    }

    /// Overshoots a little past 1 before settling (a pop).
    static func backOut(_ p: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(p - 1, 3) + c1 * pow(p - 1, 2)
    }
}

// MARK: - The hand-over

/// A box on the screen, in points, in whatever coordinate space the caller uses for both ends.
/// Used for Doddy's ready picture: `height` is the picture's height; it is as wide as the art.
public struct ScreenBox: Equatable, Sendable {
    public var centerX: Double
    public var centerY: Double
    public var height: Double

    public init(centerX: Double, centerY: Double, height: Double) {
        self.centerX = centerX
        self.centerY = centerY
        self.height = height
    }

    public var top: Double { centerY - height / 2 }
}

/// Where the ready Doddy is drawn, and how he is squashed, at one moment.
public struct PlacedDoddy: Equatable, Sendable {
    public var box: ScreenBox
    public var squashX: Double
    public var squashY: Double
    public var opacity: Double
}

/// Doddy's jump from the court into his place on Home. The renderer gives the box his picture
/// fills on Home (measured there); at the end of the opening the picture is in exactly that box,
/// at scale 1, so Home's own picture takes over with no jump.
public enum OpeningHandover {
    /// `UploadedDoddy_Listening` is 1024 × 1536.
    public static let artAspect = 2.0 / 3.0

    /// The ready pose on the court, on a screen `width` × `height` points, with the camera at 1:1
    /// (it is from `Beat.cameraSettled` on). Same placement as `OpeningLayout.ready` on the stage.
    public static func courtBox(screenWidth width: Double, screenHeight height: Double) -> ScreenBox {
        let ready = OpeningLayout.ready
        let top = (height - OpeningScene.stageHeight * width) / 2
        return ScreenBox(centerX: ready.center.x * width, centerY: top + ready.center.y * width, height: ready.height * width)
    }

    /// From `Beat.handoverStart` Doddy leaves `court` along an arc and arrives in `home` at
    /// `Beat.arrive`, then lands with a squash that settles by `Beat.end`. Without a place on Home
    /// (`home` nil) he stays on the court and fades with the paper. Under Reduce Motion he is in
    /// his place from the start.
    public static func place(court: ScreenBox, home: ScreenBox?, at t: Double, reducedMotion: Bool) -> PlacedDoddy {
        guard let home else {
            let frame = OpeningScene.frame(at: t, reducedMotion: reducedMotion)
            return PlacedDoddy(box: court, squashX: 1, squashY: 1, opacity: frame.backdropOpacity)
        }
        if reducedMotion { return PlacedDoddy(box: home, squashX: 1, squashY: 1, opacity: 1) }
        let Beat = OpeningScene.Beat.self
        let p = Ease.inOut(Ease.progress(t, Beat.handoverStart, Beat.arrive))
        let lift = (40 + 0.25 * abs(home.centerY - court.centerY)) * sin(.pi * p)
        let box = ScreenBox(
            centerX: court.centerX + (home.centerX - court.centerX) * p,
            centerY: court.centerY + (home.centerY - court.centerY) * p - lift,
            height: court.height + (home.height - court.height) * p)
        let landing = sin(.pi * Ease.progress(t, Beat.arrive, Beat.end))
        // A little stretch in the air, a squash on landing.
        let air = sin(.pi * p) * 0.06
        return PlacedDoddy(box: box, squashX: 1 - air + 0.08 * landing, squashY: 1 + air - 0.12 * landing, opacity: 1)
    }

}
