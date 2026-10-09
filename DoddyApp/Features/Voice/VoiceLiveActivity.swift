@preconcurrency import ActivityKit
import Foundation

/// Starts, updates and ends the conversation's Live Activity (Dynamic Island / Lock Screen).
/// It is optional: if the user turned Live Activities off for Doddy, or the request fails, the
/// conversation still runs and iOS still shows its own microphone indicator.
///
/// Every content update carries a stale date. If the app stops sending updates (iOS ended it
/// in the background, a crash), iOS marks the activity stale after `staleAfter` and the widget
/// stops claiming Doddy is listening (ADR-055). A heartbeat re-sends the current status with a
/// fresh stale date while the conversation is alive; the status itself still changes only on
/// SDK events.
@MainActor
final class VoiceLiveActivity {
    /// How long the island may show a status without hearing from the app.
    static let staleAfter: TimeInterval = 90
    /// Must be comfortably shorter than `staleAfter`.
    static let heartbeatEvery: TimeInterval = 40

    private var activity: Activity<DoddyVoiceAttributes>?
    private var shown: DoddyVoiceAttributes.ContentState?
    private var heartbeat: Task<Void, Never>?

    /// Shows `state`, starting the activity on first use. iOS only allows starting one while the
    /// app is in the foreground, which is where every conversation starts.
    func show(_ state: DoddyVoiceAttributes.ContentState, startedAt: Date) {
        if let activity {
            guard state != shown else { return }
            shown = state
            Task { await activity.update(Self.content(state)) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(
                attributes: DoddyVoiceAttributes(startedAt: startedAt),
                content: Self.content(state),
                pushType: nil)
            shown = state
            startHeartbeat()
        } catch {
            // Not fatal: the conversation works without the island.
        }
    }

    /// Removes the island at once, so it never claims Doddy is listening after he stopped.
    func end() {
        heartbeat?.cancel()
        heartbeat = nil
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

    private static func content(_ state: DoddyVoiceAttributes.ContentState) -> ActivityContent<DoddyVoiceAttributes.ContentState> {
        ActivityContent(state: state, staleDate: Date().addingTimeInterval(staleAfter))
    }

    /// Proves the app is still there by pushing the stale date forward. Stops with `end()`.
    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.heartbeatEvery))
                guard !Task.isCancelled, let self, let activity = self.activity, let shown = self.shown else { return }
                await activity.update(Self.content(shown))
            }
        }
    }
}
