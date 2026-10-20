import Foundation

// Motion v2, MV7 (ADR-558): his eyes. The engine has always known where he looks and when he
// blinks or squints (`MotionEngine.eyeState`); the pack had no picture of it. On 20 Oct 2026 the
// owner said "Make blink and gaze" (Q6), and the pack's sheets 007 (a blink) and 008 (nine
// gazes) have the eyes. `tools/whole_doddy/build_face_pieces.py` cuts each eye out of them as ink
// on a transparent background (nothing redrawn or recoloured) and measures where the eyes are on
// the pictures he stands, waves and sits in (`MotionFacePieces.swift`, generated).
//
// What is drawn: over a picture that has a measured front-facing head, only while his eyes are
// somewhere other than at you. A soft cover in the paper's own colour hides the picture's eye, and
// the cut eye goes on top. At you, the picture is exactly as the pack drew it. Pictures with a
// turned or tilted head (the hop strip, listening, thinking, the stretch) have no pieces, so his
// eyes stay as drawn there; docs/design/MOTION_V2_ART_REQUESTS.md lists what would add them.

/// Where his eyes are, as one of the cut pieces.
public enum MotionEyes: Equatable, Sendable {
    /// Looking at something: column 0 (his left on the screen) to 2, row 0 (up) to 2 (down).
    /// (1, 1) is looking at you, the picture as the pack drew it.
    case gaze(column: Int, row: Int)
    /// Half closed: the squint when touched, and the middle of a blink.
    case half
    /// Closed: a blink at its peak, and eyes shut in contentment.
    case closed

    public static let atYou = MotionEyes.gaze(column: 1, row: 1)

    public var isAtYou: Bool { self == .atYou }

    /// The UI tests' marker for eyes that aren't at you (`doddy.eyes.half`, `doddy.eyes.gaze02`).
    public var marker: String? {
        switch self {
        case .gaze(let column, let row): isAtYou ? nil : "doddy.eyes.gaze\(row)\(column)"
        case .half: "doddy.eyes.half"
        case .closed: "doddy.eyes.closed"
        }
    }
}

/// What the engine knows about his eyes this frame.
public struct MotionEyeState: Equatable, Sendable {
    /// The direction to what he looks at, a unit vector on the screen (x right, y down); (0, 0) is at you.
    public var gazeX: Double
    public var gazeY: Double
    /// A blink or eyes shut: 0 open, 1 closed.
    public var closed: Double
    /// The squint when touched: 0 to 1.
    public var squint: Double

    public init(gazeX: Double = 0, gazeY: Double = 0, closed: Double = 0, squint: Double = 0) {
        self.gazeX = gazeX
        self.gazeY = gazeY
        self.closed = closed
        self.squint = squint
    }
}

/// One thing to draw on his picture, in pixels of the picture's @3x file (300 × 450), the centre
/// and the size.
public struct MotionFaceLayer: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// An ellipse in the paper's colour over the picture's own eye, its edge softened.
        case cover(fill: [Int], blur: Double)
        /// A cut eye (an image set in the app's catalog).
        case piece(asset: String)
    }

    public var kind: Kind
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
}

public enum MotionFace {
    /// The size of every picture's @3x file the measurements are in.
    public static let pictureWidth = 300.0, pictureHeight = 450.0

    struct Eye: Equatable {
        var x: Double, y: Double, w: Double, h: Double
        var fill: [Int]
    }

    /// A picture's head: its radius and where its two eyes are (left is the smaller x).
    struct Fit: Equatable {
        var radius: Double
        var left: Eye
        var right: Eye
    }

    enum Side: Equatable { case left, right }

    /// One cut eye. Lengths are in head radii of the sheet it was cut from; `dx`/`dy` are how far
    /// it sits from the same eye as the picture drew it (gaze: from the sheet's looking-at-you
    /// head; blink: from the sheet's open head). A gaze piece is stretched to the picture's own
    /// eye (`normW`, `normH` are the sheet's looking-at-you eye); a blink piece keeps its size.
    struct Piece: Equatable {
        var asset: String
        var cell: MotionEyes
        var side: Side
        var dx: Double, dy: Double
        var w: Double, h: Double
        var normW: Double, normH: Double
    }

    /// The key of a picture in `fits`.
    static func key(for picture: MotionArt.Picture) -> String {
        switch picture {
        case .strip(let name, let frame): "strip:\(name):\(frame)"
        case .pose(let name): "pose:\(name)"
        }
    }

    /// Whether his eyes can be drawn on this picture.
    public static func hasFace(_ picture: MotionArt.Picture) -> Bool { fits[key(for: picture)] != nil }

    /// Every picture with a measured face, by key (for the tests and the asset check).
    public static var pictureKeys: [String] { fits.keys.sorted() }

    /// The same pictures as `MotionArt.Picture` values.
    public static var pictures: [MotionArt.Picture] {
        pictureKeys.compactMap { key in
            let parts = key.split(separator: ":")
            switch (parts.first, parts.count) {
            case ("strip"?, 3): return Int(parts[2]).map { .strip(String(parts[1]), $0) }
            case ("pose"?, 2): return .pose(String(parts[1]))
            default: return nil
            }
        }
    }

    /// Every image set the pieces use.
    public static var pieceAssets: [String] { pieces.map(\.asset) }

    // MARK: Which eyes

    /// A gaze band holds until the direction has clearly left it, so a direction hovering at an
    /// edge doesn't flicker between two pictures.
    static let enter = 0.42, leave = 0.28

    static func band(_ v: Double, previous: Int?) -> Int {
        if previous == 0, v < -leave { return 0 }
        if previous == 2, v > leave { return 2 }
        return v < -enter ? 0 : v > enter ? 2 : 1
    }

    /// The eyes this frame. A blink goes through half, closed and half again (the sheet's order);
    /// a squint is half; otherwise he looks where the engine says.
    public static func choose(_ s: MotionEyeState, previous: MotionEyes? = nil) -> MotionEyes {
        if s.closed >= 0.75 { return .closed }
        if s.closed >= 0.3 || s.squint >= 0.5 { return .half }
        var column: Int?, row: Int?
        if case .gaze(let c, let r)? = previous { column = c; row = r }
        return .gaze(column: band(s.gazeX, previous: column), row: band(s.gazeY, previous: row))
    }

    // MARK: Layers

    /// What to draw over `picture` for `eyes`: nothing at you, or on a picture with no measured face.
    public static func layers(for picture: MotionArt.Picture, eyes: MotionEyes) -> [MotionFaceLayer] {
        guard !eyes.isAtYou, let fit = fits[key(for: picture)] else { return [] }
        var out: [MotionFaceLayer] = []
        for (side, eye) in [(Side.left, fit.left), (Side.right, fit.right)] {
            guard let piece = pieces.first(where: { $0.cell == eyes && $0.side == side }) else { continue }
            out.append(MotionFaceLayer(kind: .cover(fill: eye.fill, blur: coverBlur),
                                       x: eye.x, y: eye.y,
                                       width: eye.w + 2 * coverPad, height: eye.h + 2 * coverPad))
            let width = piece.normW > 0 ? piece.w / piece.normW * eye.w : piece.w * fit.radius
            let height = piece.normH > 0 ? piece.h / piece.normH * eye.h : piece.h * fit.radius
            out.append(MotionFaceLayer(kind: .piece(asset: piece.asset),
                                       x: eye.x + piece.dx * fit.radius, y: eye.y + piece.dy * fit.radius,
                                       width: width, height: height))
        }
        return out
    }
}
