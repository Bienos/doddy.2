import DoddyCore
import SwiftUI

// PLACEHOLDER SCENERY (ADR-579): the Warsaw line and the pigeon are simple vector stand-ins drawn
// for the design review. The owner's pack has the real scenery and the pigeon from the brand
// film; replace these two views with it. The Palace of Culture outline is simplified and has not
// been checked against the building.

/// Draws SVG path data (parsed by DoddyCore's `WelcomePathData`) scaled from its own view box.
struct WelcomePathShape: Shape {
    let segments: [WelcomePathSegment]
    let viewBox: CGSize

    init(_ data: String, viewBox: CGSize) {
        // Every path used here is tested to parse; an empty result draws nothing rather than guessing.
        self.segments = WelcomePathData.parse(data) ?? []
        self.viewBox = viewBox
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard viewBox.width > 0, viewBox.height > 0 else { return path }
        let sx = rect.width / viewBox.width
        let sy = rect.height / viewBox.height
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + CGFloat(x) * sx, y: rect.minY + CGFloat(y) * sy)
        }
        for segment in segments {
            switch segment {
            case let .move(x, y):
                path.move(to: point(x, y))
            case let .line(x, y):
                path.addLine(to: point(x, y))
            case let .quad(cx, cy, x, y):
                path.addQuadCurve(to: point(x, y), control: point(cx, cy))
            case let .cubic(c1x, c1y, c2x, c2y, x, y):
                path.addCurve(to: point(x, y), control1: point(c1x, c1y), control2: point(c2x, c2y))
            case .close:
                path.closeSubpath()
            }
        }
        return path
    }
}

/// The Warsaw line: Sigismund's Column, Old Town gables, towers, the Palace of Culture. One thin
/// stroke, ink at 30%, 1000 x 130 in its own units. `scale` sizes it to the picture of Doddy.
struct WarsawLine: View {
    let scale: CGFloat

    private static let box = CGSize(width: 1000, height: 130)
    private static let strokes: [String] = [
        // Sigismund's Column
        "M50 130 V122 H74 V130 M56 122 V40 M68 122 V40 M52 40 H72 M62 40 V24 M56 31 H68",
        // Old Town gables and their windows
        "M120 130 V76 L132 64 L144 76 L156 64 L168 76 V130 M172 130 V58 H180 V50 H190 V44 H202 V50 H212 V58 H222 V130 M226 130 V82 Q253 54 280 82 V130",
        "M132 92 H138 V100 H132 Z M154 92 H160 V100 H154 Z M186 76 H192 V84 H186 Z M204 76 H210 V84 H204 Z M246 96 H258 V108 H246 Z",
        // Towers
        "M430 130 V62 H452 V130 M460 130 V38 H486 V130 M494 130 V78 H516 V130",
        // The Palace of Culture (simplified)
        "M650 130 V102 H668 V86 H684 V72 H696 V34 H700 V10 L704 34 H708 V72 H720 V86 H736 V102 H754 V130",
        // More gables
        "M830 130 V80 L842 68 L854 80 L866 68 L878 80 V130 M886 130 V60 H894 V52 H906 V60 H916 V130 M922 130 V86 Q946 62 970 86 V130",
    ]

    var body: some View {
        let width = Self.box.width * scale
        let height = Self.box.height * scale
        let style = StrokeStyle(lineWidth: max(1.5, 2 * scale), lineCap: .round, lineJoin: .round)
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.strokes.enumerated()), id: \.offset) { _, data in
                WelcomePathShape(data, viewBox: Self.box)
                    .stroke(Theme.ink.opacity(0.3), style: style)
            }
            // The column's head.
            Circle()
                .stroke(Theme.ink.opacity(0.3), style: style)
                .frame(width: 8 * scale, height: 8 * scale)
                .offset(x: 58 * scale, y: 15 * scale)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// The determined pigeon from the brand film, pecking. `peck` is 0...1 (`WelcomeTimeline.peck`),
/// `faces` where it looks.
struct PigeonView: View {
    enum Facing { case left, right }

    let facing: Facing
    let peck: Double

    private static let box = CGSize(width: 46, height: 34)

    var body: some View {
        ZStack {
            WelcomePathShape("M8 22 C8 14 16 11 24 12.5 C30 13.5 33 16 35 20 L42 27 L29 27.5 C22 31 12 29 8 22 Z", viewBox: Self.box)
                .fill(Theme.canvas)
            WelcomePathShape("M8 22 C8 14 16 11 24 12.5 C30 13.5 33 16 35 20 L42 27 L29 27.5 C22 31 12 29 8 22 Z", viewBox: Self.box)
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            WelcomePathShape("M20 29 V33 M26 29 V33", viewBox: Self.box)
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            // The head, beak and eye dip together when it pecks.
            ZStack {
                Circle().fill(Theme.canvas).frame(width: 10, height: 10).position(x: 33, y: 11.5)
                Circle().stroke(Theme.ink, lineWidth: 2.2).frame(width: 10, height: 10).position(x: 33, y: 11.5)
                WelcomePathShape("M37.5 11 L43 13 L37.5 14.5 Z", viewBox: Self.box)
                    .fill(Theme.orangeCue)
                Circle().fill(Theme.ink).frame(width: 2, height: 2).position(x: 34.5, y: 10.5)
            }
            .frame(width: Self.box.width, height: Self.box.height)
            .rotationEffect(.degrees(26 * peck), anchor: UnitPoint(x: 0.5, y: 0.8))
        }
        .frame(width: Self.box.width, height: Self.box.height)
        .offset(y: CGFloat(peck) * 1.5)
        .scaleEffect(x: facing == .left ? -1 : 1, y: 1)
        .accessibilityHidden(true)
    }
}
