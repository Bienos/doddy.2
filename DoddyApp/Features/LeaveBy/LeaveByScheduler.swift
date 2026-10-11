import DoddyCore
import Foundation
import UserNotifications

/// Schedules the "time to leave" notification (ADR-335) and reads it back from iOS.
enum LeaveByScheduler {
    enum Outcome: Equatable {
        case scheduled
        /// Notifications are off for Doddy, so nothing can remind the user.
        case notAllowed
        case failed
    }

    static func schedule(_ plan: LeaveByPlan, calendar: Calendar = .current) async -> Outcome {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return .notAllowed }
        let text = LeaveBy.notification(plan, calendar: calendar, language: .current)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.leaveAt)
        let identifier = "doddy.leaveBy.\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        do {
            try await center.add(request)
        } catch {
            return .failed
        }
        let pending = await center.pendingNotificationRequests()
        return pending.contains { $0.identifier == identifier } ? .scheduled : .failed
    }
}
