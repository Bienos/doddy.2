import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Dynamic Island + Lock Screen presentation of an open voice conversation.
/// It is a status display with two buttons, not a chat window. Text and symbols only: the
/// candidate character art stays in the app, where the "Hide character artwork" setting applies.
struct VoiceLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoiceActivityAttributes.self) { context in
            lockScreen(context)
                .padding(16)
                .activityBackgroundTint(.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let presentation = Presentation(context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: presentation.symbol)
                        .font(.title2)
                        .foregroundStyle(presentation.tint)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .monospacedDigit()
                        .font(.subheadline)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 64, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(presentation.title)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    controls(isMuted: context.state.isMuted)
                }
            } compactLeading: {
                Image(systemName: presentation.symbol)
                    .foregroundStyle(presentation.tint)
            } compactTrailing: {
                Text(context.attributes.startedAt, style: .timer)
                    .monospacedDigit()
                    .font(.caption2)
                    .frame(width: 38)
            } minimal: {
                Image(systemName: presentation.symbol)
                    .foregroundStyle(presentation.tint)
            }
            .keylineTint(presentation.tint)
        }
    }

    private func lockScreen(_ context: ActivityViewContext<VoiceActivityAttributes>) -> some View {
        let presentation = Presentation(context.state)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: presentation.symbol)
                    .font(.title2)
                    .foregroundStyle(presentation.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Doddy")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(presentation.title)
                        .font(.headline)
                }
                Spacer()
                Text(context.attributes.startedAt, style: .timer)
                    .monospacedDigit()
                    .font(.subheadline)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 64, alignment: .trailing)
            }
            controls(isMuted: context.state.isMuted)
        }
    }

    private func controls(isMuted: Bool) -> some View {
        HStack(spacing: 12) {
            Button(intent: ToggleVoiceMuteIntent()) {
                Label(isMuted ? "Unmute" : "Mute", systemImage: isMuted ? "mic.slash.fill" : "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            Button(intent: EndVoiceConversationIntent()) {
                Label("End", systemImage: "phone.down.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
        }
        .buttonStyle(.bordered)
    }

    /// Wording and symbol for each state. Muted wins over "Listening": a muted microphone is not
    /// listening, and the island must not say it is.
    private struct Presentation {
        let title: String
        let symbol: String
        let tint: Color

        init(_ state: VoiceActivityAttributes.ContentState) {
            if state.isMuted && state.phase == .listening {
                title = "Muted"; symbol = "mic.slash.fill"; tint = .orange
                return
            }
            switch state.phase {
            case .connecting: title = "Connecting…"; symbol = "ellipsis"; tint = .gray
            case .listening: title = "Listening"; symbol = "waveform"; tint = .green
            case .thinking: title = "Thinking…"; symbol = "ellipsis"; tint = .yellow
            case .speaking: title = "Speaking"; symbol = "speaker.wave.2.fill"; tint = .blue
            }
        }
    }
}
