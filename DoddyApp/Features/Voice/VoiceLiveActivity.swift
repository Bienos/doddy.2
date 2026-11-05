@preconcurrency import ActivityKit
import DoddyCore
import Foundation
import UIKit

/// Starts, updates and ends the conversation's Live Activity (Dynamic Island / Lock Screen).
/// It is optional: if the user turned Live Activities off for Doddy, or the request fails, the
/// conversation still runs and iOS still shows its own microphone indicator.
///
/// Every content update carries a stale date. If the app stops sending updates (iOS ended it
/// in the background, a crash), iOS marks the activity stale after `staleAfter` and the widget
/// stops claiming Doddy is listening (ADR-055). A heartbeat re-sends the current status with a
/// fresh stale date while the conversation is alive; the status itself still changes only on
/// SDK events.
///
/// Updates are paced (ADR-604): one task sends the newest state, at most one update is in
/// flight, and two go at least `minimumUpdateGap` apart. Before this, every change was queued
/// behind the one before it, so a status that flipped quickly (speaking, listening, speaking)
/// reached the island one step at a time, seconds late, and it looked stuck.
///
/// While Doddy talks and Doddy is not the app on screen, it also sends his beat (ADR-683): every
/// `IslandVoiceBeat.interval` a step for how loud his voice was, so the island swells and eases
/// with him as Home's strip does. iOS can't animate a Live Activity between updates, so this is
/// the only way it moves. Nothing is sent for it while Doddy is on screen (iOS shows no island
/// then), under Reduce Motion, or while he listens, works, is muted or a card waits.
@MainActor
final class VoiceLiveActivity {
    /// The one island the voice conversation uses. (Until ADR-549 "Hey Doddy" listening shared it.)
    static let shared = VoiceLiveActivity()

    /// How long the island may show a status without hearing from the app.
    static let staleAfter: TimeInterval = 90
    /// Must be comfortably shorter than `staleAfter`.
    static let heartbeatEvery: TimeInterval = 40
    /// The shortest time between two content updates (ADR-604).
    static let minimumUpdateGap: TimeInterval = 0.5

    private var activity: Activity<DoddyVoiceAttributes>?
    /// What the app wants shown, and what iOS was last given (ADR-604).
    private var pacer = LiveActivityPacer<DoddyVoiceAttributes.ContentState>(minimumGap: VoiceLiveActivity.minimumUpdateGap)
    private var heartbeat: Task<Void, Never>?
    /// The task that sends the newest state, while there is one to send. `finish`/`end` cancel it
    /// and wait for an update already in flight, so a late update can't land after the end and
    /// turn the "Conversation ended" card back into a live one.
    private var updating: Task<Void, Never>?
    /// Tells a finished sender apart from the one that replaced it.
    private var updatingID = 0
    /// Asks the next update to carry the alert that opens the island up (`expand`).
    private var wantsAlert = false
    /// Asks the next update to go even if the state is the one iOS has (the heartbeat).
    private var wantsRefresh = false
    /// The last `finish`/`end` request, so callers can wait until iOS has it.
    private var ending: Task<Void, Never>?
    /// The state the conversation asked for, before his beat is put in (ADR-683).
    private var asked: DoddyVoiceAttributes.ContentState?
    /// Sends his beat while he talks (ADR-683); nil while he doesn't.
    private var beating: Task<Void, Never>?
    private var beat = IslandVoiceBeat()
    /// The step the island was last asked to show, or nil for none.
    private var beatStep: Int?

    /// True while the conversation's activity is up (iOS accepted the request and it hasn't ended).
    var isShowing: Bool { activity != nil }

    /// Shows `state`, starting the activity on first use. iOS allows starting one while the app is
    /// in the foreground, or from a `LiveActivityIntent` running without it ("Talk in the Island",
    /// ADR-577).
    func show(_ state: DoddyVoiceAttributes.ContentState, startedAt: Date) {
        asked = state
        if activity != nil {
            updateBeating()
            if pacer.want(withBeat(state)) { sendSoon() }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(
                attributes: DoddyVoiceAttributes(startedAt: startedAt),
                content: Self.content(state),
                pushType: nil)
            pacer.started(with: state, at: Date())
            startHeartbeat()
            updateBeating()
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
        guard activity != nil, pacer.latest != nil else { return }
        wantsAlert = true
        sendSoon()
    }

    /// The conversation ended normally (End, Close, connection lost): the island and the Lock
    /// Screen card go away at once (ADR-727, owner, 5 Nov 2026), so nothing claims Doddy is still
    /// there. What a conversation saved is in Settings' "What Doddy did" log, which records each
    /// verified result; `savedCount` is no longer shown anywhere, so it is not used here.
    func finish(savedCount: Int) {
        end()
    }

    /// The conversation couldn't start or its connection dropped (ADR-579): the island goes away
    /// at once too (ADR-727); the reason is said by the app or the intent that started it.
    func finishFailed(savedCount: Int) {
        end()
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
        let pending = stopUpdating()
        ending = Task {
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

    /// The alert that opens the island up. Its words are the status, never anything said.
    private static func alert(for state: DoddyVoiceAttributes.ContentState) -> AlertConfiguration {
        AlertConfiguration(
            title: LocalizedStringResource(stringLiteral: "Doddy"),
            body: LocalizedStringResource(stringLiteral: state.title),
            sound: .default)
    }

    // MARK: Sending

    /// Makes sure a task is sending the newest state. If one is already running it picks the new
    /// state up itself, so nothing queues behind it (ADR-604).
    private func sendSoon() {
        guard updating == nil, activity != nil else { return }
        updatingID &+= 1
        let id = updatingID
        updating = Task { [weak self] in await self?.sendNewest(id: id) }
    }

    /// Sends the newest state as soon as the gap since the last update allows, and again while
    /// something newer is waiting; then stops. The last check and clearing `updating` happen with
    /// no suspension between them, so a state asked for just after can't be missed.
    private func sendNewest(id: Int) async {
        defer { if updatingID == id { updating = nil } }
        while !Task.isCancelled, let activity {
            // Nothing newer than what iOS has: don't wait out a gap for nothing.
            guard wantsAlert || wantsRefresh || pacer.hasPending else { return }
            let wait = pacer.delay(now: Date())
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            // `finish`/`end` cancel this task before they end the activity.
            guard !Task.isCancelled, self.activity?.id == activity.id else { return }
            let alert = wantsAlert
            let refresh = wantsRefresh
            wantsAlert = false
            wantsRefresh = false
            let state = (alert || refresh) ? pacer.resend(now: Date()) : pacer.next(now: Date())
            guard let state else { return }
            if alert {
                await activity.update(Self.content(state), alertConfiguration: Self.alert(for: state))
            } else {
                await activity.update(Self.content(state))
            }
        }
    }

    /// Stops the sender for good and gives back its task, so an update already in flight can
    /// finish before the activity ends. Forgets what was shown, and stops his beat.
    private func stopUpdating() -> Task<Void, Never>? {
        stopBeating()
        asked = nil
        let pending = updating
        pending?.cancel()
        updating = nil
        updatingID &+= 1
        wantsAlert = false
        wantsRefresh = false
        pacer.reset()
        return pending
    }

    // MARK: His beat (ADR-683)

    /// `state` with the step the island shows now; none unless he is talking.
    private func withBeat(_ state: DoddyVoiceAttributes.ContentState) -> DoddyVoiceAttributes.ContentState {
        var shown = state
        shown.voiceBeat = state.wantsVoiceBeat ? beatStep : nil
        return shown
    }

    /// Starts his beat when he starts talking, and stops it when he stops.
    private func updateBeating() {
        let talking = activity != nil && asked?.wantsVoiceBeat == true
        if talking, beating == nil {
            let since = Date()
            // Start from this answer: the loudest level left over from the last one is dropped.
            _ = AgentVoiceMeter.shared.takePeak()
            beating = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(IslandVoiceBeat.interval))
                    guard !Task.isCancelled, let self else { return }
                    self.beatTick(speakingSince: since)
                }
            }
        } else if !talking {
            stopBeating()
        }
    }

    /// One beat: how loud he was since the last one, as a step, sent only when it changed.
    private func beatTick(speakingSince: Date) {
        guard let asked, asked.wantsVoiceBeat, activity != nil else { return }
        let step: Int?
        if UIApplication.shared.applicationState != .active, !UIAccessibility.isReduceMotionEnabled {
            let meter = AgentVoiceMeter.shared
            let peak: Double
            if meter.hasSource {
                // His real voice (ADR-655): the loudest it was since the last beat.
                peak = meter.takePeak()
            } else {
                // No audio track to listen to (another voice provider): Home's made-up rhythm.
                let now = Date().timeIntervalSince(speakingSince)
                peak = SpeechPulse.peak(from: now - IslandVoiceBeat.interval, to: now)
            }
            step = beat.next(peak: peak)
        } else {
            // Doddy is on screen, where iOS shows no island and Home draws its own strip; or
            // Reduce Motion is on. Nothing moves, so nothing more is sent.
            step = nil
            beat.reset()
        }
        guard step != beatStep else { return }
        beatStep = step
        if pacer.want(withBeat(asked)) { sendSoon() }
    }

    private func stopBeating() {
        beating?.cancel()
        beating = nil
        beatStep = nil
        beat.reset()
    }

    /// Proves the app is still there by pushing the stale date forward. Stops with `end()`.
    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.heartbeatEvery))
                guard !Task.isCancelled, let self, self.activity != nil else { return }
                self.wantsRefresh = true
                self.sendSoon()
            }
        }
    }
}
