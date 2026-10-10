import ActivityKit
import AppIntents
import Foundation

/// Lets the Live Activity buttons reach the running conversation. These intents must run in the
/// app's process (the app is alive because it is in a conversation with background audio),
/// where `VoiceSessionController` registers these handlers. The widget extension has its own,
/// separate copy of this object whose handlers stay nil, so an intent performed there does
/// nothing (ADR-131). Both intents therefore pin `allowedExecutionTargets` to `.main`.
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

    #if compiler(>=6.4)
    /// iOS 27 performs an intent in "any available target" by default, and this type is compiled
    /// into the widget extension too (the buttons need it). Only the app has the handlers (ADR-131).
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

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

    #if compiler(>=6.4)
    /// See `EndDoddyConversationIntent.allowedExecutionTargets` (ADR-131).
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await VoiceActivityActions.shared.toggleMute?()
        return .result()
    }
}
