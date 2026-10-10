import Contacts
import DoddyCore
import EventKit
import Foundation
import UserNotifications

/// The only code that touches the calendar, reminders, contacts and notifications. Nothing here
/// runs unless the user turned the matching switch on in Settings, Connections; the caller checks
/// that first. Each call also checks iOS permission. The guard script keeps the EventKit and
/// Contacts imports in this folder.
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

    enum ReminderOutcome: Equatable {
        case added
        /// Doddy had already added this reminder and it isn't done yet; nothing new was added.
        case alreadyThere
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

    /// Synchronous for calendar, reminders and contacts. Timers use notification permission, which
    /// iOS only reports asynchronously; use `notificationAccess()` for those. Maps, Shortcuts and
    /// Messages need no permission of their own.
    func access(for connection: VoiceConnection) -> Access {
        switch connection {
        case .calendar: Self.eventAccess(EKEventStore.authorizationStatus(for: .event))
        case .reminders: Self.eventAccess(EKEventStore.authorizationStatus(for: .reminder))
        case .contacts: Self.contactAccess(CNContactStore.authorizationStatus(for: .contacts))
        case .timers: .notDetermined
        case .maps, .shortcuts, .messages: .granted
        }
    }

    /// Asks iOS for the permission only if it has never been asked. Returns the outcome.
    func request(_ connection: VoiceConnection) async -> Access {
        switch connection {
        case .timers:
            let current = await notificationAccess()
            guard current == .notDetermined else { return current }
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
            return granted ? .granted : .denied
        case .maps, .shortcuts, .messages:
            return .granted
        case .calendar, .reminders, .contacts:
            guard access(for: connection) == .notDetermined else { return access(for: connection) }
            let granted: Bool
            do {
                switch connection {
                case .calendar: granted = try await eventStore.requestFullAccessToEvents()
                case .reminders: granted = try await eventStore.requestFullAccessToReminders()
                default: granted = try await contactStore.requestAccess(for: .contacts)
                }
            } catch {
                granted = false
            }
            return granted ? .granted : .denied
        }
    }

    func notificationAccess() async -> Access {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
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
            .map {
                CalendarEventSummary(
                    id: Self.occurrenceID($0), title: $0.title ?? "Untitled", start: $0.startDate,
                    end: $0.endDate, allDay: $0.isAllDay)
            }
    }

    /// Repeating events share one identifier, so the start time is added: one id per occurrence.
    private static func occurrenceID(_ event: EKEvent) -> String {
        "\(event.calendarItemIdentifier)@\(Int(event.startDate.timeIntervalSince1970))"
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

    /// Adds the reminder unless Doddy already added the same one (same text and due time, not yet
    /// done), then reads it back by its marker. A repeated request or a "try again" after an
    /// unconfirmed add therefore never creates a second copy (ReminderKey).
    func addReminder(_ draft: ReminderDraft, calendar: Calendar) async throws -> ReminderOutcome {
        let key = ReminderKey.key(for: draft, calendar: calendar)
        if await hasIncompleteReminder(withKey: key) { return .alreadyThere }
        guard let list = eventStore.defaultCalendarForNewReminders() else { throw Failure.noDefaultReminderList }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = list
        reminder.title = draft.title
        reminder.notes = draft.notes
        reminder.url = ReminderKey.markerURL(for: draft, calendar: calendar)
        if let due = draft.due {
            let units: Set<Calendar.Component> = draft.dueHasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            var components = calendar.dateComponents(units, from: due)
            components.calendar = calendar
            reminder.dueDateComponents = components
        }
        try eventStore.save(reminder, commit: true)
        return await hasIncompleteReminder(withKey: key) ? .added : .unconfirmed
    }

    private func hasIncompleteReminder(withKey key: String) async -> Bool {
        // All reminders, filtered here: this includes ones with no due date.
        let predicate = eventStore.predicateForReminders(in: nil)
        return await withCheckedContinuation { continuation in
            // EventKit calls back on its own queue: @Sendable so the closure isn't main-actor code.
            eventStore.fetchReminders(matching: predicate) { @Sendable reminders in
                continuation.resume(returning: (reminders ?? []).contains {
                    !$0.isCompleted && ReminderKey.key(fromMarker: $0.url) == key
                })
            }
        }
    }

    /// Incomplete reminders due by `end` (overdue included), for Home → Today. Title and due
    /// date only; notes are not read.
    func remindersDue(by end: Date, calendar: Calendar) async -> [ReminderSummary] {
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        let found: [ReminderSummary] = await withCheckedContinuation { continuation in
            // EventKit calls back on its own queue: @Sendable so the closure isn't main-actor code.
            eventStore.fetchReminders(matching: predicate) { @Sendable reminders in
                let summaries = (reminders ?? []).map { reminder in
                    let components = reminder.dueDateComponents
                    return ReminderSummary(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "Untitled",
                        due: components.flatMap { calendar.date(from: $0) },
                        dueHasTime: components?.hour != nil)
                }
                continuation.resume(returning: summaries)
            }
        }
        return found
    }

    // MARK: Nudges

    /// Schedules a "before this event" notification and reads it back from iOS. The identifier
    /// is fixed per event and lead time, so setting it again replaces it.
    func scheduleNudge(_ plan: EventNudgePlan, time: String) async throws -> AddOutcome {
        let center = UNUserNotificationCenter.current()
        center.delegate = TimerBanners.shared
        let content = UNMutableNotificationContent()
        content.title = "Doddy"
        content.body = plan.body(time: time)
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.fireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger))
        return await pendingNudges().contains { $0.id == plan.identifier } ? .verified : .unconfirmed
    }

    /// Nudges iOS will actually deliver, with their fire times.
    func pendingNudges() async -> [ScheduledNudge] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { ScheduledNudge.isNudge($0.identifier) }
            .map { ScheduledNudge(id: $0.identifier, fireAt: ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()) }
    }

    /// Returns true once the nudge is gone from iOS's pending list.
    func cancelNudge(id: String) async -> Bool {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        return await !pendingNudges().contains { $0.id == id }
    }

    // MARK: Timers

    /// Schedules a local notification for the timer and reads it back from iOS to confirm.
    func startTimer(_ draft: TimerDraft) async throws -> AddOutcome {
        let center = UNUserNotificationCenter.current()
        center.delegate = TimerBanners.shared
        let content = UNMutableNotificationContent()
        content.title = "Timer done"
        content.body = draft.label ?? "Your timer is done."
        content.sound = .default
        let identifier = "doddy.timer.\(UUID().uuidString)"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(draft.seconds), repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        let pending = await center.pendingNotificationRequests()
        return pending.contains { $0.identifier == identifier } ? .verified : .unconfirmed
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

/// iOS hides notification banners for the app that is in front. This shows timer and nudge
/// banners anyway, so they still ring while Doddy is open.
final class TimerBanners: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = TimerBanners()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
