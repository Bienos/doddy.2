import DoddyCore
import Foundation
import Observation

/// Home → Today: the rest of today and the start of tomorrow from the user's Calendar and Reminders
/// on this iPhone (decision 2026-11-10-today-at-a-glance), with optional "before this event" nudges and
/// a tick to complete a reminder. Read only when the matching switch in Settings → Connections is on
/// and iOS allows it. Nothing here is sent anywhere; the next event's place goes to Apple Maps only
/// when the person taps Open in Maps.
///
/// Since 13 Nov 2026 (owner: "zero edycji") a reminder can be added, changed or deleted here, and an
/// event opens in Apple's event editor. Every write goes to Reminders or Calendar with a commit, is read
/// back, and then the list is read again; a line says "added", "saved" or "deleted" only from that read.
@MainActor
@Observable
final class TodayModel {
    enum Content: Equatable {
        case loading
        /// Calendar and Reminders are both off (or blocked by iOS).
        case notConnected
        /// Settings → Pause all is on: nothing is read.
        case paused
        case glance(TodayGlance)
    }

    private let devices = DeviceConnections()
    private(set) var content: Content = .loading
    private(set) var nudges: [ScheduledNudge] = []
    /// The last nudge result: a receipt read back from iOS, or what went wrong.
    private(set) var notice: String?
    /// The last tick or Undo result: read back from Reminders, or what went wrong.
    private(set) var reminderNotice: String?
    /// The reminder just ticked off and read back as done, while Undo is offered.
    private(set) var undoable: ReminderSnapshot?
    /// Reminders being written now; their tick waits.
    private(set) var busyReminders: Set<String> = []
    /// The next event's location as Calendar has it, read on this iPhone for this screen only.
    private(set) var nextLocation: String?

    private var paused: Bool { UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) }

    private func isOn(_ connection: VoiceConnection) -> Bool {
        UserDefaults.standard.bool(forKey: connection.preferenceKey) && devices.access(for: connection) == .granted
    }

    func refresh(now: Date = .now, calendar: Calendar = .current) async {
        if paused {
            content = .paused
            nextLocation = nil
            return
        }
        let calendarOn = isOn(.calendar), remindersOn = isOn(.reminders)
        guard calendarOn || remindersOn else {
            content = .notConnected
            nextLocation = nil
            return
        }
        // Today and tomorrow in one read each; `TodayGlance` sorts out what goes where.
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 2, to: start) ?? now
        let events = calendarOn ? await devices.readEvents(in: VoiceTimeRange(start: start, end: end)) : []
        let reminders = remindersOn ? await devices.remindersDue(by: end, calendar: calendar) : []
        let glance = TodayGlance(
            events: events, reminders: reminders, now: now, calendar: calendar, calendarOn: calendarOn, remindersOn: remindersOn)
        nextLocation = glance.nextUp
            .flatMap { devices.eventLocation($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        content = .glance(glance)
        nudges = await devices.pendingNudges()
    }

    // MARK: Nudges

    /// The nudge set for this event, if any.
    func nudge(for event: CalendarEventSummary) -> ScheduledNudge? {
        nudges.first { $0.eventID == event.id && $0.eventID != nil }
    }

    func setNudge(for event: CalendarEventSummary, leadMinutes: Int) async {
        let plan: EventNudgePlan
        do {
            plan = try EventNudgePlan(event: event, leadMinutes: leadMinutes, now: .now)
        } catch {
            notice = NSLocalizedString("That time has already passed, so no nudge was set.", comment: "")
            return
        }
        var access = await devices.notificationAccess()
        if access == .notDetermined { access = await devices.request(.timers) }
        guard access == .granted else {
            notice = NSLocalizedString("Notifications are off for Doddy. Turn them on in iPhone Settings, Notifications, Doddy.", comment: "")
            return
        }
        // Setting a different lead time replaces the earlier nudge for this event, but only once
        // the new one is confirmed: a failure keeps the old nudge rather than leaving none (DOD-08).
        let existing = nudge(for: event)
        let old: ScheduledNudge? = existing?.id == plan.identifier ? nil : existing
        do {
            let time = event.start.formatted(date: .omitted, time: .shortened)
            switch try await devices.scheduleNudge(plan, time: time) {
            case .verified:
                if let old { _ = await devices.cancelNudge(id: old.id) }
                notice = "Nudge set for \(plan.fireAt.formatted(date: .omitted, time: .shortened)): \(event.title)."
            case .unconfirmed:
                notice = old == nil
                    ? "iOS took the nudge but didn't confirm it. Check before relying on it."
                    : "iOS took the new nudge but didn't confirm it, so the earlier one was kept too. Check before relying on it."
            }
        } catch {
            notice = old == nil
                ? "The nudge wasn't set. \(error.localizedDescription)"
                : "The new nudge wasn't set; the earlier one is still on. \(error.localizedDescription)"
        }
        nudges = await devices.pendingNudges()
    }

    func cancel(_ nudge: ScheduledNudge, title: String) async {
        notice = await devices.cancelNudge(id: nudge.id)
            ? "Nudge removed: \(title)."
            : "iOS still lists that nudge. Try again."
        nudges = await devices.pendingNudges()
    }

    // MARK: Ticking off a reminder

    /// Ticks off exactly the reminder the row showed: Reminders is read again first and nothing is
    /// written unless it is still open with the same title and due (`ReminderTick`). It says "ticked
    /// off" only once Reminders reads it back as done (`changeReminder`, ADR-229; DOD-08); anything
    /// else says so and asks the person to check.
    func complete(_ reminder: ReminderSummary) async {
        guard !busyReminders.contains(reminder.id) else { return }
        busyReminders.insert(reminder.id)
        defer { busyReminders.remove(reminder.id) }
        undoable = nil
        guard !paused, isOn(.reminders) else {
            reminderNotice = NSLocalizedString("Reminders are off for Doddy, so nothing was ticked off.", comment: "")
            await refresh()
            return
        }
        guard let before = devices.reminderSnapshot(id: reminder.id),
              ReminderTick.stillAsShown(reminder, now: before, local: .current) else {
            reminderNotice = String(format: NSLocalizedString("“%@” changed in Reminders, so it wasn't ticked off. This is how it is now.", comment: ""), reminder.title)
            await refresh()
            return
        }
        do {
            switch try devices.changeReminder(before, .complete) {
            case .verified:
                reminderNotice = String(format: NSLocalizedString("Ticked off: %@. Checked in Reminders.", comment: ""), reminder.title)
                undoable = devices.reminderSnapshot(id: before.id).flatMap { $0.isCompleted ? $0 : nil }
            case .unconfirmed:
                reminderNotice = String(format: NSLocalizedString("Reminders took “%@” but didn't show it as done afterwards. Check it there.", comment: ""), reminder.title)
            case .changedElsewhere:
                reminderNotice = String(format: NSLocalizedString("“%@” changed in Reminders, so it wasn't ticked off. This is how it is now.", comment: ""), reminder.title)
            }
        } catch {
            reminderNotice = String(format: NSLocalizedString("“%@” wasn't ticked off. %@", comment: ""), reminder.title, UserFacingError.message(for: error))
        }
        await refresh()
    }

    /// Undo of the last tick (DOD-09): reopens it only if it is still done as read back, then reads
    /// it again.
    func undoTick() async {
        guard let done = undoable, !busyReminders.contains(done.id) else { return }
        undoable = nil
        busyReminders.insert(done.id)
        defer { busyReminders.remove(done.id) }
        guard !paused, isOn(.reminders) else {
            reminderNotice = NSLocalizedString("Reminders are off for Doddy, so nothing was changed. Open it in Reminders instead.", comment: "")
            await refresh()
            return
        }
        do {
            switch try devices.changeReminder(done, .reopen) {
            case .verified:
                reminderNotice = String(format: NSLocalizedString("Back on your list: %@. Checked in Reminders.", comment: ""), done.title)
            case .unconfirmed:
                reminderNotice = String(format: NSLocalizedString("Reminders took “%@” but didn't show it as open afterwards. Check it there.", comment: ""), done.title)
            case .changedElsewhere:
                reminderNotice = String(format: NSLocalizedString("“%@” changed in Reminders since, so it was left as it is.", comment: ""), done.title)
            }
        } catch {
            reminderNotice = String(format: NSLocalizedString("“%@” wasn't put back. %@", comment: ""), done.title, UserFacingError.message(for: error))
        }
        await refresh()
    }

    // MARK: Adding, changing and deleting a reminder (owner, 13 Nov 2026)

    enum ReminderSaveResult: Equatable {
        /// Written and read back, or nothing needed writing: the sheet closes and the list says what happened.
        case done
        /// Nothing was written, or it couldn't be told: the sheet stays open with what was typed.
        case problem(String)
    }

    /// Reminders is on in Settings › Connections and iOS gives Doddy full access.
    var canWriteReminders: Bool { !paused && isOn(.reminders) }

    private enum Checked {
        case ok(title: String, notes: String?)
        case problem(String)
    }

    private func check(title: String, notes: String, original: String?) -> Checked {
        let cleanTitle: String
        switch ReminderForm.checkTitle(title) {
        case .ok(let value):
            cleanTitle = value
        case .empty:
            return .problem(NSLocalizedString("Write what to remember first.", comment: "Today: a reminder without a title"))
        case .tooLong:
            return .problem(String(format: NSLocalizedString("Keep the title under %lld characters.", comment: ""), ReminderDetails.maxTitleLength))
        }
        switch ReminderForm.checkNotes(notes, original: original) {
        case .ok(let value):
            return .ok(title: cleanTitle, notes: value)
        case .tooLong:
            return .problem(String(format: NSLocalizedString("Keep the notes under %lld characters.", comment: ""), ReminderDetails.maxReplacedNotesLength))
        }
    }

    /// Adds one to the default Reminders list through `ReminderAction.add`: it looks first (so Save again
    /// never makes a second copy), writes, and says "added" only when Reminders reads it back.
    func addReminder(title: String, notes: String, due: Date?, hasTime: Bool) async -> ReminderSaveResult {
        guard canWriteReminders else {
            return .problem(NSLocalizedString("Reminders are off for Doddy, so nothing was added. Turn them on in Settings, Connections.", comment: ""))
        }
        let draft: ReminderDraft
        switch check(title: title, notes: notes, original: nil) {
        case .ok(let cleanTitle, let cleanNotes):
            let dueValue = due.map { ReminderForm.due(from: $0, hasTime: hasTime, calendar: .current) }
            draft = ReminderDraft(title: cleanTitle, due: dueValue, notes: cleanNotes)
        case .problem(let text):
            return .problem(text)
        }
        undoable = nil
        switch await ReminderAction.add(draft, to: devices, now: .now) {
        case .added(let receipt):
            reminderNotice = String(format: NSLocalizedString("Added to Reminders: %@. Checked there.", comment: ""), receipt.title)
            await refresh()
            return .done
        case .alreadyThere(let receipt):
            reminderNotice = String(format: NSLocalizedString("“%@” was already in Reminders, so nothing new was added.", comment: ""), receipt.title)
            await refresh()
            return .done
        case .notAdded(.notAllowed):
            return .problem(NSLocalizedString("iOS doesn't let Doddy use Reminders, so nothing was added. Allow Full Access in iPhone Settings, Privacy, Reminders.", comment: ""))
        case .notAdded(.couldNotCheck):
            return .problem(NSLocalizedString("Reminders couldn't be read just now, so nothing was added. Try again.", comment: ""))
        case .notAdded(.saveFailed(let why)):
            return .problem(String(format: NSLocalizedString("It wasn't added. %@", comment: ""), why))
        case .unknown:
            await refresh()
            return .problem(NSLocalizedString("Reminders didn't confirm it. Look in Reminders before trying again; Save again won't make a second copy.", comment: ""))
        case .needsClarification:
            return .problem(NSLocalizedString("That time has already passed. Pick a later time, or turn the time off.", comment: ""))
        }
    }

    /// The reminder as Reminders has it now, for the edit sheet. Nil, with a line saying so, when it's
    /// gone or already done.
    func reminderToEdit(id: String, title: String) async -> ReminderSnapshot? {
        guard canWriteReminders else {
            reminderNotice = NSLocalizedString("Reminders are off for Doddy, so nothing can be changed here. Turn them on in Settings, Connections.", comment: "")
            return nil
        }
        guard let found = devices.reminderSnapshot(id: id), !found.isCompleted else {
            reminderNotice = String(format: NSLocalizedString("“%@” is no longer open in Reminders. This is how your list is now.", comment: ""), title)
            await refresh()
            return nil
        }
        return found
    }

    /// A new title, notes and due for exactly the reminder the sheet read (`DeviceConnections.editReminder`):
    /// one save, read back, then the list is read again.
    func saveReminder(_ before: ReminderSnapshot, title: String, notes: String, due: ReminderDue?) async -> ReminderSaveResult {
        guard canWriteReminders else {
            return .problem(NSLocalizedString("Reminders are off for Doddy, so nothing was changed. Turn them on in Settings, Connections.", comment: ""))
        }
        guard !busyReminders.contains(before.id) else {
            return .problem(NSLocalizedString("Doddy is still writing this reminder. Try again in a moment.", comment: ""))
        }
        let edit: ReminderEdit
        switch check(title: title, notes: notes, original: before.notes) {
        case .ok(let cleanTitle, let cleanNotes):
            edit = ReminderEdit(title: cleanTitle, notes: cleanNotes, due: due)
        case .problem(let text):
            return .problem(text)
        }
        if edit.changesNothing(before) { return .done }
        busyReminders.insert(before.id)
        defer { busyReminders.remove(before.id) }
        undoable = nil
        let outcome: DeviceConnections.ChangeOutcome
        do {
            outcome = try devices.editReminder(before, edit)
        } catch {
            // A throw doesn't prove nothing was written: look once more before saying so.
            if let now = devices.reminderSnapshot(id: before.id), edit.confirms(now) {
                outcome = .verified
            } else {
                return .problem(String(format: NSLocalizedString("It wasn't saved. %@", comment: ""), UserFacingError.message(for: error)))
            }
        }
        switch outcome {
        case .verified:
            reminderNotice = String(format: NSLocalizedString("Saved in Reminders: %@. Checked there.", comment: ""), edit.title)
            await refresh()
            return .done
        case .changedElsewhere:
            await refresh()
            return .problem(String(format: NSLocalizedString("“%@” changed in Reminders since you opened it, so nothing was saved. Close this and open it again.", comment: ""), before.title))
        case .unconfirmed:
            reminderNotice = String(format: NSLocalizedString("Reminders took the change to “%@” but didn't show it afterwards. Check it there.", comment: ""), edit.title)
            await refresh()
            return .done
        }
    }

    /// Deletes exactly the reminder the sheet read, if it still looks so; "deleted" only when Reminders no
    /// longer has it.
    func deleteReminder(_ before: ReminderSnapshot) async -> ReminderSaveResult {
        guard canWriteReminders else {
            return .problem(NSLocalizedString("Reminders are off for Doddy, so nothing was deleted. Turn them on in Settings, Connections.", comment: ""))
        }
        guard !busyReminders.contains(before.id) else {
            return .problem(NSLocalizedString("Doddy is still writing this reminder. Try again in a moment.", comment: ""))
        }
        busyReminders.insert(before.id)
        defer { busyReminders.remove(before.id) }
        undoable = nil
        let outcome: DeviceConnections.ChangeOutcome
        do {
            outcome = try devices.deleteReminder(before)
        } catch {
            return .problem(String(format: NSLocalizedString("It wasn't deleted. %@", comment: ""), UserFacingError.message(for: error)))
        }
        switch outcome {
        case .verified:
            reminderNotice = String(format: NSLocalizedString("Deleted from Reminders: %@. Checked there.", comment: ""), before.title)
            await refresh()
            return .done
        case .changedElsewhere:
            await refresh()
            return .problem(String(format: NSLocalizedString("“%@” changed in Reminders since you opened it, so it wasn't deleted. Close this and open it again.", comment: ""), before.title))
        case .unconfirmed:
            reminderNotice = String(format: NSLocalizedString("Reminders still shows “%@”. Check it there.", comment: ""), before.title)
            await refresh()
            return .done
        }
    }

    // MARK: Events: Apple's editor, or the Calendar app

    /// A line under Calendar on the screen (why an event opened in the Calendar app, for one).
    func say(_ text: String) {
        notice = text
    }

    /// The event wasn't in Calendar as the screen showed it.
    func eventGone(_ event: CalendarEventSummary) async {
        notice = String(format: NSLocalizedString("“%@” changed in Calendar, so it didn't open. This is how your day is now.", comment: ""), event.title)
        await refresh()
    }

    /// Apple's editor closed: say what Calendar shows now, take a nudge off an event that moved or went,
    /// and read the day again.
    func eventEditorFinished(_ outcome: CalendarEditorOutcome) async {
        switch outcome {
        case .cancelled:
            break
        case .saved(let title, let confirmed, let previousID, let moved):
            var line = confirmed
                ? String(format: NSLocalizedString("Saved in Calendar: %@. Checked there.", comment: ""), title)
                : String(format: NSLocalizedString("Calendar didn't show “%@” as saved afterwards. Check it there.", comment: ""), title)
            if confirmed, moved, let old = nudges.first(where: { $0.eventID == previousID }) {
                if await devices.cancelNudge(id: old.id) {
                    line += " " + NSLocalizedString("Its nudge was for the old time, so it was removed. Set it again with the bell.", comment: "")
                }
            }
            notice = line
        case .deleted(let title, let confirmed, let id):
            var line = confirmed
                ? String(format: NSLocalizedString("Deleted from Calendar: %@. Checked there.", comment: ""), title)
                : String(format: NSLocalizedString("Calendar still shows “%@”. Check it there.", comment: ""), title)
            if confirmed, let old = nudges.first(where: { $0.eventID == id }) {
                if await devices.cancelNudge(id: old.id) {
                    line += " " + NSLocalizedString("Its nudge was removed too.", comment: "")
                }
            }
            notice = line
        }
        await refresh()
    }
}
