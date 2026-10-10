import ActivityKit
import Foundation

/// The Live Activity (Dynamic Island and Lock Screen) for a voice conversation that is running.
/// Compiled into the app, which starts, updates and ends it, and into the DoddyWidgets
/// extension, which draws it. The status only ever mirrors real SDK events in
/// `VoiceSessionController`; the activity ends as soon as the conversation does.
/// Nothing said in the conversation is put in here: the Lock Screen is visible to anyone.
struct DoddyVoiceAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Status: String, Codable, Hashable {
            case connecting, listening, thinking, speaking
            /// Doddy proposed a note and waits for Save / Don't save on the app's screen.
            case needsConfirmation
            /// The final state after End or a lost connection: shown briefly on the Lock Screen
            /// (the Dynamic Island drops ended activities at once). Doddy is not listening.
            case ended
        }

        var status: Status
        var isMuted: Bool
        /// Notes the user tapped Save on in this conversation. Shown only when it has ended.
        var savedCount: Int = 0
        /// Set with `.ended`, for the "2:31 total" line.
        var endedAt: Date?
    }

    /// When the conversation started, for the elapsed-time counter.
    var startedAt: Date
}

extension DoddyVoiceAttributes.ContentState {
    var isEnded: Bool { status == .ended }

    /// Muted only means something while the conversation runs and nothing waits in the app.
    var showsMuted: Bool { isMuted && status != .needsConfirmation && status != .ended }

    /// Short label for the island and Lock Screen.
    var title: String {
        if showsMuted { return "Muted" }
        switch status {
        case .connecting: return "Connecting…"
        case .listening: return "Listening"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking"
        case .needsConfirmation: return "Confirm in Doddy"
        case .ended: return "Conversation ended"
        }
    }

    /// Second line on the Lock Screen, when there is something true to add.
    var detail: String? {
        if showsMuted { return "Doddy can't hear you" }
        switch status {
        case .ended:
            switch savedCount {
            case 0: return "Doddy isn't listening · nothing saved"
            case 1: return "Doddy isn't listening · 1 note saved"
            default: return "Doddy isn't listening · \(savedCount) notes saved"
            }
        case .needsConfirmation: return "Open Doddy to Save or Don't save"
        default: return nil
        }
    }

    var symbolName: String {
        if showsMuted { return "mic.slash.fill" }
        switch status {
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .listening: return "waveform"
        case .thinking: return "ellipsis"
        case .speaking: return "speaker.wave.2.fill"
        case .needsConfirmation: return "hand.tap.fill"
        case .ended: return "checkmark.circle"
        }
    }

    /// The orange cue means "Doddy is live and can hear you" and nothing else.
    var isLiveCue: Bool { !showsMuted && !isEnded && status != .needsConfirmation }
}
