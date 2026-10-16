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
            .map { Self.summary($0) }
    }

    /// Repeating events share one identifier, so the start time is added: one id per occurrence.
    private static func occurrenceID(_ event: EKEvent) -> String {
        CalendarEventSummary.occurrenceID(itemID: event.calendarItemIdentifier, start: event.startDate)
    }

    /// Saves one event in the default calendar and returns it as read back with its identifier
    /// (which Undo uses, ADR-268), or nil when the read-back doesn't show it (or its repeat).
    /// `EventAddAction` looks first and compares (CalendarEventWriter, ADR-319).
    func saveEvent(_ draft: CalendarEventDraft) throws -> (event: CalendarEventSummary, eventID: String)? {
        guard let calendar = eventStore.defaultCalendarForNewEvents else { throw Failure.noDefaultCalendar }
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.allDay
        event.location = draft.location
        event.notes = draft.notes
        // A repeat (ADR-282) is saved with the event and must read back the same.
        if let repeats = draft.repeats { event.recurrenceRules = [Self.rule(repeats, calendar: .current)] }
        try eventStore.save(event, span: draft.repeats == nil ? .thisEvent : .futureEvents)
        guard let identifier = event.eventIdentifier, let back = eventStore.event(withIdentifier: identifier),
              CalendarRepeat.same(Self.readRepeat(back.recurrenceRules, calendar: .current), draft.repeats) else {
            return nil
        }
        return (Self.summary(back), identifier)
    }

    /// Calendar's and Reminders' repeat rule for a `CalendarRepeat` (ADR-282). The end is the
    /// end of the last day, in this iPhone's time zone.
    nonisolated private static func rule(_ repeats: CalendarRepeat, calendar: Calendar) -> EKRecurrenceRule {
        let frequency: EKRecurrenceFrequency = switch repeats.unit {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
        let days = repeats.weekdays?.compactMap { EKWeekday(rawValue: $0) }.map { EKRecurrenceDayOfWeek($0) }
        let end = repeats.until
            .flatMap { calendar.date(from: DateComponents(year: $0.year, month: $0.month, day: $0.day, hour: 23, minute: 59)) }
            .map { EKRecurrenceEnd(end: $0) }
        return EKRecurrenceRule(
            recurrenceWith: frequency, interval: repeats.interval, daysOfTheWeek: days, daysOfTheMonth: nil,
            monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: end)
    }

    /// The one repeat rule an event or reminder has, as a `CalendarRepeat`; nil for none, several,
    /// or a rule Doddy doesn't write.
    nonisolated private static func readRepeat(_ rules: [EKRecurrenceRule]?, calendar: Calendar) -> CalendarRepeat? {
        guard let rules, rules.count == 1, let rule = rules.first else { return nil }
        let unit: CalendarRepeat.Unit
        switch rule.frequency {
        case .daily: unit = .daily
        case .weekly: unit = .weekly
        case .monthly: unit = .monthly
        case .yearly: unit = .yearly
        @unknown default: return nil
        }
        let until = rule.recurrenceEnd?.endDate.map { date -> ReminderDue in
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return ReminderDue(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0, timeZoneID: calendar.timeZone.identifier)
        }
        return CalendarRepeat.from(
            unit: unit, interval: rule.interval, weekdays: rule.daysOfTheWeek?.map(\.dayOfTheWeek.rawValue), until: until)
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
        // A new place (ADR-281) only if the place is still what the card showed.
        if plan.newLocation != nil, (event.location ?? "") != (plan.locationBefore ?? "") { return .changedElsewhere }
        // Notes being replaced (ADR-314) must still be the ones the card showed.
        if plan.replaceNotes != nil, (event.notes ?? "") != (plan.notesBefore ?? "") { return .changedElsewhere }
        var notes = event.notes
        if let line = plan.removeNote {
            guard let removed = EventChange.notes(event.notes, removing: line) else { return .changedElsewhere }
            notes = removed
        }
        if let line = plan.addNote { notes = EventChange.notes(notes, adding: line) }
        if let text = plan.replaceNotes { notes = text.isEmpty ? nil : text }
        event.title = plan.after.title
        event.startDate = plan.after.start
        event.endDate = plan.after.end
        if let place = plan.newLocation { event.location = place.isEmpty ? nil : place }
        if plan.addNote != nil || plan.removeNote != nil || plan.replaceNotes != nil { event.notes = notes }
        try eventStore.save(event, span: .thisEvent)
        let itemID = event.calendarItemIdentifier
        let eventID = event.eventIdentifier
        let readBack = rawEvents(from: plan.after.start, to: plan.after.end).contains { found in
            (found.calendarItemIdentifier == itemID || (eventID != nil && found.eventIdentifier == eventID))
                && (found.title ?? "Untitled") == plan.after.title
                && found.startDate == plan.after.start && found.endDate == plan.after.end
                && (plan.newLocation.map { (found.location ?? "") == $0 } ?? true)
                && (plan.addNote == nil && plan.removeNote == nil && plan.replaceNotes == nil || (found.notes ?? "") == (notes ?? ""))
        }
        return readBack ? .verified : .unconfirmed
    }

    // MARK: Undo (ADR-268)

    /// Puts back exactly what Doddy did, only if it still looks exactly as Doddy left it. Nothing
    /// else is ever removed or changed. "Undone" only after a read-back agrees. When a write
    /// throws, a fresh look decides: still as Doddy left it means nothing was written.
    func undo(_ undo: ActivityUndo) async -> UndoResult {
        switch undo {
        case .listAdded, .listTicked, .listRemoved, .savedNote:
            // Lists and notes are Doddy's own (ADR-276, ADR-277): callers send them to the store,
            // never here. Nothing is written.
            return .notDone("That isn't a Calendar or Reminders change.")

        case .addedEvent(let eventID, let added):
            guard access(for: .calendar) == .granted else { return .notDone("Calendar isn't connected.") }
            guard let event = eventStore.event(withIdentifier: eventID), !event.hasRecurrenceRules,
                  ActivityUndo.unchanged(Self.summary(event), since: added) else { return .leftAlone }
            do {
                try eventStore.remove(event, span: .thisEvent, commit: true)
            } catch {
                eventStore.reset()
                return eventStore.event(withIdentifier: eventID) == nil ? .notSure : .notDone(UserFacingError.message(for: error))
            }
            return eventStore.event(withIdentifier: eventID) == nil ? .undone : .notSure

        case .changedEvent(let plan):
            guard access(for: .calendar) == .granted else { return .notDone("Calendar isn't connected.") }
            do {
                // The same guarded write as a change by voice: found by its current occurrence,
                // which must look exactly as Doddy left it, then read back.
                switch try changeEvent(ActivityUndo.reversed(plan)) {
                case .verified: return .undone
                case .changedElsewhere: return .leftAlone
                case .unconfirmed: return .notSure
                }
            } catch {
                return .notSure
            }

        case .addedReminder(let key, let title, let due):
            guard access(for: .reminders) == .granted else { return .notDone("Reminders isn't connected.") }
            guard let open = try? await incompleteReminders() else { return .notDone("Doddy couldn't read Reminders.") }
            guard let mine = ActivityUndo.addedReminder(key: key, in: open),
                  ActivityUndo.unchanged(mine, key: key, title: title, due: due),
                  let reminder = eventStore.calendarItem(withIdentifier: mine.id) as? EKReminder else { return .leftAlone }
            do {
                try eventStore.remove(reminder, commit: true)
            } catch {
                eventStore.reset()
                return eventStore.calendarItem(withIdentifier: mine.id) == nil ? .notSure : .notDone(UserFacingError.message(for: error))
            }
            return eventStore.calendarItem(withIdentifier: mine.id) == nil ? .undone : .notSure

        case .changedReminder(let id, let title, let oldDue, let newDue, let markedDone):
            guard access(for: .reminders) == .granted else { return .notDone("Reminders isn't connected.") }
            guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder,
                  ActivityUndo.unchangedSinceChange(Self.snapshot(reminder), title: title, newDue: newDue, oldDue: oldDue, markedDone: markedDone)
            else { return .leftAlone }
            if markedDone {
                reminder.isCompleted = false
            } else {
                reminder.dueDateComponents = oldDue.map(Self.components)
                // An alarm Doddy moved with the due moves back with it.
                if let newDue, let from = EventChange.moment(newDue, local: .current),
                   let oldDue, let to = EventChange.moment(oldDue, local: .current) {
                    for alarm in reminder.alarms ?? [] where alarm.absoluteDate == from {
                        alarm.absoluteDate = to
                    }
                }
            }
            do {
                try eventStore.save(reminder, commit: true)
            } catch {
                eventStore.reset()
                guard let fresh = eventStore.calendarItem(withIdentifier: id) as? EKReminder else { return .notSure }
                return ActivityUndo.unchangedSinceChange(Self.snapshot(fresh), title: title, newDue: newDue, oldDue: oldDue, markedDone: markedDone)
                    ? .notDone(UserFacingError.message(for: error)) : .notSure
            }
            guard let back = eventStore.calendarItem(withIdentifier: id) as? EKReminder else { return .notSure }
            let snapshot = Self.snapshot(back)
            let restored = markedDone
                ? !snapshot.isCompleted
                : !snapshot.isCompleted && EventChange.sameDue(snapshot.due, oldDue)
            return restored ? .undone : .notSure
        }
    }

    /// The place an occurrence has now, for the change card only (ADR-281). Never sent to the agent.
    func eventLocation(_ event: CalendarEventSummary) -> String? {
        guard access(for: .calendar) == .granted else { return nil }
        return rawEvents(from: event.start, to: event.end).first { Self.occurrenceID($0) == event.id }?.location
    }

    /// The event's notes, read on this iPhone for the card and the stale check (ADR-314). Never
    /// sent to the voice agent.
    func eventNotes(_ event: CalendarEventSummary) -> String? {
        guard access(for: .calendar) == .granted else { return nil }
        return rawEvents(from: event.start, to: event.end).first { Self.occurrenceID($0) == event.id }?.notes
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
        if let repeats = write.repeats { reminder.recurrenceRules = [Self.rule(repeats, calendar: .current)] }
        try eventStore.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    private static func components(_ due: ReminderDue) -> DateComponents {
        var components = DateComponents(year: due.year, month: due.month, day: due.day, hour: due.hour, minute: due.minute)
        components.calendar = due.calendar
        if due.hasTime { components.timeZone = due.calendar.timeZone }
        return components
    }

    /// Changes the due of, completes, or (Undo, ADR-258) reopens exactly the reminder the card
    /// showed (ADR-229). It must still look as it did (title, due, open or done), or nothing is
    /// written. An alarm set for the old due moves with it, or goes when the due is cleared. Then
    /// it's read back from Reminders.
    func changeReminder(_ before: ReminderSnapshot, _ change: ReminderChange) throws -> ChangeOutcome {
        guard access(for: .reminders) == .granted else { throw ReminderStoreError.notAllowed }
        guard let reminder = eventStore.calendarItem(withIdentifier: before.id) as? EKReminder,
              reminder.isCompleted == before.isCompleted, (reminder.title ?? "") == before.title,
              EventChange.sameDue(Self.snapshot(reminder).due, before.due) else {
            return .changedElsewhere
        }
        switch change {
        case .complete:
            guard !reminder.isCompleted else { return .changedElsewhere }
            reminder.isCompleted = true
        case .reopen:
            guard reminder.isCompleted else { return .changedElsewhere }
            reminder.isCompleted = false
        case .due(let newDue):
            guard !reminder.isCompleted else { return .changedElsewhere }
            moveDue(of: reminder, from: before.due, to: newDue)
        case .details(let newDue, let details):
            // ADR-302: the priority and list must also still be as the card showed them.
            guard !reminder.isCompleted, ReminderPriority.from(eventKit: reminder.priority) == before.priority,
                  before.listID == nil || reminder.calendar?.calendarIdentifier == before.listID else { return .changedElsewhere }
            // ADR-314: notes being replaced must still be the ones the card showed.
            if details.replaceNotes != nil, (reminder.notes ?? "") != (before.notes ?? "") { return .changedElsewhere }
            if let newDue { moveDue(of: reminder, from: before.due, to: newDue) }
            if let line = details.addNote { reminder.notes = EventChange.notes(reminder.notes, adding: line) }
            if let text = details.replaceNotes { reminder.notes = text.isEmpty ? nil : text }
            if let title = details.newTitle { reminder.title = title }
            switch details.repeatChange {
            case .set(let rule)?: reminder.recurrenceRules = [Self.rule(rule, calendar: .current)]
            case .stop?: reminder.recurrenceRules = nil
            case nil: break
            }
            if let priority = details.priority { reminder.priority = priority.eventKitValue }
            if let list = details.toList {
                guard let target = eventStore.calendar(withIdentifier: list.id), target.allowsContentModifications else { return .changedElsewhere }
                reminder.calendar = target
            }
        }
        try eventStore.save(reminder, commit: true)
        guard let back = eventStore.calendarItem(withIdentifier: before.id) as? EKReminder else { return .unconfirmed }
        let snapshot = Self.snapshot(back)
        switch change {
        case .complete: return snapshot.isCompleted ? .verified : .unconfirmed
        case .reopen: return !snapshot.isCompleted ? .verified : .unconfirmed
        case .due(let newDue): return !snapshot.isCompleted && EventChange.sameDue(snapshot.due, newDue) ? .verified : .unconfirmed
        case .details(let newDue, let details):
            return ReminderDetails.confirms(snapshot, notes: back.notes, change: details, newDue: newDue) ? .verified : .unconfirmed
        }
    }

    /// A new due; an alarm set for the old due moves with it, or goes when the due is cleared.
    private func moveDue(of reminder: EKReminder, from oldDue: ReminderDue?, to newDue: ReminderDue?) {
        let oldDate = oldDue.flatMap { EventChange.moment($0, local: .current) }
        reminder.dueDateComponents = newDue.map(Self.components)
        let newDate = newDue.flatMap { EventChange.moment($0, local: .current) }
        for alarm in reminder.alarms ?? [] where oldDate != nil && alarm.absoluteDate == oldDate {
            if let newDate { alarm.absoluteDate = newDate } else { reminder.removeAlarm(alarm) }
        }
    }

    /// Deletes exactly the occurrence the card showed (ADR-259). It must still look as it did,
    /// or nothing is deleted. A repeating event loses only this occurrence. Then Calendar is read
    /// again: verified only when that occurrence is gone.
    func deleteEvent(_ event: CalendarEventSummary) throws -> ChangeOutcome {
        guard access(for: .calendar) == .granted else { return .changedElsewhere }
        guard let found = rawEvents(from: event.start, to: event.end).first(where: { Self.occurrenceID($0) == event.id }),
              Self.summary(found) == event else {
            return .changedElsewhere
        }
        try eventStore.remove(found, span: .thisEvent)
        let stillThere = rawEvents(from: event.start, to: event.end).contains { Self.occurrenceID($0) == event.id }
        return stillThere ? .unconfirmed : .verified
    }

    /// Deletes exactly the open reminder the card showed (ADR-259), if it still looks as it did.
    /// Verified only when Reminders no longer has it.
    func deleteReminder(_ before: ReminderSnapshot) throws -> ChangeOutcome {
        guard access(for: .reminders) == .granted else { throw ReminderStoreError.notAllowed }
        guard let reminder = eventStore.calendarItem(withIdentifier: before.id) as? EKReminder,
              !reminder.isCompleted, reminder.isCompleted == before.isCompleted, (reminder.title ?? "") == before.title,
              EventChange.sameDue(Self.snapshot(reminder).due, before.due) else {
            return .changedElsewhere
        }
        try eventStore.remove(reminder, commit: true)
        return eventStore.calendarItem(withIdentifier: before.id) == nil ? .verified : .unconfirmed
    }

    /// The reminder as Reminders has it now (for Undo's starting point), or nil.
    func reminderSnapshot(id: String) -> ReminderSnapshot? {
        guard access(for: .reminders) == .granted,
              let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else { return nil }
        return Self.snapshot(reminder)
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
            isCompleted: reminder.isCompleted,
            repeats: readRepeat(reminder.recurrenceRules, calendar: .current),
            priority: ReminderPriority.from(eventKit: reminder.priority),
            listID: reminder.calendar?.calendarIdentifier,
            notes: reminder.notes)
    }

    /// The Reminders lists Doddy may move a reminder to (ADR-302): names and identifiers only.
    func reminderLists() -> [ReminderListRef] {
        guard access(for: .reminders) == .granted else { return [] }
        return eventStore.calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .map { ReminderListRef(id: $0.calendarIdentifier, title: $0.title) }
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
    /// Doddy's timers still waiting to ring (TimerWriter, ADR-320). The ring time is the one
    /// written into the notification when it was set, not recomputed from its trigger.
    func pendingTimers() async -> [PendingTimer] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().compactMap { request in
            guard request.identifier.hasPrefix("doddy.timer.") else { return nil }
            if let seconds = request.content.userInfo["firesAt"] as? Double {
                let startedAt = (request.content.userInfo["startedAt"] as? Double).map(Date.init(timeIntervalSince1970:))
                let duration = request.content.userInfo["duration"] as? Double
                return PendingTimer(
                    identifier: request.identifier,
                    firesAt: Date(timeIntervalSince1970: seconds),
                    startedAt: startedAt,
                    duration: duration)
            }
            guard let date = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate() else { return nil }
            return PendingTimer(identifier: request.identifier, firesAt: date)
        }
    }

    /// Schedules one timer notification under `identifier` (TimerStartAction reads it back).
    func scheduleTimer(_ draft: TimerDraft, identifier: String) async throws {
        let center = UNUserNotificationCenter.current()
        center.delegate = TimerBanners.shared
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Timer", comment: "Kitchen timer notification title")
        // Timer labels can contain private conversation content. Keep system surfaces generic.
        content.body = NSLocalizedString("Time's up.", comment: "Kitchen timer notification body")
        content.sound = .default
        let startedAt = Date()
        let firesAt = startedAt.addingTimeInterval(TimeInterval(draft.seconds))
        content.userInfo = [
            "firesAt": firesAt.timeIntervalSince1970,
            "startedAt": startedAt.timeIntervalSince1970,
            "duration": TimeInterval(draft.seconds),
        ]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(draft.seconds), repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    /// Cancels only this Doddy timer. Read-back confirms it is no longer pending or delivered.
    func cancelTimer(identifier: String) async -> Bool {
        guard identifier.hasPrefix("doddy.timer.") else { return false }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        let stillPending = await center.pendingNotificationRequests().contains { $0.identifier == identifier }
        let stillDelivered = await center.deliveredNotifications().contains { $0.request.identifier == identifier }
        return !stillPending && !stillDelivered
    }

    func deliveredTimerIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().deliveredNotifications().compactMap { notification in
            let identifier = notification.request.identifier
            return identifier.hasPrefix("doddy.timer.") ? identifier : nil
        }
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

    /// Name and birthday of every contact that has one, for "whose birthday is coming up"
    /// (ADR-269). Nothing else is read.
    /// Only the day and month reach the agent (`VoiceToolReply.birthdays`); the year stays here.
    func contactBirthdays() throws -> [ContactBirthday] {
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactBirthdayKey as CNKeyDescriptor,
        ]
        var found: [ContactBirthday] = []
        try contactStore.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
            // Gregorian birthdays only; a card with only a non-Gregorian date is skipped.
            guard let birthday = contact.birthday, let month = birthday.month, let day = birthday.day,
                  birthday.calendar == nil || birthday.calendar?.identifier == .gregorian else { return }
            found.append(ContactBirthday(
                name: CNContactFormatter.string(from: contact, style: .fullName) ?? "Unnamed contact",
                month: month, day: day, year: birthday.year))
        }
        return found
    }

    /// Contacts with a birthday (ADR-288): name and day only, read on this iPhone. Nil without
    /// Contacts permission. Nothing else about the contact is read.
    func birthdays() -> [BirthdayContact]? {
        guard access(for: .contacts) == .granted else { return nil }
        let keys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName), CNContactBirthdayKey as CNKeyDescriptor]
        var found: [BirthdayContact] = []
        do {
            try contactStore.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
                guard let birthday = contact.birthday, let month = birthday.month, let day = birthday.day else { return }
                found.append(BirthdayContact(
                    id: contact.identifier,
                    name: CNContactFormatter.string(from: contact, style: .fullName) ?? "Unnamed contact",
                    month: month, day: day))
            }
        } catch {
            return nil
        }
        return found
    }
}

/// The M4 Reminders port (DoddyCore `ReminderAction` drives it; the logic is tested there).
extension DeviceConnections: ReminderStore {}
extension DeviceConnections: CalendarEventWriter {}
extension DeviceConnections: TimerWriter {}

/// What `VoiceSessionController` uses of `DeviceConnections`, so its tests can put in a fake
/// Calendar and Reminders (AppTests review 2026-10-11, finding 2). The real class is the default;
/// the signatures are the class's own. Sendable because a `@MainActor` class is; the controller
/// hands it to DoddyCore's nonisolated `ReminderAction.add`.
@MainActor
/// What `VoiceSessionController` uses of the device, so a fake can stand in for it in tests.
/// Events and timers are added through `CalendarEventWriter` and `TimerWriter`, which look first
/// and read back (ADR-319, ADR-320).
protocol DeviceConnecting: ReminderStore, CalendarEventWriter, TimerWriter, Sendable {
    func access(for connection: VoiceConnection) -> DeviceConnections.Access
    func notificationAccess() async -> DeviceConnections.Access
    func changeEvent(_ plan: EventChangePlan) throws -> DeviceConnections.ChangeOutcome
    func undo(_ undo: ActivityUndo) async -> UndoResult
    func eventLocation(_ event: CalendarEventSummary) -> String?
    func eventNotes(_ event: CalendarEventSummary) -> String?
    func changeReminder(_ before: ReminderSnapshot, _ change: ReminderChange) throws -> DeviceConnections.ChangeOutcome
    func deleteEvent(_ event: CalendarEventSummary) throws -> DeviceConnections.ChangeOutcome
    func deleteReminder(_ before: ReminderSnapshot) throws -> DeviceConnections.ChangeOutcome
    func reminderSnapshot(id: String) -> ReminderSnapshot?
    func reminderLists() -> [ReminderListRef]
    func findContacts(named name: String) throws -> [DeviceConnections.ContactMatch]
    func contactBirthdays() throws -> [ContactBirthday]
}

extension DeviceConnections: DeviceConnecting {}

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

/// iOS owns notification presentation. Timer alerts use an in-app completion state while Doddy
/// is foregrounded; other notifications may request a native foreground banner.
final class TimerBanners: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = TimerBanners()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if notification.request.identifier.hasPrefix("doddy.timer.") { return [.sound] }
        [.banner, .sound]
    }
}
