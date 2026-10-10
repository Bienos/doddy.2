import DoddyCore
import EventKit
import Foundation

/// The app's only EventKit code (guarded by scripts/check_forbidden_capabilities.sh).
/// Writes one reminder after the user confirmed it, reads it back, and finds it again by the
/// Doddy marker in its URL field. It never edits or deletes other reminders.
final class EventKitReminderGateway: ReminderGateway, @unchecked Sendable {
    private let store = EKEventStore()

    func access() async -> RemindersAccess {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    func create(_ payload: ReminderPayload, marker: URL) async throws -> String {
        let reminder = EKReminder(eventStore: store)
        reminder.title = payload.title
        reminder.notes = payload.notes
        reminder.url = marker
        let list = payload.listID.flatMap { store.calendar(withIdentifier: $0) } ?? store.defaultCalendarForNewReminders()
        guard let list else { throw ReminderGatewayError.noList }
        reminder.calendar = list
        if let due = payload.due {
            reminder.dueDateComponents = due.dateComponents
            // An alarm at the due time, so the reminder actually notifies.
            if due.hasTime, let date = due.instant { reminder.addAlarm(EKAlarm(absoluteDate: date)) }
        }
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func fetch(id: String) async throws -> ExternalReminder? {
        (store.calendarItem(withIdentifier: id) as? EKReminder).map(Self.snapshot)
    }

    func find(marker: URL) async throws -> ExternalReminder? {
        let predicate = store.predicateForReminders(in: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                // Converted here, so no EventKit object leaves the callback.
                continuation.resume(returning: reminders?.first { $0.url == marker }.map(Self.snapshot))
            }
        }
    }

    func defaultListTitle() -> String? {
        store.defaultCalendarForNewReminders()?.title
    }

    private static func snapshot(_ reminder: EKReminder) -> ExternalReminder {
        let c = reminder.dueDateComponents
        let due = c.flatMap { c -> ReminderDue? in
            guard let y = c.year, let m = c.month, let d = c.day else { return nil }
            return ReminderDue(year: y, month: m, day: d, hour: c.hour, minute: c.hour == nil ? nil : (c.minute ?? 0),
                               timeZoneID: (c.timeZone ?? .current).identifier)
        }
        return ExternalReminder(id: reminder.calendarItemIdentifier, title: reminder.title ?? "", due: due,
                                listTitle: reminder.calendar?.title ?? "")
    }
}

enum ReminderGatewayError: Error {
    case noList
}
