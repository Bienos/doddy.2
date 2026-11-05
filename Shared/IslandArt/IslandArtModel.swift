import Foundation

/// The boards of the owner's Doddy-Dynamic-Island-v4 pack (design/dynamic-island-v4) that the app
/// still draws. Raw values are the pack's file prefixes. The voice board backs Whole Doddy's signs
/// and sizes; the others are the islands for a note, plan, reminder, focus, breathing, reading
/// aloud and translating. The pack's other eight boards (the seven voice looks and Pocket Radio
/// and Kinetic Ribbon, which were never used) were removed with the style picker.
enum IslandBoard: String, CaseIterable, Sendable {
    case leanIn = "voice", tinyPromise = "focus"
    case thoughtPocket = "thought-drop", languageBridge = "language-bridge"
    case reminderKnot = "reminder-pin", stepStones = "step-path", storySpool = "spoken-mark"
    case calmTide = "calm-pulse"
}

enum IslandPresentation: Sendable {
    case expanded, compact, minimal
}

/// Doddy's expressions, exactly the six the pack draws (the generator refuses any other face).
enum IslandFace: String, Codable, Hashable, Sendable {
    case listening, speaking, thinking, calm, proud, focused

    /// Eye height (half), brow and mouth in face units: a circle of radius 20 around (0, 0).
    var eyeRadiusY: Double { self == .calm ? 2.4 : 3.4 }
    var brow: String { self == .thinking ? "M3-12Q8-18 12-11" : "M3-11Q8-16 12-11" }
    var mouth: String {
        switch self {
        case .listening: "M-5 8Q4 17 12 5"
        case .speaking: "M-6 6Q3 16 12 3Q10 17 3 17Q-3 15-6 6Z"
        case .thinking: "M-4 9Q2 12 8 7"
        case .calm: "M-5 8Q3 13 10 5"
        case .proud: "M-7 6Q3 18 13 2"
        case .focused: "M-5 9Q3 13 10 6"
        }
    }
    /// The speaking mouth is a filled shape; the others are lines.
    var mouthIsFilled: Bool { self == .speaking }
}

struct IslandRect: Equatable, Sendable {
    var x: Double, y: Double, width: Double, height: Double
}

/// Colours are the pack's hex values (0xRRGGBB). nil means none.
struct IslandPaint: Equatable, Sendable {
    var fill: UInt32?
    var stroke: UInt32?
    var width: Double
}

enum IslandGroupRole: Sendable {
    /// One of Doddy's hands.
    case hand
    case other
}

indirect enum IslandArtElement: Sendable {
    case path(String, IslandPaint)
    case ellipse(cx: Double, cy: Double, rx: Double, ry: Double, IslandPaint)
    case rect(x: Double, y: Double, width: Double, height: Double, radius: Double, IslandPaint)
    /// Doddy's face: a 40-unit circle centred at (x, y), scaled.
    case face(x: Double, y: Double, scale: Double, IslandFace)
    case group(x: Double, y: Double, scale: Double, role: IslandGroupRole, [IslandArtElement])
}

/// A drawing in the pack's own coordinates; `viewBox` is the part to show.
struct IslandArt: Sendable {
    let viewBox: IslandRect
    let elements: [IslandArtElement]
}

/// The pack's palette (Design-notes.md, "Shared visual system").
enum IslandColor {
    static let cream: UInt32 = 0xF5EFE2
    static let black: UInt32 = 0x080808
    static let orange: UInt32 = 0xEC803F
    static let secondary: UInt32 = 0xBDB7AA
    static let pill: UInt32 = 0x27251F
}

/// One shape ready to draw: geometry in its own units, placed by `x + scale * point`.
struct IslandPrimitive: Sendable {
    enum Geometry: Sendable {
        case path([IslandPathCommand])
        case ellipse(cx: Double, cy: Double, rx: Double, ry: Double)
        case rect(x: Double, y: Double, width: Double, height: Double, radius: Double)
    }

    let geometry: Geometry
    let x: Double
    let y: Double
    let scale: Double
    let paint: IslandPaint
}

extension IslandArt {
    /// Flattens the drawing for the current state.
    /// - face: Doddy's expression now (nil keeps the board's).
    /// - live: false turns every orange mark into the secondary grey: orange means Doddy can
    ///   hear you (ADR-106), so a muted, waiting or lost island never shows it.
    /// - showsHands: false leaves Doddy's hands out (Lean In's hand at his ear means listening).
    func primitives(face: IslandFace? = nil, live: Bool, showsHands: Bool = true) -> [IslandPrimitive] {
        var out: [IslandPrimitive] = []
        func paint(_ p: IslandPaint) -> IslandPaint {
            guard !live else { return p }
            var p = p
            if p.fill == IslandColor.orange { p.fill = IslandColor.secondary }
            if p.stroke == IslandColor.orange { p.stroke = IslandColor.secondary }
            return p
        }
        func add(_ element: IslandArtElement, x: Double, y: Double, s: Double) {
            switch element {
            case .path(let d, let p):
                out.append(.init(geometry: .path(IslandPathParser.commands(d)), x: x, y: y, scale: s, paint: paint(p)))
            case .ellipse(let cx, let cy, let rx, let ry, let p):
                out.append(.init(geometry: .ellipse(cx: cx, cy: cy, rx: rx, ry: ry), x: x, y: y, scale: s, paint: paint(p)))
            case .rect(let rx, let ry, let w, let h, let r, let p):
                out.append(.init(geometry: .rect(x: rx, y: ry, width: w, height: h, radius: r), x: x, y: y, scale: s, paint: paint(p)))
            case .face(let fx, let fy, let fs, let boardFace):
                let f = face ?? boardFace
                let (ax, ay, as_) = (x + s * fx, y + s * fy, s * fs)
                let cream = IslandPaint(fill: IslandColor.cream, stroke: nil, width: 0)
                let outline = IslandPaint(fill: nil, stroke: IslandColor.black, width: 1.4)
                let ink = IslandPaint(fill: IslandColor.black, stroke: nil, width: 0)
                out.append(.init(geometry: .ellipse(cx: 0, cy: 0, rx: 20, ry: 20), x: ax, y: ay, scale: as_, paint: cream))
                out.append(.init(geometry: .ellipse(cx: 0, cy: 0, rx: 20, ry: 20), x: ax, y: ay, scale: as_, paint: outline))
                out.append(.init(geometry: .ellipse(cx: -5.5, cy: 0.7, rx: 1.9, ry: f.eyeRadiusY), x: ax, y: ay, scale: as_, paint: ink))
                out.append(.init(geometry: .ellipse(cx: 6.4, cy: -2.1, rx: 1.9, ry: f.eyeRadiusY), x: ax, y: ay, scale: as_, paint: ink))
                out.append(.init(geometry: .path(IslandPathParser.commands(f.brow)), x: ax, y: ay, scale: as_,
                                 paint: IslandPaint(fill: nil, stroke: IslandColor.black, width: 1.9)))
                out.append(.init(geometry: .path(IslandPathParser.commands(f.mouth)), x: ax, y: ay, scale: as_,
                                 paint: f.mouthIsFilled ? ink : IslandPaint(fill: nil, stroke: IslandColor.black, width: 2.1)))
            case .group(let gx, let gy, let gs, let role, let children):
                if role == .hand && !showsHands { return }
                for child in children { add(child, x: x + s * gx, y: y + s * gy, s: s * gs) }
            }
        }
        for element in elements { add(element, x: 0, y: 0, s: 1) }
        return out
    }
}
