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
            /// "Hey Doddy" is on (ADR-234): the iPhone listens on the device for the wake word
            /// only. No conversation is running and nothing is sent anywhere.
            case wakeListening
            /// "Hey Doddy" is on but not listening for a moment: a call or another app has the
            /// microphone, or a conversation is still letting go of it.
            case wakePaused
            /// Doddy proposed a note and waits for Save / Don't save on the app's screen.
            case needsConfirmation
            /// The final state after End or a lost connection: shown briefly on the Lock Screen
            /// (the Dynamic Island drops ended activities at once). Doddy is not listening.
            case ended
            #if DEBUG
            /// Native lifecycle fixture only; never represents microphone or provider state.
            case testFixture
            #endif
        }

        var status: Status
        var isMuted: Bool
        /// Notes the user tapped Save on in this conversation. Shown only when it has ended.
        var savedCount: Int = 0
        /// Set with `.ended`, for the "2:31 total" line.
        var endedAt: Date?
        /// "Hey Pat, what's up?" after the wake word (ADR-234), shown instead of "Connecting…" /
        /// "Listening" until the user first speaks. Only the greeting, never anything said.
        var greeting: String?
        /// When this conversation started, if the activity began earlier as "Hey Doddy"
        /// listening (one activity carries both, because iOS can't start one in the background).
        var conversationStartedAt: Date?
    }

    /// When the activity started: the conversation, or "Hey Doddy" listening (ADR-234).
    var startedAt: Date
}

extension DoddyVoiceAttributes.ContentState {
    private enum CodingKeys: String, CodingKey {
        case status, isMuted, savedCount, endedAt, greeting, conversationStartedAt
    }

    /// Content written by a build from before `savedCount`/`endedAt`/`greeting` existed still decodes.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(Status.self, forKey: .status)
        isMuted = try container.decode(Bool.self, forKey: .isMuted)
        savedCount = try container.decodeIfPresent(Int.self, forKey: .savedCount) ?? 0
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        greeting = try container.decodeIfPresent(String.self, forKey: .greeting)
        conversationStartedAt = try container.decodeIfPresent(Date.self, forKey: .conversationStartedAt)
    }

    /// "Hey Doddy" listening (ADR-234): the iPhone waits for the wake word; no conversation.
    static let wakeListening = Self(status: .wakeListening, isMuted: false)
    static let wakePaused = Self(status: .wakePaused, isMuted: false)

    var isEnded: Bool { status == .ended }
    /// "Hey Doddy" waiting or paused: not a conversation, so no timer, no Mute, Stop listening.
    var isWakeMode: Bool { status == .wakeListening || status == .wakePaused }

    /// Muted only means something while the conversation runs and nothing waits in the app.
    var showsMuted: Bool { isMuted && status != .needsConfirmation && status != .ended && !isWakeMode }

    /// The greeting replaces only the first two statuses, so it never hides Thinking, Speaking,
    /// Muted or a card waiting in the app.
    private var showsGreeting: Bool {
        guard let greeting, !greeting.isEmpty, !showsMuted else { return false }
        return status == .connecting || status == .listening
    }

    /// For the elapsed time: the conversation's own start when it began after "Hey Doddy".
    func conversationStart(activityStartedAt: Date) -> Date {
        conversationStartedAt ?? activityStartedAt
    }

    /// Short label for the island and Lock Screen.
    var title: String {
        #if DEBUG
        if status == .testFixture { return isMuted ? "Test muted" : "Test activity" }
        #endif
        if showsMuted { return "Muted" }
        if showsGreeting, let greeting { return greeting }
        switch status {
        case .connecting: return "Connecting…"
        case .listening: return "Listening"
        case .wakeListening: return "Say “Hey Doddy”"
        case .wakePaused: return "“Hey Doddy” paused"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking"
        case .needsConfirmation: return "Confirm in Doddy"
        case .ended: return "Conversation ended"
        #if DEBUG
        case .testFixture: return "Test activity"
        #endif
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
        case .wakeListening: return "Listening on this iPhone for “Hey Doddy” only"
        case .wakePaused: return "Not listening right now"
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
        case .wakeListening: return "ear"
        case .wakePaused: return "pause.circle"
        #if DEBUG
        case .testFixture: return isMuted ? "mic.slash.fill" : "wrench.and.screwdriver"
        #endif
        }
    }

    /// The orange cue means "Doddy is live and can hear you" and nothing else.
    var isLiveCue: Bool {
        #if DEBUG
        if status == .testFixture { return false }
        #endif
        // "Hey Doddy" listening is not a conversation: nothing is sent and Doddy isn't talking
        // with you, so it gets its own quiet look (iOS still shows its microphone dot).
        return !showsMuted && !isEnded && status != .needsConfirmation && !isWakeMode
    }
}
