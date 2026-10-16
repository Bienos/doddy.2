import ActivityKit
import AppIntents
import Foundation

/// Lets the tool island's buttons reach the focus timer, breathing or read-aloud running in the
/// app, the same way as the conversation's buttons (`VoiceActivityActions`, ADR-131): the
/// intents run in the app's process, where the controllers register these handlers. The focus
/// timer registers at launch from its saved state, so Pause and Stop work even after iOS ended
/// the app and launched it again just to run the intent.
@MainActor
final class ToolActivityActions {
    static let shared = ToolActivityActions()

    var togglePause: [DoddyToolAttributes.Kind: @MainActor () async -> Void] = [:]
    var stop: [DoddyToolAttributes.Kind: @MainActor () async -> Void] = [:]
    var cancelTimer: (@MainActor (String) async -> Bool)?
}

/// "Pause" / "Resume" on the focus or read-aloud island.
struct ToggleDoddyToolPauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or resume"
    static let isDiscoverable = false

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Tool") var kind: String

    init() {
        kind = DoddyToolAttributes.Kind.focus.rawValue
    }
    init(_ kind: DoddyToolAttributes.Kind) {
        self.kind = kind.rawValue
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let kind = DoddyToolAttributes.Kind(rawValue: kind) {
            await ToolActivityActions.shared.togglePause[kind]?()
        }
        return .result()
    }
}

/// "Stop" on a tool island. If nothing in this process handles it (the tool is gone), the
/// island is still removed, so it never claims something is running that isn't.
struct StopDoddyToolIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop"
    static let isDiscoverable = false

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Tool") var kind: String
    @Parameter(title: "Timer notification") var timerNotificationID: String?

    init() {
        kind = DoddyToolAttributes.Kind.focus.rawValue
        timerNotificationID = nil
    }
    init(_ kind: DoddyToolAttributes.Kind, timerNotificationID: String? = nil) {
        self.kind = kind.rawValue
        self.timerNotificationID = timerNotificationID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let kind = DoddyToolAttributes.Kind(rawValue: kind) else { return .result() }
        if kind == .timer {
            guard let timerNotificationID,
                  let cancelTimer = ToolActivityActions.shared.cancelTimer else {
                await markTimerCancellationUnconfirmed()
                return .result()
            }
            if !(await cancelTimer(timerNotificationID)) { await markTimerCancellationUnconfirmed() }
            return .result()
        }
        if let stop = ToolActivityActions.shared.stop[kind] {
            await stop()
        } else {
            for activity in Activity<DoddyToolAttributes>.activities where activity.attributes.kind == kind {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        return .result()
    }

    @MainActor
    private func markTimerCancellationUnconfirmed() async {
        guard let timerNotificationID else { return }
        for activity in Activity<DoddyToolAttributes>.activities
            where activity.attributes.kind == .timer && activity.attributes.timerNotificationID == timerNotificationID {
            var state = activity.content.state
            state.cancellationUnconfirmed = true
            await activity.update(ActivityContent(state: state, staleDate: state.endsAt))
        }
    }
}

/// Dismisses a completed or stale timer without trying to cancel an alert that may already have
/// fired or implying the timer stopped early.
struct DismissDoddyTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Dismiss timer"
    static let isDiscoverable = false

    @Parameter(title: "Timer notification") var timerNotificationID: String?

    init() { timerNotificationID = nil }
    init(timerNotificationID: String?) { self.timerNotificationID = timerNotificationID }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let timerNotificationID else { return .result() }
        for activity in Activity<DoddyToolAttributes>.activities
            where activity.attributes.kind == .timer
                && activity.attributes.timerNotificationID == timerNotificationID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}
