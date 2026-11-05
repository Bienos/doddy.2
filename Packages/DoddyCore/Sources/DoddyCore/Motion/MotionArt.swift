import Foundation

// Motion v2, MV3: which of the owner's pack pictures shows him this frame, and the whole-picture
// transforms on it (owner answer to Q7: move, scale, rotate and squash a whole picture; never
// redraw, recolour or generate). The mapping is plan section 3 and nothing else; what that
// section marks missing is not drawn (docs/design/MOTION_V2_ART_REQUESTS.md). One exception, by
// the owner's instruction of 20 Oct 2026 ("Make blink and gaze", Q6): his eyes, drawn from eyes
// cut out of the pack's sheets 007 and 008 over the pictures with a front-facing head
// (`MotionFace`, ADR-560). Names, not images: the app looks the pictures up
// (`DoddyMotion_<strip>_<n>`, `WholeDoddy_<pose>`, `DoddyEye_<cell>_<side>`).

public struct MotionArt: Equatable, Sendable {
    public enum Picture: Equatable, Sendable {
        /// A frame (from 1) of one of the pack's strips (`DoddyMotion`): "idle", "jump", "wave".
        case strip(String, Int)
        /// One of the pack's whole poses (`IslandPose` raw value): "crosslegged", "listening".
        case pose(String)
    }

    public var picture: Picture
    /// Drawn mirrored (a negative horizontal scale of the whole picture): the hop strip faces
    /// right, so a hop to the left shows it flipped.
    public var mirrored: Bool
    /// Squash and stretch of the whole picture around his soles (1: none).
    public var scaleX: Double
    public var scaleY: Double
    /// Whole-figure tilt around his soles, in degrees: the engine's lean. The pack has no
    /// separate head, so head roll is not drawn (plan section 3: "Head roll: missing").
    public var tilt: Double
    /// Where his eyes are (MV7). Only meaningful on a picture with a measured face; at you, the
    /// picture is exactly as the pack drew it.
    public var eyes: MotionEyes
    /// What to draw over the picture for his eyes: nothing at you.
    public var faceLayers: [MotionFaceLayer] { MotionFace.layers(for: picture, eyes: eyes) }
    /// The UI tests' marker for this picture (ADR-336): `doddy.motion.jump`, `doddy.pose.listening`.
    public var marker: String {
        switch picture {
        case .strip(let name, _): "doddy.motion.\(name)"
        case .pose(let name): "doddy.pose.\(name)"
        }
    }

    public init(picture: Picture, mirrored: Bool = false, scaleX: Double = 1, scaleY: Double = 1, tilt: Double = 0,
                eyes: MotionEyes = .atYou) {
        self.picture = picture
        self.mirrored = mirrored
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.tilt = tilt
        self.eyes = eyes
    }

    /// The hop strip (pack 015): crouch, take-off, apex, contact, stand.
    static let crouchFrame = 1, takeOffFrame = 2, apexFrame = 3, contactFrame = 4, settleFrame = 5
    /// Contact (60 ms in the brief) shows the landing squash frame, then the standing frame until
    /// the settle is done (about 280 ms).
    static let contactMs = 90.0, settleMs = 280.0

    /// The wave strip (pack 016) frame by frame, 140 ms each, then it rests on the open hand
    /// (as the app's wave has since ADR-380).
    static let waveFrameMs = 140.0

    /// A gesture's picture, if the pack has one. The welcome is the wave (Q15: the brief's eyes
    /// and head roll can't be drawn yet); the stretch is the yawn-and-stretch pose. The others
    /// (introduce, trace, look, edge sit) have no art and keep his standing picture.
    static func gesture(_ name: String, at t: Double) -> Picture? {
        switch name {
        case "wave", "welcome", "welcomeEvening":
            return .strip("wave", 1 + min(4, max(0, Int(t / waveFrameMs))))
        case "stretch":
            return .pose("yawn_stretch")
        default:
            return nil
        }
    }

    /// Breathing on the pack's four-frame breath (013): frames 1 to 4 on the way in, back to 1 on
    /// the way out, one breath per cycle of the engine's breath (4.2 s).
    static func breathFrame(_ phase: Double) -> Int {
        let f = phase - phase.rounded(.down)
        let depth = (1 - cos(2 * Double.pi * f)) / 2
        return 1 + Int((depth * 3).rounded())
    }

    /// His picture now. `still` replaces the standing picture when the screen asks for one (the
    /// empty Memories spot is cross-legged; a problem on screen is the facepalm, plan Q4).
    public static func choose(_ e: MotionEngine, still: String? = nil, previousEyes: MotionEyes? = nil) -> MotionArt {
        let p = e.pose
        let rm = e.settings.reduceMotion
        // The hop: crouch, take-off and apex frames, mirrored when travelling left.
        if e.mode == .anticipate {
            return MotionArt(picture: .strip("jump", crouchFrame), mirrored: p.facing < -0.2)
        }
        if e.mode == .flight, let f = e.flight {
            let s = MotionMath.clamp(f.t / max(1, f.T), 0, 1)
            let frame = s < 0.3 ? takeOffFrame : apexFrame
            let left = f.kind == .flick ? false : f.p1.x < f.p0.x - 1
            return MotionArt(picture: .strip("jump", frame), mirrored: left)
        }
        // Contact and settle after a real landing (never after a Reduce Motion fade).
        if !rm, e.mode == .attached, e.lastLand > 0 {
            let since = e.now - e.lastLand
            if since >= 0, since < contactMs { return MotionArt(picture: .strip("jump", contactFrame)) }
            if since >= 0, since < settleMs { return MotionArt(picture: .strip("jump", settleFrame)) }
        }
        // Poses the pack carries (plan section 3).
        var picture: Picture
        if p.listening {
            picture = .pose("listening")
        } else if e.isThinking {
            // Waiting for Ask's reply: the voice screen's thinking pose (kneeling, glove at chin).
            picture = .pose("kneeling_inspect")
        } else if let g = e.gestureName, let art = gesture(g, at: e.gestureElapsed) {
            picture = art
        } else if p.sit > 0.5 {
            picture = .pose("crosslegged")
        } else if let still {
            picture = .pose(still)
        } else if let phase = e.breathPhase {
            picture = .strip("idle", breathFrame(phase))
        } else {
            picture = .strip("idle", 1)
        }
        // Squash: the landing settle and the weight response while riding (crouch, in rig points
        // at 1.0×, down positive), and a drag's stretch. Off under Reduce Motion (the engine
        // already keeps the crouch at 0 there).
        var sy = 1.0
        if !rm, case .strip("idle", _) = picture {
            sy = 1 - MotionMath.clamp(p.crouch, -3, 6) / MotionLayout.height
            sy *= 1 + MotionMath.clamp(p.stretchUp, 0, 0.06)
        }
        let sx = 1 + (1 - sy) * 0.5
        // His eyes, on the pictures that have a measured front-facing head (MV7). Under Reduce
        // Motion they still move: eyes lead, and a fade is not eye movement.
        let eyes = MotionFace.hasFace(picture) ? MotionFace.choose(e.eyeState, previous: previousEyes) : .atYou
        return MotionArt(picture: picture, scaleX: sx, scaleY: sy, tilt: rm ? 0 : MotionMath.clamp(p.lean, -12, 12), eyes: eyes)
    }
}
