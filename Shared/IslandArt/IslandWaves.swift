import SwiftUI

/// Doddy's orange waves (owner, 22 Oct 2026, ADR-580; Figma file `yqoQlkN6BpevFGW3ySnNJU`, page
/// "Wyspa i wiadomości"): sine lines that say he hears you (`.line`, beside his status) or that he
/// is talking (`.full`, across the whole expanded island). `phase` moves them along. The island
/// draws them still, because a Live Activity can't run an animation of its own between updates;
/// the app's island extension on Home moves them (`IslandExtension`).
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
                            style: StrokeStyle(lineWidth: wave.width, lineCap: .round))
                    .opacity(wave.opacity)
            }
        }
        .accessibilityHidden(true)
    }

    /// The lines, in fractions of the drawing's height: three for `.line`, nine for `.full`.
    static func waves(_ kind: Kind) -> [IslandWave] {
        switch kind {
        case .line:
            [IslandWave(amplitude: 0.30, frequency: 2, offset: 0, rise: 0, width: 2.2, opacity: 1),
             IslandWave(amplitude: 0.20, frequency: 3, offset: 1.2, rise: 0, width: 1.8, opacity: 0.55),
             IslandWave(amplitude: 0.13, frequency: 4.5, offset: 2.4, rise: 0, width: 1.4, opacity: 0.3)]
        case .full:
            (0..<9).map { i in
                let n = Double(i)
                return IslandWave(amplitude: 0.10 + 0.012 * n, frequency: 1.5 + 0.25 * n, offset: 0.7 * n,
                                  rise: (n - 4) * 0.11, width: 1.3, opacity: 0.15 + 0.08 * n)
            }
        }
    }
}

struct IslandWave: Equatable, Sendable {
    var amplitude: Double
    /// Whole waves across the width.
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

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0 else { return path }
        let step: CGFloat = 2
        var x: CGFloat = 0
        while x <= rect.width {
            let along = Double(x / rect.width)
            let envelope = envelopeFloor + (1 - envelopeFloor) * sin(.pi * along)
            let y = rect.midY + CGFloat(wave.rise) * rect.height
                + CGFloat(wave.amplitude * envelope * sin(2 * .pi * wave.frequency * along + wave.offset + phase)) * rect.height
            let point = CGPoint(x: rect.minX + x, y: y)
            if x == 0 { path.move(to: point) } else { path.addLine(to: point) }
            x += step
        }
        return path
    }
}
