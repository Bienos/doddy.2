import Contacts
import DoddyCore
import EventKit
import Foundation

/// The only code that touches the calendar, reminders and contacts. Nothing here runs unless the
/// user turned the matching toggle on in Settings, Connections; the caller checks that first.
/// Each call also checks iOS permission. The guard script keeps these imports in this folder.
@MainActor
final class DeviceConnections {
    enum Access: Equatable {
        case granted, denied, notDetermined
    }

    enum AddOutcome: Equatable {
        case verified
        /// Saved, but reading it back failed. The agent must tell the user to check.
        case unconfirmed
    }

    struct ContactMatch: Identifiable, Equatable {
        let id: String
        let name: String
        let phoneNumbers: [String]
        let emailAddresses: [String]
    }

    enum Failure: LocalizedError {
        case noDefaultCalendar
        case noDefaultReminderList

        var errorDescription: String? {
            switch self {
            case .noDefaultCalendar: "There is no calendar to add the event to."
            case .noDefaultReminderList: "There is no list to add the reminder to."
            }
        }
    }

    private let eventStore = EKEventStore()
    private let contactStore = CNContactStore()

    // MARK: Permission

    func access(for connection: VoiceConnection) -> Access {
        switch connection {
        case .calendar: Self.eventAccess(EKEventStore.authorizationStatus(for: .event))
        case .reminders: Self.eventAccess(EKEventStore.authorizationStatus(for: .reminder))
        case .contacts: Self.contactAccess(CNContactStore.authorizationStatus(for: .contacts))
        }
    }

    /// Asks iOS for the permission only if it has never been asked. Returns the outcome.
    func request(_ connection: VoiceConnection) async -> Access {
        guard access(for: connection) == .notDetermined else { return access(for: connection) }
        let granted: Bool
        do {
            switch connection {
            case .calendar: granted = try await eventStore.requestFullAccessToEvents()
            case .reminders: granted = try await eventStore.requestFullAccessToReminders()
            case .contacts: granted = try await contactStore.requestAccess(for: .contacts)
            }
        } catch {
            granted = false
        }
        return granted ? .granted : .denied
    }

    private static func eventAccess(_ status: EKAuthorizationStatus) -> Access {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    private static func contactAccess(_ status: CNAuthorizationStatus) -> Access {
        switch status {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    // MARK: Calendar

    /// Title and times only; notes and locations are not read.
    func events(in range: VoiceTimeRange) -> [CalendarEventSummary] {
        let predicate = eventStore.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        return eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { CalendarEventSummary(title: $0.title ?? "Untitled", start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay) }
    }

    func addEvent(_ draft: CalendarEventDraft) throws -> AddOutcome {
        guard let calendar = eventStore.defaultCalendarForNewEvents else { throw Failure.noDefaultCalendar }
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.allDay
        event.location = draft.location
        event.notes = draft.notes
        try eventStore.save(event, span: .thisEvent)
        guard let identifier = event.eventIdentifier, eventStore.event(withIdentifier: identifier) != nil else {
            return .unconfirmed
        }
        return .verified
    }

    // MARK: Reminders

    func addReminder(_ draft: ReminderDraft, calendar: Calendar) throws -> AddOutcome {
        guard let list = eventStore.defaultCalendarForNewReminders() else { throw Failure.noDefaultReminderList }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = list
        reminder.title = draft.title
        reminder.notes = draft.notes
        if let due = draft.due {
            let units: Set<Calendar.Component> = draft.dueHasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            var components = calendar.dateComponents(units, from: due)
            components.calendar = calendar
            reminder.dueDateComponents = components
        }
        try eventStore.save(reminder, commit: true)
        return eventStore.calendarItem(withIdentifier: reminder.calendarItemIdentifier) != nil ? .verified : .unconfirmed
    }

    // MARK: Contacts

    func findContacts(named name: String) throws -> [ContactMatch] {
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        let found = try contactStore.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys)
        return found.map { contact in
            ContactMatch(
                id: contact.identifier,
                name: CNContactFormatter.string(from: contact, style: .fullName) ?? "Unnamed contact",
                phoneNumbers: contact.phoneNumbers.map { $0.value.stringValue },
                emailAddresses: contact.emailAddresses.map { $0.value as String })
        }
    }
}
