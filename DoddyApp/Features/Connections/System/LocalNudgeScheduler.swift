@preconcurrency import UserNotifications
import DoddyCore
import Foundation

/// Local notifications scheduled by iOS on this iPhone. No server, no network.
struct LocalNudgeScheduler: NudgeScheduler {
    private var center: UNUserNotificationCenter { .current() }

    func authorization() async -> NudgeAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .authorized
        @unknown default: return .denied
        }
    }

    func requestAuthorization() async throws -> NudgeAuthorization {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
        return await authorization()
    }

    func schedule(_ plan: EventNudgePlan) async throws -> ScheduledNudge {
        guard await authorization() == .authorized else { throw NudgeError.notAuthorized }
        let content = UNMutableNotificationContent()
        content.title = plan.notificationTitle
        content.body = plan.notificationBody
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.fireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        // Same identifier for the same event and lead time: a repeat replaces, never duplicates.
        try await center.add(UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger))
        guard let scheduled = try await pending().first(where: { $0.id == plan.identifier }) else {
            throw NudgeError.unverified
        }
        return scheduled
    }

    func pending() async throws -> [ScheduledNudge] {
        await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix("nudge.") }
            .map { request in
                ScheduledNudge(
                    id: request.identifier,
                    title: request.content.title,
                    body: request.content.body,
                    fireAt: (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate())
            }
            .sorted { ($0.fireAt ?? .distantFuture) < ($1.fireAt ?? .distantFuture) }
    }

    func cancel(id: String) async throws {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        if try await pending().contains(where: { $0.id == id }) { throw NudgeError.unverified }
    }
}

/// Shows a nudge as a banner even when Doddy is open (otherwise iOS hides it in the foreground).
final class NudgePresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    @MainActor
    static func install(_ delegate: NudgePresentationDelegate) {
        UNUserNotificationCenter.current().delegate = delegate
    }
}
