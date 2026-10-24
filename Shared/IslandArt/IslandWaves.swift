import SwiftUI

/// Doddy's orange waves (owner, 22 Oct 2026, ADR-596; Figma file `yqoQlkN6BpevFGW3ySnNJU`, page
/// "Wyspa i wiadomości"): sine lines that say he hears you (`.line`, beside his status) or that he
/// is talking (`.speech` on the expanded island, `.full` in the Home extension). `phase` moves
/// them along. The island draws them still, because a Live Activity can't run an animation of
/// its own between updates; the app's island extension on Home moves them (`IslandExtension`).
///
/// Bolder since 24 Oct (owner: the lines were too thin and rendered poorly, ADR-607): fewer lines,
/// 2 to 3 pt wide instead of 1.3 to 2.2, and drawn from a point every half point instead of every
/// two, so a small wave is a curve and not a zigzag. On the expanded island his talking waves
/// stay in the band under his status, as his listening line does, start beside him and spread
/// out to the right (owner: not across the whole island, and they should end before him).
struct IslandWavesView: View {
    enum Kind: Sendable {
        /// A band of two lines.
        case line
        /// Lines across the whole drawing (the Home extension while he talks).
        case full
        /// A livelier band: five lines that start together at the leading edge, fade in and
        /// spread out to the right, his voice coming out of him on the expanded island.
        case speech
    }

    let kind: Kind
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
                Group {
                    if kind == .speech {
                        // Nothing where they meet beside him; full strength from 15 % of the way.
                        line.stroke(LinearGradient(stops: [
                            .init(color: colour.opacity(0), location: 0),
                            .init(color: colour, location: 0.15),
                            .init(color: colour, location: 0.85),
                            .init(color: colour.opacity(0.4), location: 1),
                        ], startPoint: .leading, endPoint: .trailing), style: style)
                    } else {
                        line.stroke(colour, style: style)
                    }
                }
                .opacity(wave.opacity)
            }
        }
        .accessibilityHidden(true)
    }

    private var shape: IslandWaveLine.Spread {
        switch kind {
        case .line: .envelope(floor: 0)
        case .full: .envelope(floor: 0.45)
        case .speech: .fromLeading(centre: Self.speechCentre)
        }
    }

    /// The lines, in fractions of the drawing's height: two for `.line`, five for `.speech`,
    /// seven for `.full`.
    static func waves(_ kind: Kind) -> [IslandWave] {
        switch kind {
        case .line:
            [IslandWave(amplitude: 0.30, frequency: 2, offset: 0, rise: 0, width: 3, opacity: 1),
             IslandWave(amplitude: 0.18, frequency: 3, offset: 1.9, rise: 0, width: 2, opacity: 0.5)]
        case .full:
            // Lighter at the top; strongest at the bottom.
            (0..<7).map { i in
                let n = Double(i)
                return IslandWave(amplitude: 0.10 + 0.012 * n, frequency: 1.4 + 0.3 * n, offset: 0.9 * n,
                                  rise: (n - 3) * 0.10, width: 2.2, opacity: 0.3 + 0.1 * n)
            }
        case .speech:
            // The strongest in the middle; each ends up a little above or below it.
            [IslandWave(amplitude: 0.12, frequency: 2.2, offset: 0, rise: -0.28, width: 2.2, opacity: 0.5),
             IslandWave(amplitude: 0.16, frequency: 2.8, offset: 1.1, rise: -0.14, width: 2.4, opacity: 0.7),
             IslandWave(amplitude: 0.20, frequency: 2.0, offset: 2.2, rise: 0, width: 3, opacity: 1),
             IslandWave(amplitude: 0.16, frequency: 2.6, offset: 3.3, rise: 0.14, width: 2.4, opacity: 0.7),
             IslandWave(amplitude: 0.12, frequency: 2.4, offset: 4.4, rise: 0.28, width: 2.2, opacity: 0.5)]
        }
    }
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
