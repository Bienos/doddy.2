import ActivityKit
import DoddyCore
import Foundation

/// Bridges Doddy's confirmed local timer requests to the existing shared Live Activity UI.
/// Each timer keeps its notification identifier as a non-content key, so simultaneous timers
/// remain independent and the island never receives a user-entered label.
@MainActor
final class KitchenTimerActivities {
    static let shared = KitchenTimerActivities()

    private let devices = DeviceConnections()
    private var completionTasks: [String: Task<Void, Never>] = [:]

    private init() {
        ToolActivityActions.shared.cancelTimer = { [weak self] identifier in
            guard let self else { return false }
            return await self.cancel(identifier: identifier)
        }
    }

    func start(timer: PendingTimer, fallbackDuration: TimeInterval) async {
        guard timer.identifier.hasPrefix("doddy.timer.") else { return }
        let duration = max(1, timer.duration ?? fallbackDuration)
        let startedAt = timer.startedAt ?? timer.firesAt.addingTimeInterval(-duration)
        let state = DoddyToolAttributes.ContentState(isPaused: false, endsAt: timer.firesAt)

        if let existing = activity(for: timer.identifier) {
            if existing.content.state != state {
                await existing.update(ActivityContent(state: state, staleDate: timer.firesAt))
            }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            let attributes = DoddyToolAttributes(
                kind: .timer, startedAt: startedAt, duration: duration,
                timerNotificationID: timer.identifier)
            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: timer.firesAt),
                    pushType: nil)
            } catch {
                // Timer and its local notification remain valid if Live Activities are unavailable.
            }
        }
        scheduleCompletion(for: timer.identifier, at: timer.firesAt)
    }

    /// Restores visible countdowns from iOS's pending timer requests on launch and foreground.
    /// Missing future requests are removed; an elapsed request is shown as finished, never as
    /// an active countdown. This does not infer that an alert was delivered.
    func reconcile(now: Date = Date()) async {
        let pending = await devices.pendingTimers()
        let deliveredIDs = Set(await devices.deliveredTimerIdentifiers())
        for identifier in deliveredIDs { postCompletionOnce(identifier) }
        let pendingIDs = Set(pending.map(\.identifier))
        for timer in pending {
            let duration = timer.duration ?? max(1, timer.firesAt.timeIntervalSince(timer.startedAt ?? now))
            await start(timer: timer, fallbackDuration: duration)
        }
        for activity in Activity<DoddyToolAttributes>.activities
            where activity.attributes.kind == .timer {
            guard let identifier = activity.attributes.timerNotificationID,
                  !pendingIDs.contains(identifier) else { continue }
            if activity.attributes.startedAt.addingTimeInterval(activity.attributes.duration) <= now {
                let finished = DoddyToolAttributes.ContentState(isPaused: false, endsAt: nil, isFinished: true)
                await activity.end(
                    ActivityContent(state: finished, staleDate: nil),
                    dismissalPolicy: .after(now.addingTimeInterval(300)))
                postCompletionOnce(identifier)
            } else {
                // A future timer disappeared from the authoritative pending list. Do not imply
                // that it is still running or that it completed.
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Called only by the Live Activity's Cancel button. The activity ends after iOS confirms
    /// that both the pending and delivered request are gone.
    func cancel(identifier: String) async -> Bool {
        guard identifier.hasPrefix("doddy.timer.") else { return false }
        let removed = await devices.cancelTimer(identifier: identifier)
        guard removed else {
            if let activity = activity(for: identifier) {
                var state = activity.content.state
                state.cancellationUnconfirmed = true
                await activity.update(ActivityContent(state: state, staleDate: state.endsAt))
            }
            return false
        }
        completionTasks.removeValue(forKey: identifier)?.cancel()
        if let activity = activity(for: identifier) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return true
    }

    private func activity(for identifier: String) -> Activity<DoddyToolAttributes>? {
        Activity<DoddyToolAttributes>.activities.first {
            $0.attributes.kind == .timer && $0.attributes.timerNotificationID == identifier
        }
    }

    private func scheduleCompletion(for identifier: String, at end: Date) {
        completionTasks[identifier]?.cancel()
        completionTasks[identifier] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow))) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            let finished = DoddyToolAttributes.ContentState(isPaused: false, endsAt: nil, isFinished: true)
            if let activity = self.activity(for: identifier) {
                await activity.end(
                    ActivityContent(state: finished, staleDate: nil),
                    dismissalPolicy: .after(Date().addingTimeInterval(300)))
            }
            self.completionTasks[identifier] = nil
            self.postCompletionOnce(identifier)
        }
    }

    private func postCompletionOnce(_ identifier: String) {
        let key = "doddy.kitchenTimer.completed.\(identifier)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        NotificationCenter.default.post(name: .doddyKitchenTimerFinished, object: nil)
    }

    func notificationOpened(identifier: String) {
        guard identifier.hasPrefix("doddy.timer.") else { return }
        postCompletionOnce(identifier)
    }
}

extension Notification.Name {
    static let doddyKitchenTimerFinished = Notification.Name("doddy.kitchenTimer.finished")
}
