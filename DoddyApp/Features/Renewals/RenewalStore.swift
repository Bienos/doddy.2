import DoddyCore
import Foundation
import UserNotifications

/// Bills and subscriptions (ADR-344), kept in the app's preferences on this iPhone, with one
/// notification per renewal for its next date. Every save is read back; notifications are read
/// back from iOS and rebuilt when Doddy comes to the front, so a passed one is replaced.
enum RenewalStore {
    private static var defaults: UserDefaults { .standard }
    static let notificationPrefix = "doddy.renewal."

    static func current() -> Renewals { Renewals(stored: defaults.data(forKey: Renewals.storageKey)) }

    enum Outcome: Equatable {
        case saved
        /// Kept, but iOS doesn't allow notifications, so no reminder will show.
        case savedWithoutReminder
        case problem(RenewalProblem)
        case notSaved
    }

    static func save(_ renewal: Renewal) async -> Outcome {
        var all = current()
        if let problem = all.save(renewal) { return .problem(problem) }
        guard write(all) else { return .notSaved }
        let scheduled = await reconcile()
        return renewal.remindDaysBefore == nil || scheduled.contains(renewal.id) ? .saved : .savedWithoutReminder
    }

    static func remove(_ id: UUID) async -> Bool {
        var all = current()
        all.remove(id)
        guard write(all) else { return false }
        await reconcile()
        return true
    }

    /// Replaces every renewal notification with one for each next date; returns the ids iOS
    /// confirmed. Asks for notifications only if iOS never asked and a reminder is wanted.
    @discardableResult
    static func reconcile(now: Date = .now, calendar: Calendar = .current) async -> Set<UUID> {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(notificationPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        let wanted = current().items.compactMap { item in item.reminderDate(now: now, calendar: calendar).map { (item, $0) } }
        guard !wanted.isEmpty else { return [] }
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return [] }
        for (item, date) in wanted {
            let next = item.next(after: date, calendar: calendar)
            let text = item.notification(next: next, calendar: calendar, language: .current)
            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            try? await center.add(UNNotificationRequest(
                identifier: notificationPrefix + item.id.uuidString, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
        let pending = Set(await center.pendingNotificationRequests().map(\.identifier))
        return Set(wanted.map(\.0.id).filter { pending.contains(notificationPrefix + $0.uuidString) })
    }

    private static func write(_ all: Renewals) -> Bool {
        defaults.set(all.stored, forKey: Renewals.storageKey)
        return current() == all
    }
}
