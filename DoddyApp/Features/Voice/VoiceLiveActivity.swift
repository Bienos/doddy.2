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
    /// The one island the voice conversation uses. (Until ADR-549 "Hey Doddy" listening shared it.)
    static let shared = VoiceLiveActivity()

    /// How long the island may show a status without hearing from the app.
    static let staleAfter: TimeInterval = 90
    /// Must be comfortably shorter than `staleAfter`.
    static let heartbeatEvery: TimeInterval = 40

    private var activity: Activity<DoddyVoiceAttributes>?
    private var shown: DoddyVoiceAttributes.ContentState?
    private var heartbeat: Task<Void, Never>?
    /// The last content update sent to iOS. `finish`/`end` wait for it, so a late update can't
    /// land after the end and turn the "Conversation ended" card back into a live one.
    private var updating: Task<Void, Never>?
    /// The last `finish`/`end` request, so callers can wait until iOS has it.
    private var ending: Task<Void, Never>?

    /// True while the conversation's activity is up (iOS accepted the request and it hasn't ended).
    var isShowing: Bool { activity != nil }

    /// Shows `state`, starting the activity on first use. iOS allows starting one while the app is
    /// in the foreground, or from a `LiveActivityIntent` running without it ("Talk in the Island",
    /// ADR-577).
    func show(_ state: DoddyVoiceAttributes.ContentState, startedAt: Date) {
        if let activity {
            guard state != shown else { return }
            shown = state
            let previous = updating
            updating = Task {
                await previous?.value
                await activity.update(Self.content(state))
            }
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

    /// Asks iOS to open the island up for a few seconds with what it shows now (the big island:
    /// it unfolds and plays the alert sound). `IslandExpansion` (ADR-577) decides when. iOS does
    /// this only while Doddy is not the app on screen, and decides the final size, so this is a
    /// request. The alert's words are only shown on a paired Apple Watch: the status, never
    /// anything said. A no-op when there is no activity. Only for a conversation the app is
    /// running, so no push is needed.
    func expand() {
        guard let activity, let shown else { return }
        let alert = AlertConfiguration(
            title: LocalizedStringResource(stringLiteral: "Doddy"),
            body: LocalizedStringResource(stringLiteral: shown.title),
            sound: .default)
        let previous = updating
        updating = Task {
            await previous?.value
            await activity.update(Self.content(shown), alertConfiguration: alert)
        }
    }

    /// How long the "Conversation ended" card stays on the Lock Screen. The Dynamic Island
    /// drops an ended activity at once whatever this says.
    static let endedCardFor: TimeInterval = 120

    /// The conversation ended normally (End, Close, connection lost): the Lock Screen shows a
    /// short "Conversation ended" card with the number of notes saved, then it goes away.
    /// It carries no stale date: it claims nothing that can go out of date.
    func finish(savedCount: Int) {
        let beat = heartbeat
        beat?.cancel()
        heartbeat = nil
        guard let activity else { return }
        self.activity = nil
        shown = nil
        var final = DoddyVoiceAttributes.ContentState(status: .ended, isMuted: false, savedCount: savedCount, endedAt: Date())
        // ADR-617: the ended card in the language of Doddy's screens, as the island was.
        final.language = Bundle.main.preferredLocalizations.first
        let removeAt = Date().addingTimeInterval(Self.endedCardFor)
        let pending = updating
        updating = nil
        ending = Task {
            // A heartbeat update already in flight finishes first (the sleep ends at cancel).
            await beat?.value
            await pending?.value
            await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .after(removeAt))
        }
    }

    /// How long the "Conversation stopped" card stays on the Lock Screen after a failure.
    static let failedCardFor: TimeInterval = 60

    /// The conversation couldn't start or its connection dropped (ADR-579): the Lock Screen shows
    /// "Conversation stopped" with Open Doddy for a minute, never a live status. The Dynamic
    /// Island drops it at once; the reason is said by the app or the intent that started it.
    func finishFailed(savedCount: Int) {
        let beat = heartbeat
        beat?.cancel()
        heartbeat = nil
        guard let activity else { return }
        self.activity = nil
        shown = nil
        var final = DoddyVoiceAttributes.ContentState(status: .failed, isMuted: false, savedCount: savedCount, endedAt: Date())
        final.language = Bundle.main.preferredLocalizations.first
        let removeAt = Date().addingTimeInterval(Self.failedCardFor)
        let pending = updating
        updating = nil
        ending = Task {
            await beat?.value
            await pending?.value
            await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .after(removeAt))
        }
    }

    /// Waits until the last update and `finish`/`end` have reached iOS (so the island's End
    /// sees the state the app left it in).
    func settle() async {
        await updating?.value
        await ending?.value
    }

    /// Removes the island at once, so it never claims Doddy is listening after he stopped.
    /// Used when the conversation failed or never really started.
    func end() {
        let beat = heartbeat
        beat?.cancel()
        heartbeat = nil
        guard let activity else { return }
        self.activity = nil
        shown = nil
        let pending = updating
        updating = nil
        ending = Task {
            // A heartbeat update already in flight finishes first (the sleep ends at cancel).
            await beat?.value
            await pending?.value
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Clears activities left over from an earlier run that was killed mid-conversation. Called
    /// once, from `DoddyApp.init`, before anything in this run can start one; the list is read
    /// right away, so a conversation the Action Button starts in this run is never in it. To be
    /// safe whatever calls it later (ADR-579), it also skips the activity this run owns and any
    /// that began after this run did.
    static func endStale(runStartedAt: Date = Date()) {
        let own = shared.activity?.id
        for activity in Activity<DoddyVoiceAttributes>.activities
        where activity.id != own && activity.attributes.startedAt < runStartedAt {
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
