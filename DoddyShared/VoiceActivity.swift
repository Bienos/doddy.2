import ActivityKit
import AppIntents
import Foundation

// Compiled into BOTH the app and the DoddyWidgets extension. Keep it free of app-only types.

/// What the Dynamic Island / Lock Screen shows while a voice conversation is open.
struct VoiceActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Mirrors the real conversation phase. Only phases in which the conversation is
        /// actually live exist here; when it ends the Live Activity ends too.
        enum Phase: String, Codable, Hashable {
            case connecting, listening, thinking, speaking
        }

        var phase: Phase
        var isMuted: Bool
    }

    /// When the conversation was opened (drives the elapsed-time label).
    var startedAt: Date
}

enum VoiceActivityCommand: Sendable {
    case end, toggleMute
}

/// Lets the Live Activity buttons reach the running conversation. The intents below execute in
/// the app's process (that is what `LiveActivityIntent` means); the widget extension only
/// compiles them to draw the buttons, so nothing is registered there and nothing runs there.
@MainActor
final class VoiceActivityBridge {
    typealias Handler = @MainActor (VoiceActivityCommand) async -> Void

    static let shared = VoiceActivityBridge()
    private var handler: Handler?

    func register(_ handler: @escaping Handler) { self.handler = handler }
    func clear() { handler = nil }

    func send(_ command: VoiceActivityCommand) async {
        if let handler {
            await handler(command)
        } else if case .end = command {
            // No conversation is running in this process (the app was relaunched), so the
            // activity is stale. Never leave a "listening" indicator on screen.
            for activity in Activity<VoiceActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}

struct EndVoiceConversationIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End conversation"

    func perform() async throws -> some IntentResult {
        await VoiceActivityBridge.shared.send(.end)
        return .result()
    }
}

struct ToggleVoiceMuteIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mute or unmute"

    func perform() async throws -> some IntentResult {
        await VoiceActivityBridge.shared.send(.toggleMute)
        return .result()
    }
}
