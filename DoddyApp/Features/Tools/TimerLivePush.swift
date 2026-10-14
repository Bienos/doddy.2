@preconcurrency import ActivityKit
import DoddyCore
import Foundation

/// A voice timer's Live Activity, with a push token so the server can update it when the time is
/// up (ADR-483). The island then opens with an alert and a sound, even when Doddy is not running.
/// The local "Timer" notification still goes out as before. Optional: if Live Activities are off,
/// or there is no server, the timer works as it did.
@MainActor
enum TimerLivePush {
    static func start(seconds: TimeInterval, label: String?) {
        guard seconds > 0, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let endsAt = Date().addingTimeInterval(seconds)
        let state = DoddyToolAttributes.ContentState(isPaused: false, endsAt: endsAt, label: label)
        let activity: Activity<DoddyToolAttributes>
        do {
            activity = try Activity.request(
                attributes: DoddyToolAttributes(kind: .timer, startedAt: .now, duration: seconds),
                content: ActivityContent(state: state, staleDate: endsAt.addingTimeInterval(60)),
                pushType: .token)
        } catch {
            return
        }
        Task {
            guard let client = ServerConfig.client() else { return }
            // Only the first token is needed for this timer; a later change is rare and not sent.
            for await token in activity.pushTokenUpdates {
                _ = try? await client.registerTimer(
                    activityToken: token, environment: ServerConfig.pushEnvironment, endsAt: endsAt, label: label)
                return
            }
        }
    }
}
