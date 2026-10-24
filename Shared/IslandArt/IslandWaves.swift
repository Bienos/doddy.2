import SwiftUI

/// Doddy's orange waves (owner, 22 Oct 2026, ADR-596; Figma file `yqoQlkN6BpevFGW3ySnNJU`, page
/// "Wyspa i wiadomości"): sine lines that say he hears you (`.line`, beside his status) or that he
/// is talking (`.full`, across the whole expanded island). `phase` moves them along. The island
/// draws them still, because a Live Activity can't run an animation of its own between updates;
/// the app's island extension on Home moves them (`IslandExtension`).
///
/// Bolder since 24 Oct (owner: the lines were too thin and rendered poorly, ADR-607): fewer lines,
/// 2 to 3 pt wide instead of 1.3 to 2.2, and drawn from a point every half point instead of every
/// two, so a small wave is a curve and not a zigzag.
struct IslandWavesView: View {
    enum Kind: Sendable {
        case line, full
    }

    let kind: Kind
    var phase: Double = 0
    /// Orange only while Doddy is live; grey otherwise, as the island's other signs (ADR-239).
    var live = true

    var body: some View {
        ZStack {
            ForEach(Array(Self.waves(kind).enumerated()), id: \.offset) { _, wave in
                IslandWaveLine(wave: wave, envelopeFloor: kind == .full ? 0.45 : 0, phase: phase)
                    .stroke(live ? Color.islandOrange : Color.islandSecondary,
                            style: StrokeStyle(lineWidth: wave.width, lineCap: .round, lineJoin: .round))
                    .opacity(wave.opacity)
            }
        }
        .accessibilityHidden(true)
    }

    /// The lines, in fractions of the drawing's height: two for `.line`, seven for `.full`.
    static func waves(_ kind: Kind) -> [IslandWave] {
        switch kind {
        case .line:
            [IslandWave(amplitude: 0.34, frequency: 2, offset: 0, rise: 0, width: 3, opacity: 1),
             IslandWave(amplitude: 0.20, frequency: 3, offset: 1.9, rise: 0, width: 2, opacity: 0.5)]
        case .full:
            // Lighter at the top, where his words are; strongest at the bottom.
            (0..<7).map { i in
                let n = Double(i)
                return IslandWave(amplitude: 0.10 + 0.012 * n, frequency: 1.4 + 0.3 * n, offset: 0.9 * n,
                                  rise: (n - 3) * 0.10, width: 2.2, opacity: 0.3 + 0.1 * n)
            }
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

/// One sine line, highest in the middle and fading to `envelopeFloor` at the ends.
struct IslandWaveLine: Shape {
    let wave: IslandWave
    let envelopeFloor: Double
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

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0 else { return path }
        let waves = Self.waveCount(wave, width: rect.width)
        let step: CGFloat = 0.5
        var x: CGFloat = 0
        while true {
            let along = Double(x / rect.width)
            let envelope = envelopeFloor + (1 - envelopeFloor) * sin(.pi * along)
            let y = rect.midY + CGFloat(wave.rise) * rect.height
                + CGFloat(wave.amplitude * envelope * sin(2 * .pi * waves * along + wave.offset + phase)) * rect.height
            let point = CGPoint(x: rect.minX + x, y: y)
            if x == 0 { path.move(to: point) } else { path.addLine(to: point) }
            guard x < rect.width else { break }
            x = min(rect.width, x + step)
        }
        return path
    }
}
