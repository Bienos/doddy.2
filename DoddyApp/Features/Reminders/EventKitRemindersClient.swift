import DoddyCore
import EventKit
import Foundation

/// The only EventKit code in the app (the capability guard enforces this folder). It does what
/// `RemindersActionAdapter` asks and nothing else: no reading of other reminders beyond finding
/// Doddy's own by its marker. UNVERIFIED until built and run on an iPhone.
actor EventKitRemindersClient: RemindersClient {
    private let store = EKEventStore()

    func authorization() async -> RemindersAuthorization {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        // .denied, .writeOnly (calendars only) and anything newer: treat as no access.
        default: .denied
        }
    }

    func requestAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func defaultList() async -> ReminderList? {
        store.defaultCalendarForNewReminders().map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }
    }

    func list(id: String) async -> ReminderList? {
        guard let calendar = store.calendar(withIdentifier: id), calendar.allowedEntityTypes.contains(.reminder) else {
            return nil
        }
        return ReminderList(id: calendar.calendarIdentifier, title: calendar.title)
    }

    func create(_ write: ReminderWrite) async throws -> String {
        guard let calendar = store.calendar(withIdentifier: write.listID) else { throw RemindersClientError.listMissing }
        let reminder = EKReminder(eventStore: store)
        reminder.title = write.title
        reminder.calendar = calendar
        reminder.url = write.markerURL
        reminder.notes = write.markerNote
        if let due = write.due {
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = write.timeZone
            var components = gregorian.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            components.timeZone = write.timeZone
            reminder.dueDateComponents = components
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func findReminder(reference: UUID) async throws -> String? {
        let predicate = store.predicateForReminders(in: nil)
        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                guard let reminders else {
                    continuation.resume(throwing: RemindersClientError.lookupFailed)
                    return
                }
                let match = reminders.first {
                    RemindersMarker.matches(url: $0.url, notes: $0.notes, reference: reference)
                }
                continuation.resume(returning: match?.calendarItemIdentifier)
            }
        }
    }
}
