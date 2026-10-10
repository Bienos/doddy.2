import DoddyCore
import Foundation
import Observation
import UserNotifications

/// The morning brief's one daily local notification (ADR-212). Same words every day, so nothing
/// personal is on the Lock Screen and nothing runs in the background. Only the identifier
/// `MorningBriefNotification.identifier` is touched here; timers, nudges, note reminders and server
/// pushes share iOS's queue and are left alone.
enum MorningBriefNotifications {
    enum Outcome: Equatable {
        /// Read back from iOS's pending list at the asked time.
        case set
        /// iOS accepted it but didn't list it as asked: not claimed as set.
        case unconfirmed
        /// Notifications are off for Doddy (or the user said no).
        case notificationsOff
        case failed(String)
    }

    static func current() -> MorningBriefSchedule {
        let defaults = UserDefaults.standard
        return MorningBriefSchedule(
            isOn: defaults.bool(forKey: PreferenceKey.morningBriefOn),
            hour: defaults.object(forKey: PreferenceKey.morningBriefHour) as? Int ?? MorningBriefSchedule.defaultHour,
            minute: defaults.object(forKey: PreferenceKey.morningBriefMinute) as? Int ?? MorningBriefSchedule.defaultMinute)
    }

    /// Adds (or replaces) the daily notification at `schedule`'s time in the iPhone's current zone,
    /// then reads it back. Asks for notification permission only when `mayAsk`.
    static func schedule(_ schedule: MorningBriefSchedule, mayAsk: Bool) async -> Outcome {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined, mayAsk {
            // Same options as timers and note reminders; no badge, no provisional delivery.
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .ephemeral else { return .notificationsOff }

        let content = UNMutableNotificationContent()
        content.title = MorningBriefNotification.title
        content.body = MorningBriefNotification.body
        content.sound = .default
        content.interruptionLevel = .active
        // No zone: the brief follows the iPhone's local morning wherever the user is.
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: schedule.hour, minute: schedule.minute), repeats: true)
        do {
            try await center.add(UNNotificationRequest(
                identifier: MorningBriefNotification.identifier, content: content, trigger: trigger))
        } catch {
            return .failed(error.localizedDescription)
        }
        let pending = await center.pendingNotificationRequests()
        guard let found = pending.first(where: { $0.identifier == MorningBriefNotification.identifier }),
              let listed = found.trigger as? UNCalendarNotificationTrigger, listed.repeats,
              listed.dateComponents.hour == schedule.hour, listed.dateComponents.minute == schedule.minute
        else { return .unconfirmed }
        return .set
    }

    /// Removes the daily notification and checks iOS no longer lists it.
    static func cancel() async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [MorningBriefNotification.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [MorningBriefNotification.identifier])
        return !(await center.pendingNotificationRequests()).contains { $0.identifier == MorningBriefNotification.identifier }
    }

    /// At launch: keep iOS's list equal to the setting, without asking for permission.
    static func syncAtLaunch() async {
        // UI-test launches never touch iOS notifications (as for note reminders).
        guard !ProcessInfo.processInfo.arguments.contains("-inMemoryStore") else { return }
        let schedule = current()
        if schedule.isOn {
            _ = await self.schedule(schedule, mayAsk: false)
        } else {
            _ = await cancel()
        }
    }
}

/// A tap on the brief's notification opens Home.
@MainActor
@Observable
final class MorningBriefRouter {
    static let shared = MorningBriefRouter()
    var openRequested = false
}
