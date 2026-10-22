import ActivityKit
import DoddyCore
import Foundation
import os

/// The Live Activity of the recording being made (ADR-579): one at a time, started only after the
/// recorder has delivered audio, so the island never says "recording" on a hope. Updated when the
/// state changes, never on a timer: the running time is drawn by the system from a start date.
@MainActor
final class RecordingActivityController {
    private var activity: Activity<DoddyCaptureAttributes>?
    private static let log = Logger(subsystem: "com.bienos.doddy2.dev", category: "capture")

    var isUp: Bool { activity != nil }

    /// Asks iOS for the activity. False if Live Activities are off, or iOS refuses (it only starts
    /// one with Doddy on screen); the caller then says so, it does not pretend.
    func start(recordingID: UUID, startedAt: Date, snapshot: CaptureActivitySnapshot) -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        do {
            activity = try Activity.request(
                attributes: DoddyCaptureAttributes(recordingID: recordingID, startedAt: startedAt),
                content: ActivityContent(state: snapshot, staleDate: nil),
                pushType: nil)
            return true
        } catch {
            Self.log.notice("capture activity not started: \(LogSafeError.kind(of: error), privacy: .public)")
            return false
        }
    }

    func update(_ snapshot: CaptureActivitySnapshot) async {
        guard let activity else { return }
        await activity.update(ActivityContent(state: snapshot, staleDate: nil))
    }

    /// Ends it. `snapshot` is the last thing shown, for `dismissAfter` seconds on the Lock Screen
    /// (the island drops an ended activity at once).
    func end(final snapshot: CaptureActivitySnapshot?, dismissAfter seconds: TimeInterval) async {
        guard let activity else {
            await endLeftovers()
            return
        }
        self.activity = nil
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
}
