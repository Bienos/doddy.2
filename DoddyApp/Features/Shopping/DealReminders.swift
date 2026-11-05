import DoddyCore
import Foundation
import UserNotifications

/// "Remind me on the day" for a leaflet price that starts later (ADR-664): one local notification at 8:00 in Poland
/// on the price's first day, with the words the user saw before saying yes (`DealStartReminder`). Read back from
/// iOS's pending list before the screen says it is set. Nothing leaves the iPhone.
@MainActor
enum DealReminders {
    enum Outcome: Equatable {
        case scheduled(DealDay)
        case needsPermission
        case failed
    }

    static func schedule(_ offer: DealOffer) async -> Outcome {
        guard let id = DealStartReminder.id(offer), let day = offer.validFrom else { return .failed }
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return .needsPermission }

        let language = NotificationLanguage.current
        let content = UNMutableNotificationContent()
        content.title = DealStartReminder.title(language)
        content.body = DealStartReminder.body(offer, language)
        content.sound = .default
        content.interruptionLevel = DoddyNotificationKind.dealStart.interruptionLevel
        var when = day.dateComponents
        when.hour = DealStartReminder.hour
        when.minute = 0
        when.timeZone = TimeZone(identifier: "Europe/Warsaw")
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content,
                                                       trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
        } catch {
            return .failed
        }
        // Read back: the request is in iOS's list, for that day.
        let pending = await center.pendingNotificationRequests()
        guard let request = pending.first(where: { $0.identifier == id }),
              let trigger = request.trigger as? UNCalendarNotificationTrigger,
              trigger.dateComponents.day == day.day, trigger.dateComponents.month == day.month else { return .failed }
        return .scheduled(day)
    }
}
