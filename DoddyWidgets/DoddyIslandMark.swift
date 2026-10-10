import SwiftUI

/// Doddy for the Dynamic Island, from the owner's "Lean In" board (Doddy-Dynamic-Island-v4,
/// board 01, ADR-210): round cream face, vertical oval eyes with the right one raised, one
/// curved eyebrow, an asymmetric mouth, and a cupped hand with an orange arc when he is
/// listening. Every path and number below is copied from the pack's state SVGs
/// (`02-states/voice-*`, `companion-1`, `calm-pulse-0`, `language-bridge-1`). Only the pack's own
/// expressions are used; none is invented here.
///
/// Units are the SVGs' face units: the face is a circle of radius 20 centred on (0, 0).
/// A Live Activity only redraws when the app sends a new state, so nothing here moves by itself.
struct DoddyIslandMark: View {
    enum Expression: Equatable {
        /// `voice-0`: smile.
        case listening
        /// `voice-1`: open mouth.
        case speaking
        /// `companion-1`: brow up, small mouth.
        case thinking
        /// `calm-pulse-0`: softer eyes, small smile.
        case calm
        /// `language-bridge-1`: big smile.
        case proud
    }

    enum Cue: Equatable {
        case faceOnly
        /// The cupped hand at his ear.
        case hand
        /// Hand plus the orange "I can hear you" arc. Only while live.
        case handAndArc
    }

    let expression: Expression
    let cue: Cue
    /// Diameter of the face in points. Expanded board: 36 pt; compact: 22 pt; minimal: 21 pt.
    let faceSize: CGFloat

    private var k: CGFloat { faceSize / 40 }

    /// Width in face units, from the face's left edge to the right edge of what is drawn.
    private var widthUnits: CGFloat {
        switch cue {
        case .faceOnly: return 42
        case .hand: return 61
        case .handAndArc: return 65
        }
    }

    var body: some View {
        ZStack {
            FacePath(part: .disk).fill(Lean.cream)
            FacePath(part: .outline).stroke(Lean.black, style: Lean.round(1.4 * k))
            FacePath(part: .eyes(expression)).fill(Lean.black)
            FacePath(part: .brow(expression)).stroke(Lean.black, style: Lean.round(1.9 * k))
            if expression == .speaking {
                FacePath(part: .mouth(expression)).fill(Lean.black)
            } else {
                FacePath(part: .mouth(expression)).stroke(Lean.black, style: Lean.round(2.1 * k))
            }
            if cue != .faceOnly {
                FacePath(part: .hand).fill(Lean.cream)
                FacePath(part: .handCrease).stroke(Lean.black, style: Lean.round(1.5 * Lean.handScale * k))
            }
            if cue == .handAndArc {
                FacePath(part: .arc).stroke(Lean.orange, style: Lean.round(2 / 0.9 * k))
            }
        }
        .frame(width: widthUnits * k, height: 44 * k)
        .accessibilityHidden(true)
    }
}

/// The Lean In palette (Design-notes.md, "Shared visual system").
enum Lean {
    static let cream = Color(red: 0xF5 / 255, green: 0xEF / 255, blue: 0xE2 / 255)
    static let black = Color(red: 0x08 / 255, green: 0x08 / 255, blue: 0x08 / 255)
    static let orange = Color(red: 0xEC / 255, green: 0x80 / 255, blue: 0x3F / 255)
    static let secondary = Color(red: 0xBD / 255, green: 0xB7 / 255, blue: 0xAA / 255)
    /// The 34 pt button pill.
    static let pill = Color(red: 0x27 / 255, green: 0x25 / 255, blue: 0x1F / 255)

    /// Hand position and size relative to the face (board: face at 45,81 ×0.9; hand at 72,84 ×0.567).
    static let handOffset = CGPoint(x: 27 / 0.9, y: 3 / 0.9)
    static let handScale: CGFloat = 0.5666666666666667 / 0.9

    static func round(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }
}

/// One part of the mark, built in face units and mapped into the view's frame.
private struct FacePath: Shape {
    enum Part {
        case disk, outline, eyes(DoddyIslandMark.Expression), brow(DoddyIslandMark.Expression)
        case mouth(DoddyIslandMark.Expression), hand, handCrease, arc
    }

    let part: Part

    func path(in rect: CGRect) -> Path {
        // The frame is 44 face units tall with the face centred; its left edge is 1 unit left of the face.
        let k = rect.height / 44
        let toRect = CGAffineTransform(translationX: rect.minX + 21 * k, y: rect.midY).scaledBy(x: k, y: k)
        return unitPath.applying(toRect)
    }

    private var unitPath: Path {
        var p = Path()
        switch part {
        case .disk, .outline:
            p.addEllipse(in: CGRect(x: -20, y: -20, width: 40, height: 40))

        case .eyes(let expression):
            // calm-pulse: shorter eyes; every other board: 3.4.
            let ry: CGFloat = expression == .calm ? 2.4 : 3.4
            p.addEllipse(in: CGRect(x: -5.5 - 1.9, y: 0.7 - ry, width: 3.8, height: ry * 2))
            p.addEllipse(in: CGRect(x: 6.4 - 1.9, y: -2.1 - ry, width: 3.8, height: ry * 2))

        case .brow(let expression):
            if expression == .thinking {
                p.move(to: CGPoint(x: 3, y: -12))  // M3-12Q8-18 12-11
                p.addQuadCurve(to: CGPoint(x: 12, y: -11), control: CGPoint(x: 8, y: -18))
            } else {
                p.move(to: CGPoint(x: 3, y: -11))  // M3-11Q8-16 12-11
                p.addQuadCurve(to: CGPoint(x: 12, y: -11), control: CGPoint(x: 8, y: -16))
            }

        case .mouth(let expression):
            switch expression {
            case .listening:  // M-5 8Q4 17 12 5
                p.move(to: CGPoint(x: -5, y: 8))
                p.addQuadCurve(to: CGPoint(x: 12, y: 5), control: CGPoint(x: 4, y: 17))
            case .speaking:  // M-6 6Q3 16 12 3Q10 17 3 17Q-3 15-6 6Z (filled)
                p.move(to: CGPoint(x: -6, y: 6))
                p.addQuadCurve(to: CGPoint(x: 12, y: 3), control: CGPoint(x: 3, y: 16))
                p.addQuadCurve(to: CGPoint(x: 3, y: 17), control: CGPoint(x: 10, y: 17))
                p.addQuadCurve(to: CGPoint(x: -6, y: 6), control: CGPoint(x: -3, y: 15))
                p.closeSubpath()
            case .thinking:  // M-4 9Q2 12 8 7
                p.move(to: CGPoint(x: -4, y: 9))
                p.addQuadCurve(to: CGPoint(x: 8, y: 7), control: CGPoint(x: 2, y: 12))
            case .calm:  // M-5 8Q3 13 10 5
                p.move(to: CGPoint(x: -5, y: 8))
                p.addQuadCurve(to: CGPoint(x: 10, y: 5), control: CGPoint(x: 3, y: 13))
            case .proud:  // M-7 6Q3 18 13 2
                p.move(to: CGPoint(x: -7, y: 6))
                p.addQuadCurve(to: CGPoint(x: 13, y: 2), control: CGPoint(x: 3, y: 18))
            }

        case .hand:
            // M-11 4Q-14-2-9-4L-2-2L-3-9Q-1-15 3-9L6-2L10-1Q15 0 13 7Q8 14 0 13Q-8 13-11 4Z
            var h = Path()
            h.move(to: CGPoint(x: -11, y: 4))
            h.addQuadCurve(to: CGPoint(x: -9, y: -4), control: CGPoint(x: -14, y: -2))
            h.addLine(to: CGPoint(x: -2, y: -2))
            h.addLine(to: CGPoint(x: -3, y: -9))
            h.addQuadCurve(to: CGPoint(x: 3, y: -9), control: CGPoint(x: -1, y: -15))
            h.addLine(to: CGPoint(x: 6, y: -2))
            h.addLine(to: CGPoint(x: 10, y: -1))
            h.addQuadCurve(to: CGPoint(x: 13, y: 7), control: CGPoint(x: 15, y: 0))
            h.addQuadCurve(to: CGPoint(x: 0, y: 13), control: CGPoint(x: 8, y: 14))
            h.addQuadCurve(to: CGPoint(x: -11, y: 4), control: CGPoint(x: -8, y: 13))
            h.closeSubpath()
            p = h.applying(Self.handTransform)

        case .handCrease:  // M-5 5Q2 1 9 5
            var h = Path()
            h.move(to: CGPoint(x: -5, y: 5))
            h.addQuadCurve(to: CGPoint(x: 9, y: 5), control: CGPoint(x: 2, y: 1))
            p = h.applying(Self.handTransform)

        case .arc:
            // Board: M74 59Q88 78 77 99, relative to the face at (45, 81) scaled 0.9.
            func f(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - 45) / 0.9, y: (y - 81) / 0.9) }
            p.move(to: f(74, 59))
            p.addQuadCurve(to: f(77, 99), control: f(88, 78))
        }
        return p
    }

    private static let handTransform = CGAffineTransform(translationX: Lean.handOffset.x, y: Lean.handOffset.y)
        .scaledBy(x: Lean.handScale, y: Lean.handScale)
}

/// The board's voice bars: seven bars with an orange centre (expanded), five (compact) or three
/// (minimal). A fixed "voice is live" sign that appears only while Doddy can hear you; the heights
/// are the board's and do not follow the microphone level.
struct LeanVoiceBars: View {
    enum Size { case expanded, compact, minimal }

    let size: Size

    private var bars: [(height: CGFloat, orange: Bool)] {
        switch size {
        case .expanded: return [(4, false), (7, false), (11, false), (18, true), (10, false), (6, false), (3, false)]
        case .compact: return [(6, false), (11, false), (17, true), (9, false), (5, false)]
        case .minimal: return [(5, false), (13, true), (7, false)]
        }
    }

    private var width: CGFloat { size == .minimal ? 2 : (size == .compact ? 2.5 : 2.2) }
    private var gap: CGFloat { size == .minimal ? 2 : (size == .compact ? 2.5 : 2.8) }
    private var plain: Color { size == .compact ? Lean.cream : Lean.secondary }

    var body: some View {
        HStack(alignment: .center, spacing: gap) {
            ForEach(bars.indices, id: \.self) { i in
                Capsule()
                    .fill(bars[i].orange ? Lean.orange : plain)
                    .frame(width: width, height: bars[i].height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// "Here With You" thinking cue (companion-1): three dots, the middle one orange while live.
struct LeanThinkingDots: View {
    let orangeCentre: Bool
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 3.5 * scale) {
            Circle().fill(Lean.secondary).frame(width: 3 * scale, height: 3 * scale)
            Circle().fill(orangeCentre ? Lean.orange : Lean.secondary).frame(width: 4 * scale, height: 4 * scale)
            Circle().fill(Lean.secondary).frame(width: 3 * scale, height: 3 * scale)
        }
        .accessibilityHidden(true)
    }
}
