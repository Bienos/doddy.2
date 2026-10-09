@preconcurrency import EventKit
import DoddyCore
import Foundation

/// One shared EKEventStore (Apple: create it once and reuse it). EventKit is only used inside
/// Features/Connections (enforced by scripts/check_forbidden_capabilities.sh).
final class SharedEventStore: @unchecked Sendable {
    let store = EKEventStore()

    static func map(_ status: EKAuthorizationStatus) -> SystemAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .fullAccess: .fullAccess
        case .writeOnly: .writeOnly
        @unknown default: .denied
        }
    }
}

/// Calendar on this iPhone, including accounts synced into iOS Calendar (Google, iCloud, Outlook).
struct EventKitCalendarGateway: CalendarGateway {
    let shared: SharedEventStore

    func authorization() -> SystemAuthorization {
        SharedEventStore.map(EKEventStore.authorizationStatus(for: .event))
    }

    func requestAccess() async throws -> SystemAuthorization {
        _ = try await shared.store.requestFullAccessToEvents()
        return authorization()
    }

    func calendars() async throws -> [CalendarInfo] {
        try requireFullAccess()
        return shared.store.calendars(for: .event).map {
            CalendarInfo(id: $0.calendarIdentifier, title: $0.title, allowsWrites: $0.allowsContentModifications)
        }
    }

    func events(from start: Date, to end: Date) async throws -> [CalendarEvent] {
        try requireFullAccess()
        let predicate = shared.store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return shared.store.events(matching: predicate)
            .compactMap(Self.map)
            .sorted { $0.start < $1.start }
    }

    func createEvent(_ draft: EventDraft) async throws -> CalendarEvent {
        guard authorization().allowsWriting else { throw ConnectionError.notAuthorized(.calendar) }
        guard let calendar = shared.store.defaultCalendarForNewEvents else { throw ConnectionError.noWritableCalendar }
        let event = EKEvent(eventStore: shared.store)
        event.calendar = calendar
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.isAllDay
        event.location = draft.location
        event.notes = draft.notes
        do {
            try shared.store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw ConnectionError.failed(error.localizedDescription)
        }
        // Verify by reading the saved event back. Write-only access cannot read back: unknown.
        guard authorization().allowsReading,
              let identifier = event.eventIdentifier,
              let saved = shared.store.event(withIdentifier: identifier),
              let mapped = Self.map(saved)
        else { throw ConnectionError.unverified(.calendar) }
        return mapped
    }

    private func requireFullAccess() throws {
        guard authorization().allowsReading else { throw ConnectionError.notAuthorized(.calendar) }
    }

    /// The identifier includes the start time, so each occurrence of a repeating event is distinct.
    static func map(_ event: EKEvent) -> CalendarEvent? {
        guard let identifier = event.eventIdentifier, let start = event.startDate, let end = event.endDate else { return nil }
        let title: String = event.title ?? ""
        let location: String = event.location ?? ""
        return CalendarEvent(
            id: "\(identifier)@\(Int(start.timeIntervalSince1970))",
            calendarTitle: event.calendar?.title ?? "Calendar",
            title: title.isEmpty ? "Untitled event" : title,
            start: start, end: end, isAllDay: event.isAllDay,
            location: location.isEmpty ? nil : location)
    }
}

struct EventKitRemindersGateway: RemindersGateway {
    let shared: SharedEventStore

    func authorization() -> SystemAuthorization {
        SharedEventStore.map(EKEventStore.authorizationStatus(for: .reminder))
    }

    func requestAccess() async throws -> SystemAuthorization {
        _ = try await shared.store.requestFullAccessToReminders()
        return authorization()
    }

    func listTitles() async throws -> [String] {
        try requireFullAccess()
        return shared.store.calendars(for: .reminder).map(\.title)
    }

    func incompleteReminders(dueBefore: Date?) async throws -> [ReminderItem] {
        try requireFullAccess()
        let store = shared.store
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: dueBefore, calendars: nil)
        return await withCheckedContinuation { continuation in
            _ = store.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).map(Self.map)
                continuation.resume(returning: items.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) })
            }
        }
    }

    func createReminder(_ draft: ReminderDraft) async throws -> ReminderItem {
        try requireFullAccess()
        guard let list = shared.store.defaultCalendarForNewReminders() else { throw ConnectionError.noWritableCalendar }
        let reminder = EKReminder(eventStore: shared.store)
        reminder.calendar = list
        reminder.title = draft.title
        reminder.notes = draft.notes
        if let due = draft.due {
            let units: Set<Calendar.Component> = draft.dueIncludesTime
                ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            reminder.dueDateComponents = Calendar.current.dateComponents(units, from: due)
            if draft.dueIncludesTime { reminder.addAlarm(EKAlarm(absoluteDate: due)) }
        }
        do {
            try shared.store.save(reminder, commit: true)
        } catch {
            throw ConnectionError.failed(error.localizedDescription)
        }
        guard let saved = shared.store.calendarItem(withIdentifier: reminder.calendarItemIdentifier) as? EKReminder else {
            throw ConnectionError.unverified(.reminders)
        }
        return Self.map(saved)
    }

    private func requireFullAccess() throws {
        guard authorization().allowsReading else { throw ConnectionError.notAuthorized(.reminders) }
    }

    static func map(_ reminder: EKReminder) -> ReminderItem {
        let components = reminder.dueDateComponents
        let due = components.flatMap { Calendar.current.date(from: $0) }
        let title: String = reminder.title ?? ""
        return ReminderItem(
            id: reminder.calendarItemIdentifier,
            title: title.isEmpty ? "Untitled reminder" : title,
            due: due,
            dueIncludesTime: components?.hour != nil,
            listTitle: reminder.calendar?.title ?? "Reminders")
    }
}
