import ActivityKit
import AppIntents
import Foundation

/// Lets the Live Activity buttons reach the running conversation. `LiveActivityIntent`s run in
/// the app's process (the app is alive because it is in a conversation with background audio),
/// where `VoiceSessionController` registers these handlers. In the widget extension they stay
/// nil and are never called.
@MainActor
final class VoiceActivityActions {
    static let shared = VoiceActivityActions()

    var endConversation: (@MainActor () async -> Void)?
    var toggleMute: (@MainActor () async -> Void)?
}

/// "End" in the Dynamic Island / Lock Screen.
struct EndDoddyConversationIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End conversation with Doddy"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        // The conversation ends itself and leaves a short "Conversation ended" card.
        await VoiceActivityActions.shared.endConversation?()
        // Anything still claiming to be live has no conversation behind it (iOS ended the
        // process in the background, or this is a fresh launch just to run the intent). The
        // island must still go away, so end it. The "ended" card is left alone.
        for activity in Activity<DoddyVoiceAttributes>.activities where !activity.content.state.isEnded {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}

/// "Mute" / "Unmute" in the Dynamic Island / Lock Screen. Does nothing when no conversation is
/// running in this process; the island then shows its stale state and only End is offered.
struct ToggleDoddyMuteIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mute or unmute Doddy"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await VoiceActivityActions.shared.toggleMute?()
        return .result()
    }
}
