import ActivityKit
import AppIntents
import DoddyCore
import Foundation
import os
#if canImport(UIKit) && !DODDY_WIDGET_EXTENSION
import UIKit
#endif

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
        // The conversation ends itself and leaves a short "Conversation ended" card.
        await handler?()
        // Anything still claiming to be live has no conversation behind it (iOS ended the
        // process in the background, or this is a fresh launch just to run the intent). The
        // island must still go away, so end it. The "ended" card is left alone.
        var leftovers = 0
        for activity in Activity<DoddyVoiceAttributes>.activities where !activity.content.state.isEnded {
            await activity.end(nil, dismissalPolicy: .immediate)
            leftovers += 1
        }
        IslandIntentLog.performed("End", handled: handler != nil, leftoverActivitiesEnded: leftovers)
        return .result()
    }
}

/// "Mute" in the Dynamic Island / Lock Screen. Open on a locked iPhone: anyone may silence Doddy.
/// It only ever mutes (`IslandMute`): when the island already shows him muted it does nothing. Does
/// nothing when no conversation is running in this process; the island then shows its stale state and
/// only End is offered.
struct MuteDoddyIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mute Doddy"
    static let isDiscoverable = false

    #if compiler(>=6.4)
    /// See `EndDoddyConversationIntent.allowedExecutionTargets` (ADR-131).
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await IslandMuteButton.press(.mute)
        return .result()
    }
}

/// "Unmute" in the Dynamic Island / Lock Screen. Starts Doddy listening again, so iOS asks for Face ID
/// or the passcode first on a locked iPhone (`IslandMute.needsUnlockedIPhone`), the way a widget's list
/// tick does; the app checks again that the iPhone is unlocked when it runs. It only ever unmutes.
struct UnmuteDoddyIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Unmute Doddy"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    #if compiler(>=6.4)
    /// See `EndDoddyConversationIntent.allowedExecutionTargets` (ADR-131).
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await IslandMuteButton.press(.unmute)
        return .result()
    }
}

/// What both island buttons do in the app's process: read what the island shows, ask `IslandMute`,
/// and flip the conversation's mute only when it says so. The log line names the button and the
/// outcome, nothing from the conversation.
@MainActor
enum IslandMuteButton {
    static func press(_ button: IslandMute.Button) async {
        let handler = VoiceActivityActions.shared.toggleMute
        let decision = IslandMute.decide(button, shownMuted: shownMuted, iPhoneUnlocked: ProtectedData.isAvailable)
        let name = button == .mute ? "Mute" : "Unmute"
        switch decision {
        case .toggle:
            IslandIntentLog.performed(name, handled: handler != nil)
            await handler?()
        case .nothing:
            IslandIntentLog.performed("\(name) (already so)", handled: handler != nil)
        case .refusedLocked:
            // The microphone stays off; the island keeps showing Muted and Unmute.
            IslandIntentLog.performed("\(name) refused: iPhone locked", handled: handler != nil)
        }
    }

    /// What the conversation's island shows now, or nil when this process has none running.
    private static var shownMuted: Bool? {
        Activity<DoddyVoiceAttributes>.activities.first { !$0.content.state.isEnded }?.content.state.isMuted
    }
}

/// Whether iOS says the iPhone's protected data can be read now, which is false while the iPhone is
/// locked (it has a passcode). Only the app can ask; anywhere else it answers false, so nothing that
/// needs an unlocked iPhone goes ahead there.
@MainActor
enum ProtectedData {
    static var isAvailable: Bool {
        #if canImport(UIKit) && !DODDY_WIDGET_EXTENSION
        UIApplication.shared.isProtectedDataAvailable
        #else
        false
        #endif
    }
}
