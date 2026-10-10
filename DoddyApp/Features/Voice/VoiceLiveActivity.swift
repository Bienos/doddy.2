import ActivityKit
import Foundation

/// Owns the one Live Activity (Dynamic Island / Lock Screen) that mirrors an open conversation.
/// It only ever shows states the conversation is really in; `end()` removes it immediately.
@MainActor
final class VoiceLiveActivity {
    typealias State = VoiceActivityAttributes.ContentState

    /// Called when iOS or the user removes the activity while the conversation is still open.
    var onRemovedBySystem: (@MainActor () -> Void)?

    private var activity: Activity<VoiceActivityAttributes>?
    private var watcher: Task<Void, Never>?
    private var lastUpdate: Task<Void, Never>?

    var isRunning: Bool { activity != nil }

    /// Starts the activity, or updates it if it is already showing.
    /// Returns a user-facing problem when it cannot be shown, `nil` on success.
    @discardableResult
    func show(_ state: State) -> String? {
        let content = ActivityContent(state: state, staleDate: nil)

        if let activity {
            let previous = lastUpdate
            lastUpdate = Task {
                await previous?.value
                await activity.update(content)
            }
            return nil
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "Live Activities are turned off for Doddy, so the Dynamic Island can't show. Turn them on in Settings → Doddy."
        }
        do {
            // Anything left over from a previous run (for example after a crash) goes first.
            let leftovers = Activity<VoiceActivityAttributes>.activities
            if !leftovers.isEmpty {
                Task { for old in leftovers { await old.end(nil, dismissalPolicy: .immediate) } }
            }
            let new = try Activity.request(
                attributes: VoiceActivityAttributes(startedAt: .now),
                content: content,
                pushType: nil)
            activity = new
            watch(new)
            return nil
        } catch {
            return "Couldn't start the Dynamic Island (\(error.localizedDescription))."
        }
    }

    func end() {
        watcher?.cancel()
        watcher = nil
        guard let finished = activity else { return }
        activity = nil
        let previous = lastUpdate
        lastUpdate = Task {
            await previous?.value
            await finished.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func watch(_ watched: Activity<VoiceActivityAttributes>) {
        watcher?.cancel()
        watcher = Task { [weak self] in
            for await state in watched.activityStateUpdates {
                guard state == .ended || state == .dismissed else { continue }
                // Only react if this is still the activity we are tracking (not one we ended).
                if let self, self.activity?.id == watched.id {
                    self.activity = nil
                    self.onRemovedBySystem?()
                }
                return
            }
        }
    }
}
