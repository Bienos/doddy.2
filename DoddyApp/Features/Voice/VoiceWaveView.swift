import SwiftUI

/// The sound wave beside Doddy on the voice screen (ADR-442). Seven bars that follow whose turn
/// it is (`VoiceWave`), not the audio itself: the app doesn't measure the microphone or Doddy's
/// voice here, so the height says "listening" or "speaking", never "how loud". With Reduce Motion
/// the bars stand still at the shape of the current mode. Decorative: the status text says the same.
struct VoiceWaveView: View {
    let mode: VoiceWave.Mode
    var height: CGFloat = 64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Paused while the app isn't in front, so it never redraws for nobody.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || mode == .flat || scenePhase != .active)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 5) {
                ForEach(0..<VoiceWave.barCount, id: \.self) { bar in
                    Capsule()
                        .fill(color)
                        .frame(width: 6, height: max(6, height * VoiceWave.level(bar: bar, mode: mode, at: seconds, still: reduceMotion)))
                }
            }
            .frame(height: height)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: mode)
        .accessibilityHidden(true)
        .accessibilityIdentifier("voice.wave")
    }

    /// Doddy's orange is decoration only (Theme), fine for bars; the words beside carry the meaning.
    private var color: Color {
        mode == .speaking ? Theme.orangeCue : Theme.secondaryText.opacity(mode == .flat ? 0.35 : 0.8)
    }
}
