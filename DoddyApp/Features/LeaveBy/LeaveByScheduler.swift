import DoddyCore
import Foundation
import UserNotifications

/// Schedules the "time to leave" notification (ADR-335) and reads it back from iOS. Doddy looks
/// for the same one first through `LeaveBySetAction`, so asking again never sets a second.
@MainActor
final class LeaveByScheduler: LeaveByWriter {
    private let center = UNUserNotificationCenter.current()

    func notificationsAllowed() async -> Bool {
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    func pendingLeaveBys() async -> [PendingLeaveBy] {
        await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix("doddy.leaveBy.") }
            .map { PendingLeaveBy(identifier: $0.identifier, firesAt: ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()) }
    }

    func scheduleLeaveBy(_ plan: LeaveByPlan, identifier: String) async throws {
        let calendar = Calendar.current
        let text = LeaveBy.notification(plan, calendar: calendar, language: .current)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        // Doddy on tiptoe, "on the way" (ADR-546); the words are unchanged.
        if let art = NotificationArt.attachment(for: .leaveBy) { content.attachments = [art] }
        content.sound = .default
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.leaveAt)
        let request = UNNotificationRequest(identifier: identifier, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        try await center.add(request)
    }
}
