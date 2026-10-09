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
        await VoiceActivityActions.shared.endConversation?()
        // No handler means the process that ran the conversation is gone (iOS ended it in the
        // background, or this is a fresh launch just to run the intent). The island must still
        // go away, so end whatever is left.
        for activity in Activity<DoddyVoiceAttributes>.activities {
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
