import ActivityKit
import AppIntents
import Foundation
import os

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

/// Records which process performed an island button, so a Mac run of the red Unmute check
/// (`NATIVE_BASELINE_REPORT.md`, ADR-131) can tell routing from a dead handler. Only the bundle
/// identifier of the running process and whether a conversation handler was registered there;
/// nothing from the conversation. Console: subsystem `com.bienos.doddy2`, category `island`.
enum IslandIntentLog {
    static func performed(_ intent: String, handled: Bool, leftoverActivitiesEnded: Int? = nil) {
        let process = Bundle.main.bundleIdentifier ?? "unknown"
        let logger = Logger(subsystem: "com.bienos.doddy2", category: "island")
        if let leftoverActivitiesEnded {
            logger.info("\(intent, privacy: .public) performed in \(process, privacy: .public); conversation handler: \(handled ? "yes" : "no", privacy: .public); leftover activities ended: \(leftoverActivitiesEnded, privacy: .public)")
        } else {
            logger.info("\(intent, privacy: .public) performed in \(process, privacy: .public); conversation handler: \(handled ? "yes" : "no", privacy: .public)")
        }
    }
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
        let handler = VoiceActivityActions.shared.endConversation
        // The conversation ends itself and leaves a short "Conversation ended" card. With
        // "Hey Doddy" listening (ADR-254) this is Stop listening, which turns it off.
        await handler?()
        // Anything still claiming to be live has no conversation behind it (iOS ended the
        // process in the background, or this is a fresh launch just to run the intent). The
        // island must still go away, so end it. The "ended" card is left alone, and so is
        // "Hey Doddy" listening that the running app just took back after the conversation.
        var leftovers = 0
        for activity in Activity<DoddyVoiceAttributes>.activities where !activity.content.state.isEnded {
            if handler != nil && activity.content.state.isWakeMode { continue }
            await activity.end(nil, dismissalPolicy: .immediate)
            leftovers += 1
        }
        IslandIntentLog.performed("End", handled: handler != nil, leftoverActivitiesEnded: leftovers)
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
        let handler = VoiceActivityActions.shared.toggleMute
        IslandIntentLog.performed("Mute/Unmute", handled: handler != nil)
        await handler?()
        return .result()
    }
}
