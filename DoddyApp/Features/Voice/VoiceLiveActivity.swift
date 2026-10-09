@preconcurrency import ActivityKit
import Foundation

/// Starts, updates and ends the conversation's Live Activity (Dynamic Island / Lock Screen).
/// It is optional: if the user turned Live Activities off for Doddy, or the request fails, the
/// conversation still runs and iOS still shows its own microphone indicator.
@MainActor
final class VoiceLiveActivity {
    private var activity: Activity<DoddyVoiceAttributes>?
    private var shown: DoddyVoiceAttributes.ContentState?

    /// Shows `state`, starting the activity on first use. iOS only allows starting one while the
    /// app is in the foreground, which is where every conversation starts.
    func show(_ state: DoddyVoiceAttributes.ContentState, startedAt: Date) {
        guard state != shown else { return }
        if let activity {
            shown = state
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(
                attributes: DoddyVoiceAttributes(startedAt: startedAt),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil)
            shown = state
        } catch {
            // Not fatal: the conversation works without the island.
        }
    }

    /// Removes the island at once, so it never claims Doddy is listening after he stopped.
    func end() {
        guard let activity else { return }
        self.activity = nil
        shown = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Clears activities left over from an earlier run that was killed mid-conversation.
    static func endStale() {
        for activity in Activity<DoddyVoiceAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
