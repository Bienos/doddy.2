import SwiftUI

/// Doddy's orange waves (owner, 22 Oct 2026, ADR-596; Figma file `yqoQlkN6BpevFGW3ySnNJU`, page
/// "Wyspa i wiadomości"): sine lines that say he hears you (`.line`, beside his status) or that he
/// is talking (`.speech` on the expanded island). `phase` moves them along. A Live Activity can't
/// run an animation of its own between updates, so while he talks the compact island slides them
/// on one stretch per beat the app sends (ADR-653), and Home moves them under him
/// (`HomeVoiceWaves`).
///
/// Bolder since 24 Oct (owner: the lines were too thin and rendered poorly, ADR-615): fewer lines,
/// 2 to 3 pt wide instead of 1.3 to 2.2, and drawn from a point every half point instead of every
/// two, so a small wave is a curve and not a zigzag. On the expanded island his talking waves
/// stay in the band under his status, as his listening line does, start beside him and spread
/// out to the right (owner: not across the whole island, and they should end before him).
struct IslandWavesView: View {
    enum Kind: Sendable {
        /// A band of two lines.
        case line
        /// The same two lines, with as many waves per point as the compact island's (about one in
        /// 21 pt), for the pill Home pushes out from the camera while he talks (ADR-653): what you
        /// see inside Doddy is what the island shows outside it.
        case across
        /// A livelier band: five lines that start together at the leading edge, fade in and
        /// spread out to the right, his voice coming out of him on the expanded island.
        case speech
    }

    let kind: Kind
    /// For `.across` only: the stretch of the drawing, as fractions of its width, that the camera
    /// covers. The lines fade out into it and come back out of it, as if they ran behind the
    /// camera (ADR-653). Nil: they run unbroken.
    var gap: ClosedRange<Double>?
    var phase: Double = 0
    /// Orange only while Doddy is live; grey otherwise, as the island's other signs (ADR-239).
    var live = true

    /// Where the speech lines meet: the middle of their band.
    static let speechCentre = 0.5

    var body: some View {
        let colour = live ? Color.islandOrange : Color.islandSecondary
        ZStack {
            ForEach(Array(Self.waves(kind).enumerated()), id: \.offset) { _, wave in
                let line = IslandWaveLine(wave: wave, shape: shape, phase: phase)
                let style = StrokeStyle(lineWidth: wave.width, lineCap: .round, lineJoin: .round)
                // The fade is in the colour, not a `.opacity` on the view: a view opacity makes
                // SwiftUI composite each line in its own offscreen layer, every frame while he
                // talks (ADR-604). A single stroked line looks the same either way.
                let strength = colour.opacity(wave.opacity)
                if kind == .across, let gap {
                    // Fades at both ends and at the camera, in the colour (ADR-604), so the lines
                    // dissolve into the black instead of stopping.
                    line.stroke(LinearGradient(stops: Self.acrossStops(strength, gap: gap),
                                               startPoint: .leading, endPoint: .trailing), style: style)
                } else if kind == .speech {
                    // Nothing where they meet beside him; full strength from 15 % of the way.
                    line.stroke(LinearGradient(stops: [
                        .init(color: colour.opacity(0), location: 0),
                        .init(color: strength, location: 0.15),
                        .init(color: strength, location: 0.85),
                        .init(color: colour.opacity(0.4 * wave.opacity), location: 1),
                    ], startPoint: .leading, endPoint: .trailing), style: style)
                } else {
                    line.stroke(strength, style: style)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Gradient stops for `.across`: transparent at the left end, full from 10 %, fading into the
    /// camera's gap, out of it on the other side, full again and transparent at the right end.
    /// Locations never go backwards, whatever the gap (a gap that is nearly the whole drawing
    /// leaves only the two ends).
    static func acrossStops(_ colour: Color, gap: ClosedRange<Double>) -> [Gradient.Stop] {
        let edge = 0.10, soft = 0.06
        let lower = min(0.5, max(edge + soft, gap.lowerBound))
        let upper = 1 - lower
        return [
            .init(color: colour.opacity(0), location: 0),
            .init(color: colour, location: edge),
            .init(color: colour, location: lower - soft),
            .init(color: colour.opacity(0), location: lower),
            .init(color: colour.opacity(0), location: upper),
            .init(color: colour, location: upper + soft),
            .init(color: colour, location: 1 - edge),
            .init(color: colour.opacity(0), location: 1),
        ]
    }

    private var shape: IslandWaveLine.Spread {
        switch kind {
        case .line, .across: .envelope(floor: 0)
        case .speech: .fromLeading(centre: Self.speechCentre)
        }
    }

    /// The lines, in fractions of the drawing's height: two for `.line` and `.across`, five for `.speech`.
    /// Built once: the animated version asks for them on every frame (ADR-604).
    static func waves(_ kind: Kind) -> [IslandWave] {
        switch kind {
        case .line: lineWaves
        case .across: acrossWaves
        case .speech: speechWaves
        }
    }

    private static let lineWaves: [IslandWave] = [
        IslandWave(amplitude: 0.30, frequency: 2, offset: 0, rise: 0, width: 3, opacity: 1),
        IslandWave(amplitude: 0.18, frequency: 3, offset: 1.9, rise: 0, width: 2, opacity: 0.5),
    ]

    /// `lineWaves` with 4.5 times the waves: 2 and 3 in 42 pt become 9 and 13 in about 190 pt.
    private static let acrossWaves: [IslandWave] = lineWaves.map { wave in
        var wave = wave
        wave.frequency *= 4.5
        return wave
    }

    /// The strongest in the middle; each ends up a little above or below it.
    private static let speechWaves: [IslandWave] = [
        IslandWave(amplitude: 0.12, frequency: 2.2, offset: 0, rise: -0.28, width: 2.2, opacity: 0.5),
        IslandWave(amplitude: 0.16, frequency: 2.8, offset: 1.1, rise: -0.14, width: 2.4, opacity: 0.7),
        IslandWave(amplitude: 0.20, frequency: 2.0, offset: 2.2, rise: 0, width: 3, opacity: 1),
        IslandWave(amplitude: 0.16, frequency: 2.6, offset: 3.3, rise: 0.14, width: 2.4, opacity: 0.7),
        IslandWave(amplitude: 0.12, frequency: 2.4, offset: 4.4, rise: 0.28, width: 2.2, opacity: 0.5),
    ]
}

struct IslandWave: Equatable, Sendable {
    var amplitude: Double
    /// Whole waves across the width (fewer on a very narrow drawing, see `IslandWaveLine`).
    var frequency: Double
    var offset: Double
    /// Up or down from the middle, in fractions of the height.
    var rise: Double
    var width: CGFloat
    var opacity: Double
}

/// One sine line.
struct IslandWaveLine: Shape {
    enum Spread: Equatable, Sendable {
        /// Highest in the middle, fading to `floor` at the ends, around the middle of the height.
        case envelope(floor: Double)
        /// Starts at `centre` with no height and spreads to its rise and full height by 40 % of
        /// the way.
        case fromLeading(centre: Double)
    }

    let wave: IslandWave
    let shape: Spread
    var phase: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    /// A wave is never shorter than six line widths, so a thick line on a narrow drawing (the
    /// compact island) stays a wave instead of filling in.
    static func waveCount(_ wave: IslandWave, width: CGFloat) -> Double {
        min(wave.frequency, Double(width / max(1, wave.width * 6)))
    }

    /// 0 to 1 between `a` and `b`, eased at both ends.
    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// The line's height at `along` (0 at the leading edge, 1 at the trailing), in fractions of
    /// the drawing's height from its top.
    func y(at along: Double, waves: Double) -> Double {
        let sine = sin(2 * .pi * waves * along + wave.offset + phase)
        switch shape {
        case .envelope(let floor):
            let envelope = floor + (1 - floor) * sin(.pi * along)
            return 0.5 + wave.rise + wave.amplitude * envelope * sine
        case .fromLeading(let centre):
            let spread = Self.smoothstep(0, 0.4, along)
            return centre + (wave.rise + wave.amplitude * sine) * spread
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0 else { return path }
        let waves = Self.waveCount(wave, width: rect.width)
        let step: CGFloat = 0.5
        var x: CGFloat = 0
        while true {
            let point = CGPoint(x: rect.minX + x,
                                y: rect.minY + CGFloat(y(at: Double(x / rect.width), waves: waves)) * rect.height)
            if x == 0 { path.move(to: point) } else { path.addLine(to: point) }
            guard x < rect.width else { break }
            x = min(rect.width, x + step)
        }
        return path
    }
}
