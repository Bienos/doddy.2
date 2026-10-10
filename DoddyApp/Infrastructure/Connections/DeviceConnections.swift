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

    /// Changing something that is already in Calendar or Reminders (ADR-229).
    enum ChangeOutcome: Equatable {
        case verified
        /// It no longer looks as it did on the card (changed, moved, done or deleted elsewhere).
        /// Nothing was written.
        case changedElsewhere
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
            .map(Self.summary)
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

    /// Moves or renames exactly the occurrence the card showed (ADR-229). It's found again by its
    /// id and must still look as it did on the card, or nothing is written. A repeating event
    /// changes only this occurrence. Then it's read back from Calendar.
    func changeEvent(_ plan: EventChangePlan) throws -> ChangeOutcome {
        guard access(for: .calendar) == .granted else { return .changedElsewhere }
        guard let event = rawEvents(from: plan.before.start, to: plan.before.end).first(where: { Self.occurrenceID($0) == plan.before.id }),
              Self.summary(event) == plan.before else {
            return .changedElsewhere
        }
        event.title = plan.after.title
        event.startDate = plan.after.start
        event.endDate = plan.after.end
        try eventStore.save(event, span: .thisEvent)
        let itemID = event.calendarItemIdentifier
        let eventID = event.eventIdentifier
        let readBack = rawEvents(from: plan.after.start, to: plan.after.end).contains { found in
            (found.calendarItemIdentifier == itemID || (eventID != nil && found.eventIdentifier == eventID))
                && (found.title ?? "Untitled") == plan.after.title
                && found.startDate == plan.after.start && found.endDate == plan.after.end
        }
        return readBack ? .verified : .unconfirmed
    }

    private func rawEvents(from start: Date, to end: Date) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(withStart: start.addingTimeInterval(-60), end: end.addingTimeInterval(60), calendars: nil)
        return eventStore.events(matching: predicate)
    }

    private static func summary(_ event: EKEvent) -> CalendarEventSummary {
        CalendarEventSummary(
            id: occurrenceID(event), title: event.title ?? "Untitled", start: event.startDate,
            end: event.endDate, allDay: event.isAllDay)
    }

    // MARK: Reminders (M4, ADR-126)

    /// A read of Reminders that takes longer than this counts as failed, and nothing is written.
    private static let reminderReadTimeout: Duration = .seconds(10)

    /// Every incomplete reminder in every list: title, due, list name and Doddy's marker URL.
    /// Used on the phone only, to look before writing and to read back after. Notes are not read.
    func incompleteReminders() async throws -> [ReminderSnapshot] {
        guard access(for: .reminders) == .granted else { throw ReminderStoreError.notAllowed }
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let once = OnceContinuation<[ReminderSnapshot]>()
        let timeout = Self.reminderReadTimeout
        return try await withCheckedThrowingContinuation { continuation in
            once.set(continuation)
            // EventKit calls back on its own queue: @Sendable so the closure isn't main-actor code.
            _ = eventStore.fetchReminders(matching: predicate) { @Sendable reminders in
                once.resume(.success((reminders ?? []).map(DeviceConnections.snapshot)))
            }
            Task {
                try? await Task.sleep(for: timeout)
                once.resume(.failure(ReminderStoreError.timedOut))
            }
        }
    }

    /// Saves exactly what the card showed in the default list, with Doddy's marker in the URL
    /// field. A timed due carries the user's time zone explicitly; a day without a time stays
    /// floating, as the Reminders app does for whole-day reminders.
    func save(_ write: ReminderWrite) throws -> String {
        guard access(for: .reminders) == .granted else { throw ReminderStoreError.notAllowed }
        guard let list = eventStore.defaultCalendarForNewReminders() else { throw Failure.noDefaultReminderList }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = list
        reminder.title = write.title
        reminder.notes = write.notes
        reminder.url = URL(string: write.markerURL)
        if let due = write.due {
            reminder.dueDateComponents = Self.components(due)
        }
        try eventStore.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    private static func components(_ due: ReminderDue) -> DateComponents {
        var components = DateComponents(year: due.year, month: due.month, day: due.day, hour: due.hour, minute: due.minute)
        components.calendar = due.calendar
        if due.hasTime { components.timeZone = due.calendar.timeZone }
        return components
    }

    /// Changes the due of, or completes, exactly the reminder the card showed (ADR-229). It must
    /// still be open with the same title and due, or nothing is written. An alarm set for the old
    /// due moves with it. Then it's read back from Reminders.
    func changeReminder(_ before: ReminderSnapshot, newDue: ReminderDue?, markDone: Bool) throws -> ChangeOutcome {
        guard access(for: .reminders) == .granted else { throw ReminderStoreError.notAllowed }
        guard let reminder = eventStore.calendarItem(withIdentifier: before.id) as? EKReminder,
              !reminder.isCompleted, (reminder.title ?? "") == before.title,
              EventChange.sameDue(Self.snapshot(reminder).due, before.due) else {
            return .changedElsewhere
        }
        if markDone {
            reminder.isCompleted = true
        } else if let newDue {
            let oldDate = before.due.flatMap { EventChange.moment($0, local: .current) }
            reminder.dueDateComponents = Self.components(newDue)
            if let oldDate, let newDate = EventChange.moment(newDue, local: .current) {
                for alarm in reminder.alarms ?? [] where alarm.absoluteDate == oldDate {
                    alarm.absoluteDate = newDate
                }
            }
        }
        try eventStore.save(reminder, commit: true)
        guard let back = eventStore.calendarItem(withIdentifier: before.id) as? EKReminder else { return .unconfirmed }
        let snapshot = Self.snapshot(back)
        if markDone { return snapshot.isCompleted ? .verified : .unconfirmed }
        return !snapshot.isCompleted && EventChange.sameDue(snapshot.due, newDue) ? .verified : .unconfirmed
    }

    /// For "What Doddy did" → Check: is the reminder Doddy wasn't sure about in Reminders now
    /// (found by its marker key)? Nil when Reminders access is off or the read failed, so the
    /// screen can say so instead of guessing.
    func reminderIsThere(key: String) async -> Bool? {
        guard let open = try? await incompleteReminders() else { return nil }
        return open.contains { ReminderIdempotency.key(fromMarker: $0.markerURL) == key }
    }

    nonisolated private static func snapshot(_ reminder: EKReminder) -> ReminderSnapshot {
        let due = reminder.dueDateComponents.flatMap { components -> ReminderDue? in
            guard let year = components.year, let month = components.month, let day = components.day else { return nil }
            return ReminderDue(
                year: year, month: month, day: day, hour: components.hour, minute: components.minute,
                timeZoneID: components.timeZone?.identifier)
        }
        return ReminderSnapshot(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            listTitle: reminder.calendar?.title ?? "Reminders",
            due: due,
            markerURL: reminder.url?.absoluteString,
            isCompleted: reminder.isCompleted)
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

/// The M4 Reminders port (DoddyCore `ReminderAction` drives it; the logic is tested there).
extension DeviceConnections: ReminderStore {}

/// Resumes a continuation once: whichever comes first, EventKit's answer or the timeout.
private final class OnceContinuation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    func set(_ continuation: CheckedContinuation<Value, Error>) {
        lock.withLock { self.continuation = continuation }
    }

    func resume(_ result: Result<Value, Error>) {
        let pending: CheckedContinuation<Value, Error>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(with: result)
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
