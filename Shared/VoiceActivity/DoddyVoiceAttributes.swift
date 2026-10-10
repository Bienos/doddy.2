import ActivityKit
import Foundation

/// The Live Activity (Dynamic Island and Lock Screen) for a voice conversation that is running.
/// Compiled into the app, which starts, updates and ends it, and into the DoddyWidgets
/// extension, which draws it. The status only ever mirrors real SDK events in
/// `VoiceSessionController`; the activity ends as soon as the conversation does.
struct DoddyVoiceAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Status: String, Codable, Hashable {
            case connecting, listening, thinking, speaking
            /// Doddy proposed a note and waits for Save / Don't save on the app's screen.
            case needsConfirmation
        }

        var status: Status
        var isMuted: Bool
    }

    /// When the conversation started, for the elapsed-time counter.
    var startedAt: Date
}

extension DoddyVoiceAttributes.ContentState {
    /// Short label for the island and Lock Screen.
    var title: String {
        if isMuted, status != .needsConfirmation { return "Muted" }
        switch status {
        case .connecting: return "Connecting…"
        case .listening: return "Listening"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking"
        case .needsConfirmation: return "Confirm in Doddy"
        }
    }

    var symbolName: String {
        if isMuted, status != .needsConfirmation { return "mic.slash.fill" }
        switch status {
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .listening: return "waveform"
        case .thinking: return "ellipsis"
        case .speaking: return "speaker.wave.2.fill"
        case .needsConfirmation: return "hand.tap.fill"
        }
    }
}
