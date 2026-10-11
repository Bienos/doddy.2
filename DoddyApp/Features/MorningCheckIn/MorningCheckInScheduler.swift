import DoddyCore
import Foundation
import UserNotifications

/// Puts the morning check-in's repeating notification in iOS (ADR-220) and reads it back. The
/// notification carries only "Good morning · A quick look at your day?", never a note.
enum MorningCheckInScheduler {
    enum Outcome: Equatable {
        /// Read back from iOS's pending list: this many requests (1, or 5 on weekdays only).
        case scheduled(Int)
        case off
        /// iOS notifications are off for Doddy; nothing was scheduled.
        case needsPermission
        case failed
    }

    /// Replaces whatever check-in requests are pending with the ones `settings` asks for.
    static func apply(_ settings: MorningCheckInSettings) async -> Outcome {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter(MorningCheckIn.isCheckIn(notificationID:)))
        let requests = MorningCheckIn.requests(settings)
        guard !requests.isEmpty else { return .off }

        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return .needsPermission }

        let language = NotificationLanguage.current
        for request in requests {
            let content = UNMutableNotificationContent()
            content.title = MorningCheckIn.title(language)
            content.body = MorningCheckIn.body(language)
            content.sound = .default
            var when = DateComponents()
            when.hour = request.hour
            when.minute = request.minute
            when.weekday = request.weekday
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            do {
                try await center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: trigger))
            } catch {
                return .failed
            }
        }
        let wanted = Set(requests.map(\.id))
        let now = Set(await center.pendingNotificationRequests().map(\.identifier))
        return wanted.isSubset(of: now) ? .scheduled(wanted.count) : .failed
    }
}
