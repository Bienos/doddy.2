@preconcurrency import ActivityKit
import DoddyCore
import Foundation
import os

/// The Live Activity of the recording being made (ADR-588): one at a time, started only after the
/// recorder has delivered audio, so the island never says "recording" on a hope. Updated when the
/// state changes: the running time is drawn by the system from a start date, not by updates.
///
/// While audio is being written, a heartbeat keeps pushing the stale date forward. If Doddy is
/// killed mid-recording the updates stop, iOS marks the card stale, and the widget stops claiming a
/// recording (the same idea as the voice island, ADR-055). Paused and interrupted cards carry no stale
/// date: the microphone is off there, so "paused" stays true even if the app was suspended.
@MainActor
final class RecordingActivityController {
    /// How long the card may say "recording" without hearing from the app.
    static let staleAfter: TimeInterval = 150
    /// Comfortably shorter than `staleAfter`.
    static let heartbeatEvery: TimeInterval = 60

    private var activity: Activity<DoddyCaptureAttributes>?
    private var shown: CaptureActivitySnapshot?
    private var heartbeat: Task<Void, Never>?
    private var watcher: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.bienos.doddy2.dev", category: "capture")

    /// Called when iOS or the user ended the card while the recording goes on (swiped away, or the
    /// system ended it). Not called for an end this class asked for.
    var onEndedBySystem: (@MainActor () -> Void)?

    var isUp: Bool { activity != nil }

    private static func content(_ snapshot: CaptureActivitySnapshot) -> ActivityContent<CaptureActivitySnapshot> {
        ActivityContent(state: snapshot, staleDate: CapturePresentation.isRecordingCue(snapshot) ? Date().addingTimeInterval(staleAfter) : nil)
    }

    /// Asks iOS for the activity. False if Live Activities are off, or iOS refuses (it only starts
    /// one with Doddy on screen); the caller then says so, it does not pretend.
    func start(recordingID: UUID, startedAt: Date, snapshot: CaptureActivitySnapshot) -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        do {
            let started = try Activity.request(
                attributes: DoddyCaptureAttributes(recordingID: recordingID, startedAt: startedAt),
                content: Self.content(snapshot),
                pushType: nil)
            activity = started
            shown = snapshot
            startHeartbeat()
            watch(started)
            return true
        } catch {
            Self.log.notice("capture activity not started: \(LogSafeError.kind(of: error), privacy: .public)")
            return false
        }
    }

    func update(_ snapshot: CaptureActivitySnapshot) async {
        guard let activity else { return }
        shown = snapshot
        await activity.update(Self.content(snapshot))
    }

    /// Ends it. `snapshot` is the last thing shown, for `dismissAfter` seconds on the Lock Screen
    /// (the island drops an ended activity at once).
    func end(final snapshot: CaptureActivitySnapshot?, dismissAfter seconds: TimeInterval) async {
        guard let activity else {
            await endLeftovers()
            return
        }
        self.activity = nil
        shown = nil
        // A heartbeat update already on its way finishes first, so it cannot land after the end and
        // turn the saved card back into a live one.
        let beat = heartbeat
        heartbeat?.cancel()
        heartbeat = nil
        watcher?.cancel()
        watcher = nil
        await beat?.value
        await activity.end(
            snapshot.map { ActivityContent(state: $0, staleDate: nil) },
            dismissalPolicy: seconds > 0 ? .after(Date().addingTimeInterval(seconds)) : .immediate)
    }

    /// Activities left from before Doddy was closed, with no recording behind them.
    func endLeftovers() async {
        for leftover in Activity<DoddyCaptureAttributes>.activities where leftover.id != activity?.id {
            await leftover.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: -

    /// Proves the app is still there by pushing the stale date forward, only while audio is written.
    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.heartbeatEvery))
                guard !Task.isCancelled else { return }
                guard let self, let activity = self.activity, let shown = self.shown,
                      CapturePresentation.isRecordingCue(shown) else { continue }
                await activity.update(Self.content(shown))
            }
        }
    }

    /// Notices a card that went away without us asking, so the recording is never believed to have one.
    private func watch(_ started: Activity<DoddyCaptureAttributes>) {
        watcher?.cancel()
        let id = started.id
        watcher = Task { [weak self] in
            for await state in started.activityStateUpdates {
                guard state == .ended || state == .dismissed else { continue }
                guard let self, self.activity?.id == id else { return }
                self.activity = nil
                self.shown = nil
                self.heartbeat?.cancel()
                self.heartbeat = nil
                self.onEndedBySystem?()
                return
            }
        }
    }
}
