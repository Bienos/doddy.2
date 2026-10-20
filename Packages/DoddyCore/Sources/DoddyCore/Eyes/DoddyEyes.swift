import Foundation

// Doddy's eyes (ADR-560). The owner's pack has no picture of Doddy looking somewhere or blinking,
// but its sheets 007 (a blink) and 008 (nine looks) have the eyes. On 20 Oct 2026 the owner said
// "Make blink and gaze" (Q6), then "minimum plus the eyes" for the calm Home (ADR-545).
// `tools/whole_doddy/build_face_pieces.py` cuts each eye out of those sheets as ink on a
// transparent background (nothing redrawn or recoloured) and measures where the eyes are on the
// pack pictures with a front-facing head (`DoddyEyePieces.swift`, generated).
//
// What is drawn: on a picture with a measured face, and only while his eyes are not on you, a soft
// cover in the paper's own colour hides the picture's eye and the cut eye goes on top. Looking at
// you, the picture is exactly as the pack drew it. Pictures with a turned head (the listening pose,
// the hop strip) have no pieces, so his eyes stay as drawn there.

/// Where his eyes are, as one of the cut pieces.
public enum DoddyLook: Equatable, Sendable {
    /// Looking at something: column 0 (the screen's left) to 2, row 0 (up) to 2 (down).
    /// (1, 1) is looking at you, the picture as the pack drew it.
    case gaze(column: Int, row: Int)
    /// Half closed: the squint while a finger is on him, and the middle of a blink.
    case half
    /// Closed: a blink at its peak.
    case closed

    public static let atYou = DoddyLook.gaze(column: 1, row: 1)

    public var isAtYou: Bool { self == .atYou }

    /// The piece to draw on a picture shown mirrored (the motion world flips a whole picture to
    /// face left): the mirror swaps left and right, so a look to the screen's left is drawn as the
    /// picture's own look to the right.
    public var mirrored: DoddyLook {
        if case .gaze(let column, let row) = self { return .gaze(column: 2 - column, row: row) }
        return self
    }

    /// For the UI tests' markers: `half`, `closed`, `gaze02`; nil when he looks at you.
    public var name: String? {
        switch self {
        case .gaze(let column, let row): isAtYou ? nil : "gaze\(row)\(column)"
        case .half: "half"
        case .closed: "closed"
        }
    }
}

/// What his eyes are doing this moment, before it is turned into one of the pieces.
public struct DoddyEyeState: Equatable, Sendable {
    /// The direction to what he looks at, a unit vector on the screen (x right, y down); (0, 0) is at you.
    public var gazeX: Double
    public var gazeY: Double
    /// A blink: 0 open, 1 closed.
    public var closed: Double
    /// The squint while touched: 0 to 1.
    public var squint: Double

    public init(gazeX: Double = 0, gazeY: Double = 0, closed: Double = 0, squint: Double = 0) {
        self.gazeX = gazeX
        self.gazeY = gazeY
        self.closed = closed
        self.squint = squint
    }
}

/// A point on the screen, in points.
public struct DoddyEyePoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// One thing to draw on his picture, in pixels of the picture's @3x file (300 × 450): the centre
/// and the size.
public struct DoddyEyeLayer: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// An ellipse in the paper's colour over the picture's own eye, its edge softened by `blur` pixels.
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

public enum DoddyEyes {
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
        var cell: DoddyLook
        var side: Side
        var dx: Double, dy: Double
        var w: Double, h: Double
        var normW: Double, normH: Double
    }

    /// Whether his eyes can be drawn on this picture (an image set name, `WholeDoddy_crosslegged`).
    public static func hasFace(_ asset: String) -> Bool { fits[asset] != nil }

    /// Every picture with a measured face, by image set name.
    public static var pictureAssets: [String] { fits.keys.sorted() }

    /// Every image set the pieces use.
    public static var pieceAssets: [String] { pieces.map(\.asset) }

    // MARK: Which piece

    /// A gaze band holds until the direction has clearly left it, so a direction hovering at an
    /// edge doesn't flicker between two pieces.
    static let enter = 0.42, leave = 0.28

    static func band(_ v: Double, previous: Int?) -> Int {
        if previous == 0, v < -leave { return 0 }
        if previous == 2, v > leave { return 2 }
        return v < -enter ? 0 : v > enter ? 2 : 1
    }

    /// The piece for this moment. A blink goes through half, closed and half again (the sheet's
    /// order); a squint is half; otherwise he looks where the direction says.
    public static func look(_ s: DoddyEyeState, previous: DoddyLook? = nil) -> DoddyLook {
        if s.closed >= 0.75 { return .closed }
        if s.closed >= 0.3 || s.squint >= 0.5 { return .half }
        var column: Int?, row: Int?
        if case .gaze(let c, let r)? = previous { column = c; row = r }
        return .gaze(column: band(s.gazeX, previous: column), row: band(s.gazeY, previous: row))
    }

    // MARK: Layers

    /// The middle of the picture's two eyes, in pixels of its @3x file: where he looks from.
    /// `mirrored`: the picture is drawn flipped round its middle, so the point is too.
    public static func eyesCentre(_ asset: String, mirrored: Bool = false) -> DoddyEyePoint? {
        guard let fit = fits[asset] else { return nil }
        let x = (fit.left.x + fit.right.x) / 2
        return DoddyEyePoint(x: mirrored ? pictureWidth - x : x, y: (fit.left.y + fit.right.y) / 2)
    }

    /// What to draw over `asset` for `look`: nothing at you, or on a picture with no measured face.
    public static func layers(for asset: String, look: DoddyLook) -> [DoddyEyeLayer] {
        guard !look.isAtYou, let fit = fits[asset] else { return [] }
        var out: [DoddyEyeLayer] = []
        for (side, eye) in [(Side.left, fit.left), (Side.right, fit.right)] {
            guard let piece = pieces.first(where: { $0.cell == look && $0.side == side }) else { continue }
            out.append(DoddyEyeLayer(kind: .cover(fill: eye.fill, blur: coverBlur),
                                     x: eye.x, y: eye.y,
                                     width: eye.w + 2 * coverPad, height: eye.h + 2 * coverPad))
            let width = piece.normW > 0 ? piece.w / piece.normW * eye.w : piece.w * fit.radius
            let height = piece.normH > 0 ? piece.h / piece.normH * eye.h : piece.h * fit.radius
            out.append(DoddyEyeLayer(kind: .piece(asset: piece.asset),
                                     x: eye.x + piece.dx * fit.radius, y: eye.y + piece.dy * fit.radius,
                                     width: width, height: height))
        }
        return out
    }
}

/// His eyes on the calm Home (ADR-560): they follow a finger anywhere on Home and come back to you
/// 300 ms after it lifts; half close while a finger is on him; and after 21:00 he gives one slow
/// blink, once a day. Nothing else: no blinking on a loop (brief rule 9, stillness by default).
public enum HomeEyes {
    /// After the finger lifts, the eyes stay on where it was this long, then come back to you.
    public static let returnAfter = 0.3
    /// The evening's slow blink (the brief: 280 ms).
    public static let blinkDuration = 0.28
    /// The evening blink is due from this hour.
    public static let eveningHour = 21
    /// A finger this close to his eyes (points) doesn't move them: he can't look at his own nose.
    public static let deadZone = 24.0

    /// The direction from his eyes to a finger, a unit vector; (0, 0) inside the dead zone.
    public static func direction(from eyes: DoddyEyePoint, to finger: DoddyEyePoint) -> (x: Double, y: Double) {
        let dx = finger.x - eyes.x, dy = finger.y - eyes.y
        let d = (dx * dx + dy * dy).squareRoot()
        guard d > deadZone else { return (0, 0) }
        return (dx / d, dy / d)
    }

    /// How closed the eyes are, `elapsed` seconds into a blink: closing over 43 % of it, then opening.
    public static func blink(elapsed: Double, duration: Double = blinkDuration) -> Double {
        guard elapsed >= 0, elapsed < duration else { return 0 }
        let a = duration * 0.43
        return elapsed < a ? elapsed / a : 1 - (elapsed - a) / (duration - a)
    }

    /// Today's key (`2026-10-20`), if the evening blink is due: from 21:00, once a day.
    public static func eveningBlinkDay(now: Date, lastDay: String?, calendar: Calendar = .current) -> String? {
        let c = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        guard let hour = c.hour, hour >= eveningHour, let y = c.year, let m = c.month, let d = c.day else { return nil }
        let day = String(format: "%04d-%02d-%02d", y, m, d)
        return day == lastDay ? nil : day
    }

    /// The piece for this moment on Home.
    /// - Parameters:
    ///   - eyes: where his eyes are on the screen.
    ///   - finger: a finger on Home, not on him; nil when none is down.
    ///   - lifted: where the last finger lifted and how long ago (seconds).
    ///   - pressed: a finger is on him (the Talk button is held down).
    ///   - blinkElapsed: seconds into the evening blink, if it is playing.
    public static func look(eyes: DoddyEyePoint, finger: DoddyEyePoint?, lifted: (point: DoddyEyePoint, ago: Double)?,
                            pressed: Bool, blinkElapsed: Double?, previous: DoddyLook?) -> DoddyLook {
        var state = DoddyEyeState()
        if let blinkElapsed { state.closed = blink(elapsed: blinkElapsed) }
        if pressed { state.squint = 1 }
        if let point = finger ?? lifted.flatMap({ $0.ago < returnAfter ? $0.point : nil }) {
            let v = direction(from: eyes, to: point)
            state.gazeX = v.x
            state.gazeY = v.y
        }
        return DoddyEyes.look(state, previous: previous)
    }
}
