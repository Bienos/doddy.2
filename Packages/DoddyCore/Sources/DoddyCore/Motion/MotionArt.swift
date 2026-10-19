import Foundation

// Motion v2, MV3: which of the owner's pack pictures shows him this frame, and the whole-picture
// transforms on it (owner answer to Q7: move, scale, rotate and squash a whole picture; never
// redraw, recolour, cut up or generate). The mapping is plan section 3 and nothing else; what
// that section marks missing is not drawn (docs/design/MOTION_V2_ART_REQUESTS.md). Names, not
// images: the app looks the pictures up (`DoddyMotion_<strip>_<n>`, `WholeDoddy_<pose>`).

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
    /// The UI tests' marker for this picture (ADR-336): `doddy.motion.jump`, `doddy.pose.listening`.
    public var marker: String {
        switch picture {
        case .strip(let name, _): "doddy.motion.\(name)"
        case .pose(let name): "doddy.pose.\(name)"
        }
    }

    public init(picture: Picture, mirrored: Bool = false, scaleX: Double = 1, scaleY: Double = 1, tilt: Double = 0) {
        self.picture = picture
        self.mirrored = mirrored
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.tilt = tilt
    }

    /// The hop strip (pack 015): crouch, take-off, apex, contact, stand.
    static let crouchFrame = 1, takeOffFrame = 2, apexFrame = 3, contactFrame = 4, settleFrame = 5
    /// Contact (60 ms in the brief) shows the landing squash frame, then the standing frame until
    /// the settle is done (about 280 ms).
    static let contactMs = 90.0, settleMs = 280.0

    /// His picture now. `still` replaces the standing picture when the screen asks for one (the
    /// empty Memories spot is cross-legged; a problem on screen is the facepalm, plan Q4).
    public static func choose(_ e: MotionEngine, still: String? = nil) -> MotionArt {
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
        } else if p.sit > 0.5 {
            picture = .pose("crosslegged")
        } else if let still {
            picture = .pose(still)
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
        return MotionArt(picture: picture, scaleX: sx, scaleY: sy, tilt: rm ? 0 : MotionMath.clamp(p.lean, -12, 12))
    }
}
