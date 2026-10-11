@preconcurrency import ActivityKit
import DoddyCore
import Foundation

/// Starts and ends the leave-by countdown (ADR-347). Optional: if Live Activities are off for
/// Doddy or the request fails, the notification still comes; the reply says only what happened.
@MainActor
enum LeaveByCountdownActivity {
    /// True when iOS accepted the countdown.
    static func start(_ plan: LeaveByPlan, now: Date = .now) -> Bool {
        guard LeaveByCountdown.isAvailable(plan, now: now), ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        let state = LeaveByActivityAttributes.ContentState(leaveAt: plan.leaveAt, arriveBy: plan.request.arriveBy)
        do {
            _ = try Activity.request(
                attributes: LeaveByActivityAttributes(placeName: plan.placeName),
                content: ActivityContent(state: state, staleDate: plan.leaveAt),
                pushType: nil)
            return true
        } catch {
            return false
        }
    }

    /// When Doddy comes to the front: countdowns whose arrival time has passed are removed.
    static func endFinished(now: Date = .now) {
        for activity in Activity<LeaveByActivityAttributes>.activities
        where LeaveByCountdown.isOver(arriveBy: activity.content.state.arriveBy, now: now) {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
