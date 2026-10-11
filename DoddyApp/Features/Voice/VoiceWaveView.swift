import SwiftUI

/// The sound wave beside Doddy on the voice screen (ADR-442). Seven bars whose look says whose
/// turn it is (`VoiceWave`). In an ElevenLabs conversation their height also follows how loud your
/// microphone or Doddy's voice is (`VoiceLevelMeters`, ADR-443). Without a reading (the OpenAI test
/// voice, or no sound yet) they show the phase's pattern only, which is not a loudness. With
/// Reduce Motion the bars stand still at the shape of the current mode. Decorative: the status
/// text says the same.
struct VoiceWaveView: View {
    let mode: VoiceWave.Mode
    /// The measured loudness of the conversation, when there is one (ElevenLabs); nil shows the
    /// phase's pattern only.
    var levels: VoiceLevelMeters?
    var height: CGFloat = 64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Paused while the app isn't in front, so it never redraws for nobody.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || mode == .flat || scenePhase != .active)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            // One reading per frame for all the bars. With Reduce Motion nothing is redrawn, so no reading.
            let signal = reduceMotion ? nil : levels?.signal(for: mode)
            HStack(alignment: .center, spacing: 5) {
                ForEach(0..<VoiceWave.barCount, id: \.self) { bar in
                    Capsule()
                        .fill(color)
                        .frame(width: 6, height: max(6, height * VoiceWave.level(bar: bar, mode: mode, at: seconds, still: reduceMotion, signal: signal)))
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
