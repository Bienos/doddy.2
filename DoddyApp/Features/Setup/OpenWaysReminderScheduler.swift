import DoddyCore
import Foundation
import UserNotifications

/// Puts the weekly "Open Doddy faster" reminders in iOS and takes them out again (ADR-547). Four
/// one-time notifications, a week apart, for someone who hasn't used a way to open Doddy yet. They
/// are removed the moment Doddy's shortcut runs, the Back Tap test is confirmed, or the Settings
/// switch is turned off.
///
/// This never asks iOS for notification permission: a reminder about a convenience isn't worth a
/// permission prompt. Without permission nothing is scheduled, and it is tried again the next time
/// Doddy comes to the front. The text says the same thing each time and names nothing personal.
@MainActor
enum OpenWaysReminderScheduler {
    /// The refresh still running, if any. Each one waits for the one before it, so a quick
    /// succession of changes can't interleave their remove and add steps.
    private static var running: Task<Void, Never>?

    static func refresh(_ setup: BackTapSetupModel) async {
        let previous = running
        let task = Task {
            _ = await previous?.value
            await apply(setup)
        }
        running = task
        await task.value
    }

    private static func apply(_ setup: BackTapSetupModel) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter(OpenWaysReminder.isReminder(notificationID:))
        let conversations = UserDefaults.standard.integer(forKey: PreferenceKey.connectedConversations)
        // Back Tap and the Action Button are iPhone things, so the reminder is too (as the Home card is).
        guard DeviceSupport.hasBackTap, setup.reminderWanted(connectedConversations: conversations) else {
            if !pending.isEmpty { center.removePendingNotificationRequests(withIdentifiers: pending) }
            return
        }
        // One round for each time the switch goes on. An armed round is pending, or its four
        // weeks are over; either way nothing more is added.
        guard setup.offer.remindersArmedAt == nil else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let now = Date.now
        let language = NotificationLanguage.current
        let calendar = Calendar.current
        for (id, date) in zip(OpenWaysReminder.ids(), OpenWaysReminder.fireDates(after: now, calendar: calendar)) {
            let content = UNMutableNotificationContent()
            content.title = OpenWaysReminder.title(language)
            content.body = OpenWaysReminder.body(language)
            content.sound = .default
            let when = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            } catch {
                break
            }
        }
        // Read back from iOS: the round counts as set only if all four are really pending.
        let pendingNow = Set(await center.pendingNotificationRequests().map(\.identifier))
        if Set(OpenWaysReminder.ids()).isSubset(of: pendingNow) {
            setup.reminderRoundArmed(at: now)
        } else {
            center.removePendingNotificationRequests(withIdentifiers: OpenWaysReminder.ids())
        }
    }
}
