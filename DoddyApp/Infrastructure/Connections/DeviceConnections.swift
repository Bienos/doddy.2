import Contacts
import CoreMotion
import DoddyCore
import EventKit
import Foundation
import UserNotifications

/// The only code that touches the calendar, reminders, contacts, Motion & Fitness and notifications. Nothing here
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

    struct ContactMatch: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let phoneNumbers: [String]
        let emailAddresses: [String]
    }

    enum Failure: LocalizedError {
        case noDefaultCalendar
        case noDefaultReminderList
        case stepsNotAllowed
        case stepsTimedOut

        var errorDescription: String? {
            switch self {
            case .noDefaultCalendar: "There is no calendar to add the event to."
            case .noDefaultReminderList: "There is no list to add the reminder to."
            case .stepsNotAllowed: "Motion & Fitness isn't allowed for Doddy."
            case .stepsTimedOut: "Motion & Fitness didn't answer in time."
            }
        }
    }

    private let eventStore = EKEventStore()
    private let contactStore = CNContactStore()
    private let pedometer = CMPedometer()

    // MARK: Permission

    /// Synchronous for calendar, reminders and contacts. Timers use notification permission, which
    /// iOS only reports asynchronously; use `notificationAccess()` for those. Maps, Shortcuts,
    /// Messages and Presentations need no permission of their own.
    func access(for connection: VoiceConnection) -> Access {
        switch connection {
        case .calendar: Self.eventAccess(EKEventStore.authorizationStatus(for: .event))
        case .reminders: Self.eventAccess(EKEventStore.authorizationStatus(for: .reminder))
        case .contacts: Self.contactAccess(CNContactStore.authorizationStatus(for: .contacts))
        case .steps: Self.motionAccess()
        // ADR-569: the library (PhotoLibrarySearch) and the camera (CameraAccess), each its own file.
        case .photos: PhotoLibrarySearch.access()
        case .camera: CameraAccess.access()
        case .timers: .notDetermined
        // Home (HomeKit): its own file; no prompt until Allow is tapped (HomeKitClient).
        case .home: HomeKitClient.access()
        // BLIK transfers (ADR-510) need no iOS permission: the card only shows what to send.
        // Presentations (ADR-567) are a file Doddy makes; the user picks where it goes.
        case .maps, .shortcuts, .messages, .blik, .presentations: .granted
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
        case .maps, .shortcuts, .messages, .blik, .presentations:
            return .granted
        case .steps:
            return await requestMotion()
        case .photos:
            return await PhotoLibrarySearch.request()
        case .camera:
            return await CameraAccess.request()
        case .home:
            return await HomeKitClient.request()
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

    /// What a timer needs (ADR-650): nothing more on iOS 26 with alarms not refused, since it rings
    /// through AlarmKit (asked at the Start tap); otherwise notifications, as before.
    func timerAccess() async -> Access {
        TimerRinger.canRing ? .granted : await notificationAccess()
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

    /// An iPad has no step counter; it counts as refused, and the voice controller says so first.
    private static func motionAccess() -> Access {
        guard CMPedometer.isStepCountingAvailable() else { return .denied }
        switch CMPedometer.authorizationStatus() {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// CoreMotion has no "ask" call: the first query shows iOS's prompt. Its answer arrives
    /// separately from the query's, so the status is read until it is no longer undecided (at most
    /// 30 seconds, then it counts as not allowed).
    private func requestMotion() async -> Access {
        let current = Self.motionAccess()
        guard current == .notDetermined else { return current }
        let now = Date()
        pedometer.queryPedometerData(from: now.addingTimeInterval(-60), to: now) { @Sendable _, _ in }
        for _ in 0..<60 {
            try? await Task.sleep(for: .milliseconds(500))
            let answer = Self.motionAccess()
            if answer != .notDetermined { return answer }
        }
        return .notDetermined
    }

    var stepCountingAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    // MARK: Photos and camera (ADR-569)

    var cameraAvailable: Bool { CameraAccess.isAvailable }

    func findPhotos(_ request: PhotoSearchRequest, now: Date) -> PhotoSearchFound {
        PhotoLibrarySearch.find(request, now: now)
    }

    // MARK: Steps (ADR-568)

    /// One day's totals from Motion & Fitness (the iPhone keeps seven days). Read only, nothing kept.
    func steps(on day: StepDay, now: Date) async throws -> StepTotals {
        guard Self.motionAccess() == .granted else { throw Failure.stepsNotAllowed }
        let range = day.range(now: now, calendar: .current)
        let once = OnceContinuation<StepTotals>()
        let timeout = Self.reminderReadTimeout
        return try await withCheckedThrowingContinuation { continuation in
            once.set(continuation)
            // CoreMotion calls back on its own queue: @Sendable so the closure isn't main-actor code.
            pedometer.queryPedometerData(from: range.start, to: range.end) { @Sendable data, error in
                if let error {
                    once.resume(.failure(error))
                } else {
                    once.resume(.success(StepTotals(
                        steps: data?.numberOfSteps.intValue ?? 0, distanceMeters: data?.distance?.doubleValue,
                        floorsUp: data?.floorsAscended?.intValue)))
                }
            }
            Task {
                try? await Task.sleep(for: timeout)
                once.resume(.failure(Failure.stepsTimedOut))
            }
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
        Self.sortedSummaries(in: eventStore, range: range)
    }

    /// The same read, off the main actor (ADR-604): `events(matching:)` is a synchronous call to the
    /// calendar daemon and takes longer on a big calendar. Called from a tool call, it froze Doddy
    /// and the island while he was "thinking". Returns plain values only.
    func readEvents(in range: VoiceTimeRange) async -> [CalendarEventSummary] {
        let stores = Stores(events: eventStore, contacts: contactStore)
        return await Task.detached(priority: .userInitiated) {
            Self.sortedSummaries(in: stores.events, range: range)
        }.value
    }

    /// EventKit and Contacts stores may be used for reads off the main thread; this lets one cross.
    private struct Stores: @unchecked Sendable {
        let events: EKEventStore
        let contacts: CNContactStore
    }

    private nonisolated static func sortedSummaries(in store: EKEventStore, range: VoiceTimeRange) -> [CalendarEventSummary] {
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { Self.summary($0) }
    }

    /// Repeating events share one identifier, so the start time is added: one id per occurrence.
    private nonisolated static func occurrenceID(_ event: EKEvent) -> String {
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

    private nonisolated static func summary(_ event: EKEvent) -> CalendarEventSummary {
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
        // The alert itself (ADR-650): without an alarm Reminders lists it but never rings.
        if let alertAt = write.alertDate(local: .current) { reminder.addAlarm(EKAlarm(absoluteDate: alertAt)) }
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
    /// A reminder with no alarm at all (one an older Doddy wrote, ADR-650) gets one at a new timed due.
    private func moveDue(of reminder: EKReminder, from oldDue: ReminderDue?, to newDue: ReminderDue?) {
        let oldDate = oldDue.flatMap { EventChange.moment($0, local: .current) }
        let hadAlarms = !(reminder.alarms ?? []).isEmpty
        reminder.dueDateComponents = newDue.map(Self.components)
        let newDate = newDue.flatMap { EventChange.moment($0, local: .current) }
        for alarm in reminder.alarms ?? [] where oldDate != nil && alarm.absoluteDate == oldDate {
            if let newDate { alarm.absoluteDate = newDate } else { reminder.removeAlarm(alarm) }
        }
        if let alertAt = ReminderAlert.addOnMove(hasAlarms: hadAlarms, newDue: newDue, local: .current) {
            reminder.addAlarm(EKAlarm(absoluteDate: alertAt))
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
        content.interruptionLevel = DoddyNotificationKind.eventNudge.interruptionLevel
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

    /// Doddy's timers still waiting to ring (TimerWriter, ADR-320): those AlarmKit runs (ADR-650)
    /// and those left as notifications. A notification's ring time is the one written into it
    /// when it was set, not recomputed from its trigger.
    func pendingTimers() async -> [PendingTimer] {
        let ringing = TimerRinger.pending()
        let notified: [PendingTimer] = await UNUserNotificationCenter.current().pendingNotificationRequests().compactMap { request in
            guard request.identifier.hasPrefix("doddy.timer.") else { return nil }
            if let seconds = request.content.userInfo["firesAt"] as? Double {
                return PendingTimer(identifier: request.identifier, firesAt: Date(timeIntervalSince1970: seconds), ring: .notification)
            }
            guard let date = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate() else { return nil }
            return PendingTimer(identifier: request.identifier, firesAt: date, ring: .notification)
        }
        return ringing + notified
    }

    /// Starts one timer under `identifier` (TimerStartAction reads it back). AlarmKit first, so it
    /// rings like the Clock app's timer (ADR-650); a notification when AlarmKit can't be used, or
    /// failed and doesn't list it (so a timer is never set twice).
    func scheduleTimer(_ draft: TimerDraft, identifier: String) async throws {
        if TimerRinger.canRing {
            do {
                if try await TimerRinger.start(draft, identifier: identifier) == .ringing { return }
            } catch {
                if TimerRinger.isListed(identifier) { return }
            }
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = TimerBanners.shared
        let language = NotificationLanguage.current
        let content = UNMutableNotificationContent()
        content.title = TimerCopy.notificationTitle(language)
        content.body = TimerCopy.notificationBody(label: draft.label, seconds: draft.seconds, language)
        content.sound = .default
        // Through a Focus where the user allows Time Sensitive, and never held for the summary.
        content.interruptionLevel = DoddyNotificationKind.timer.interruptionLevel
        content.relevanceScore = 1
        content.userInfo = ["firesAt": Date().addingTimeInterval(TimeInterval(draft.seconds)).timeIntervalSince1970]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(draft.seconds), repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    // MARK: Contacts

    func findContacts(named name: String) throws -> [ContactMatch] {
        try Self.matches(named: name, in: contactStore)
    }

    /// The same read, off the main actor (ADR-604); see `readEvents`.
    func readContacts(named name: String) async throws -> [ContactMatch] {
        let stores = Stores(events: eventStore, contacts: contactStore)
        return try await Task.detached(priority: .userInitiated) {
            try Self.matches(named: name, in: stores.contacts)
        }.value
    }

    private nonisolated static func matches(named name: String, in store: CNContactStore) throws -> [ContactMatch] {
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        let found = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys)
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
        try Self.birthdays(in: contactStore)
    }

    /// The same read, off the main actor (ADR-604); walking every contact is the slow one.
    func readContactBirthdays() async throws -> [ContactBirthday] {
        let stores = Stores(events: eventStore, contacts: contactStore)
        return try await Task.detached(priority: .userInitiated) {
            try Self.birthdays(in: stores.contacts)
        }.value
    }

    private nonisolated static func birthdays(in store: CNContactStore) throws -> [ContactBirthday] {
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactBirthdayKey as CNKeyDescriptor,
        ]
        var found: [ContactBirthday] = []
        try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
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
    /// Asks iOS when it never has (the permission sheet's Allow, ADR-566).
    func request(_ connection: VoiceConnection) async -> DeviceConnections.Access
    func notificationAccess() async -> DeviceConnections.Access
    /// What a timer needs: AlarmKit on iOS 26, notifications otherwise (ADR-650).
    func timerAccess() async -> DeviceConnections.Access
    var stepCountingAvailable: Bool { get }
    func steps(on day: StepDay, now: Date) async throws -> StepTotals
    var cameraAvailable: Bool { get }
    func findPhotos(_ request: PhotoSearchRequest, now: Date) -> PhotoSearchFound
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
    /// The same reads off the main actor, for tool calls (ADR-604).
    func readEvents(in range: VoiceTimeRange) async -> [CalendarEventSummary]
    func readContacts(named name: String) async throws -> [DeviceConnections.ContactMatch]
    func readContactBirthdays() async throws -> [ContactBirthday]
}

extension DeviceConnections: DeviceConnecting {}

/// Fakes that don't model them answer like a device without the permission (tests).
extension DeviceConnecting {
    func request(_ connection: VoiceConnection) async -> DeviceConnections.Access { access(for: connection) }
    /// A fake's timers need notifications, as every timer did before ADR-650.
    func timerAccess() async -> DeviceConnections.Access { await notificationAccess() }
    var stepCountingAvailable: Bool { false }
    func steps(on day: StepDay, now: Date) async throws -> StepTotals { throw DeviceConnections.Failure.stepsNotAllowed }
    var cameraAvailable: Bool { false }
    func findPhotos(_ request: PhotoSearchRequest, now: Date) -> PhotoSearchFound { .empty }
    func readEvents(in range: VoiceTimeRange) async -> [CalendarEventSummary] { events(in: range) }
    func readContacts(named name: String) async throws -> [DeviceConnections.ContactMatch] { try findContacts(named: name) }
    func readContactBirthdays() async throws -> [ContactBirthday] { try contactBirthdays() }
}

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
/// banners anyway, so they still ring while Doddy is open, and keeps them in Notification Center
/// and on the Lock Screen afterwards (`.list`, ADR-650), as when Doddy was closed.
final class TimerBanners: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = TimerBanners()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

/// How each Doddy notification comes through (DoddyCore `DoddyNotificationKind`, ADR-650).
extension DoddyNotificationKind {
    var interruptionLevel: UNNotificationInterruptionLevel {
        switch urgency {
        case .timeSensitive: .timeSensitive
        case .active: .active
        }
    }
}
