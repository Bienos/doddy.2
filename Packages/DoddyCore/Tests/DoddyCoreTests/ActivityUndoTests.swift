import XCTest
@testable import DoddyCore

/// Undo in "What Doddy did" (ADR-265): offered only for changes Doddy made and checked, within a
/// day, and only ever reverses exactly what Doddy did.
final class ActivityUndoTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { date(10, 12) }

    private func event(_ title: String = "Dentist", start: Date, minutes: Int = 60, id: String? = nil) -> CalendarEventSummary {
        CalendarEventSummary(id: id, title: title, start: start, end: start.addingTimeInterval(Double(minutes) * 60), allDay: false)
    }

    private func entry(_ request: VoiceToolRequest, reply: String, undo: ActivityUndo?, at: Date? = nil) -> ActivityEntry {
        ActivityEntry(request: ActivityRequest.describe(request, calendar: calendar)!, reply: reply, at: at ?? now, undo: undo)
    }

    // MARK: When Undo is offered

    func testUndoIsKeptOnlyForChangesDoddyMadeAndChecked() {
        let draft = ReminderDraft(title: "Buy milk", due: nil, notes: nil)
        let receipt = ReminderReceipt(title: "Buy milk", listTitle: "Reminders", due: nil)
        let undo = ActivityUndo.addedReminder(key: ReminderWrite(draft).key, title: "Buy milk", due: nil)
        let add = VoiceToolRequest.createReminder(draft)

        let added = entry(add, reply: VoiceToolReply.reminder(.added(receipt)), undo: undo)
        XCTAssertEqual(added.undo, undo)
        XCTAssertTrue(added.canUndo(now: now))

        // Already there: Doddy added nothing, so there is nothing of Doddy's to remove.
        XCTAssertNil(entry(add, reply: VoiceToolReply.reminder(.alreadyThere(receipt)), undo: undo).undo)
        // Not sure it went in, declined, or failed: never offered.
        XCTAssertNil(entry(add, reply: VoiceToolReply.addUnconfirmed, undo: undo).undo)
        XCTAssertNil(entry(add, reply: VoiceToolReply.declinedReminder, undo: undo).undo)
        XCTAssertNil(entry(add, reply: VoiceToolReply.notAdded("Reminders isn't connected."), undo: undo).undo)
        XCTAssertFalse(entry(add, reply: VoiceToolReply.addUnconfirmed, undo: undo).canUndo(now: now))
    }

    func testVerifiedChangesAreDoneAndUnverifiedOnesAreNot() {
        // Before ADR-265 a checked change was listed as "Not sure it happened".
        let change = VoiceToolRequest.changeReminder(ReminderChangeDraft(title: "Call mum", newDue: nil, markDone: true))
        XCTAssertEqual(entry(change, reply: VoiceToolReply.reminderCompleted("Call mum"), undo: nil).outcome, .done)
        XCTAssertEqual(entry(change, reply: VoiceToolReply.reminderChanged("Call mum", due: nil), undo: nil).outcome, .done)
        XCTAssertEqual(entry(change, reply: VoiceToolReply.eventChanged(event(start: date(11, 9)), calendar: calendar), undo: nil).outcome, .done)
        XCTAssertEqual(entry(change, reply: VoiceToolReply.reminderChangeUnconfirmed, undo: nil).outcome, .notSure)
        XCTAssertEqual(entry(change, reply: VoiceToolReply.reminderChangedElsewhere, undo: nil).outcome, .notDone)
        XCTAssertEqual(entry(change, reply: VoiceToolReply.reminderNotFound("Call mum"), undo: nil).outcome, .notDone)
        XCTAssertEqual(entry(change, reply: VoiceToolReply.changeNothingNew, undo: nil).outcome, .notDone)
        XCTAssertEqual(entry(change, reply: VoiceToolReply.changeDeclined, undo: nil).outcome, .declined)
    }

    func testUndoIsOfferedForADayOnly() {
        let added = event(start: date(11, 9))
        let request = VoiceToolRequest.createCalendarEvent(CalendarEventDraft(title: "Dentist", start: added.start, end: added.end, allDay: false, location: nil, notes: nil))
        let undo = ActivityUndo.addedEvent(eventID: "E1", event: added)
        let done = entry(request, reply: "added: \"Dentist\" on the user's calendar. Checked.", undo: undo)
        XCTAssertEqual(done.outcome, .done)
        XCTAssertTrue(done.canUndo(now: now.addingTimeInterval(23 * 3_600)))
        XCTAssertFalse(done.canUndo(now: now.addingTimeInterval(24 * 3_600)))
        // A clock set back before the entry doesn't open a window either.
        XCTAssertFalse(done.canUndo(now: now.addingTimeInterval(-60)))
    }

    func testAfterUndoTheRowSaysWhatHappenedAndOnlyNothingWrittenCanBeRetried() {
        let undo = ActivityUndo.addedEvent(eventID: "E1", event: event(start: date(11, 9)))
        let done = ActivityEntry(at: now, app: .calendar, title: "Add event", detail: nil, outcome: .done, undo: undo)
        let later = now.addingTimeInterval(60)

        let undone = ActivityLog.undid(done, result: .undone, at: later)
        XCTAssertEqual(undone.undoState, .undone(later))
        XCTAssertEqual(undone.statusText, "Calendar · Undone")
        XCTAssertEqual(undone.note, "You undid this. Checked in Calendar.")
        XCTAssertFalse(undone.canUndo(now: later))

        let leftAlone = ActivityLog.undid(done, result: .leftAlone, at: later)
        XCTAssertEqual(leftAlone.statusText, "Calendar · Done")
        XCTAssertEqual(leftAlone.note, "Not undone: it changed in Calendar since Doddy did this, so Doddy left it alone.")
        XCTAssertFalse(leftAlone.canUndo(now: later))

        let unsure = ActivityLog.undid(done, result: .notSure, at: later)
        XCTAssertEqual(unsure.note, "Doddy couldn't confirm the undo. Check Calendar before trying again.")
        XCTAssertFalse(unsure.canUndo(now: later))

        // Nothing was written (permission off, Pause all): the user can try again.
        let notDone = ActivityLog.undid(done, result: .notDone("Calendar isn't connected."), at: later)
        XCTAssertEqual(notDone.note, "Not undone: Calendar isn't connected. Nothing changed.")
        XCTAssertTrue(notDone.canUndo(now: later))
    }

    func testOlderEntriesWithoutUndoStillDecodeAndUndoSurvivesSaving() throws {
        let old = """
        [{"id":"6F1A2C3E-0000-4000-8000-000000000001","at":0,"app":"calendar","title":"Add event","detail":null,"outcome":"done"}]
        """
        let decoded = try JSONDecoder().decode([ActivityEntry].self, from: Data(old.utf8))
        XCTAssertNil(decoded[0].undo)
        XCTAssertFalse(decoded[0].canUndo(now: Date(timeIntervalSinceReferenceDate: 60)))

        let due = ReminderDue(year: 2026, month: 10, day: 12, hour: 18, minute: 0, timeZoneID: "Europe/Warsaw")
        let undos: [ActivityUndo] = [
            .addedEvent(eventID: "E1", event: event(start: date(11, 9))),
            .addedReminder(key: "k1", title: "Buy milk", due: due),
            .changedEvent(EventChangePlan(before: event(start: date(11, 9), id: "I@1"), after: event(start: date(11, 10), id: "I@1"))),
            .changedReminder(id: "R1", title: "Call mum", oldDue: nil, newDue: due, markedDone: false),
        ]
        for undo in undos {
            var entry = ActivityEntry(at: now, app: undo.app, title: "x", detail: nil, outcome: .done, undo: undo)
            entry.undoState = .notDone(now)
            let back = try JSONDecoder().decode(ActivityEntry.self, from: JSONEncoder().encode(entry))
            XCTAssertEqual(back, entry)
        }
    }

    // MARK: What Undo checks before it writes

    func testAnAddedEventIsRemovedOnlyIfItIsExactlyAsDoddyLeftIt() {
        let added = event(start: date(11, 9))
        XCTAssertTrue(ActivityUndo.unchanged(event(start: date(11, 9), id: "E1@1"), since: added))
        XCTAssertFalse(ActivityUndo.unchanged(event("Dentist!", start: date(11, 9)), since: added))
        XCTAssertFalse(ActivityUndo.unchanged(event(start: date(11, 10)), since: added))
        XCTAssertFalse(ActivityUndo.unchanged(event(start: date(11, 9), minutes: 30), since: added))
    }

    func testAnAddedReminderIsFoundByDoddysMarkerAndMustBeOpenAndUnchanged() {
        let due = ReminderDue(year: 2026, month: 10, day: 12, hour: 18, minute: 0, timeZoneID: "Europe/Warsaw")
        let write = ReminderWrite(ReminderDraft(title: "Buy milk", due: due, notes: nil))
        let mine = ReminderSnapshot(id: "R1", title: "Buy milk", listTitle: "Reminders", due: due, markerURL: write.markerURL)
        let users = ReminderSnapshot(id: "R2", title: "Buy milk", listTitle: "Reminders", due: due, markerURL: nil)

        // The user's own reminder with the same words is never touched.
        XCTAssertEqual(ActivityUndo.addedReminder(key: write.key, in: [users, mine]), mine)
        XCTAssertNil(ActivityUndo.addedReminder(key: write.key, in: [users]))
        // Two with Doddy's marker: Doddy doesn't guess which.
        let copy = ReminderSnapshot(id: "R3", title: "Buy milk", listTitle: "Home", due: due, markerURL: write.markerURL)
        XCTAssertNil(ActivityUndo.addedReminder(key: write.key, in: [mine, copy]))

        XCTAssertTrue(ActivityUndo.unchanged(mine, key: write.key, title: "Buy milk", due: due))
        let renamed = ReminderSnapshot(id: "R1", title: "Buy oat milk", listTitle: "Reminders", due: due, markerURL: write.markerURL)
        XCTAssertFalse(ActivityUndo.unchanged(renamed, key: write.key, title: "Buy milk", due: due))
        let moved = ReminderSnapshot(id: "R1", title: "Buy milk", listTitle: "Reminders", due: nil, markerURL: write.markerURL)
        XCTAssertFalse(ActivityUndo.unchanged(moved, key: write.key, title: "Buy milk", due: due))
        let ticked = ReminderSnapshot(id: "R1", title: "Buy milk", listTitle: "Reminders", due: due, markerURL: write.markerURL, isCompleted: true)
        XCTAssertFalse(ActivityUndo.unchanged(ticked, key: write.key, title: "Buy milk", due: due))
    }

    func testAChangedReminderMustStillLookAsDoddyLeftIt() {
        let old = ReminderDue(year: 2026, month: 10, day: 12, timeZoneID: nil)
        let new = ReminderDue(year: 2026, month: 10, day: 13, hour: 9, minute: 0, timeZoneID: "Europe/Warsaw")
        let open = ReminderSnapshot(id: "R1", title: "Call mum", listTitle: "Reminders", due: new, markerURL: nil)
        XCTAssertTrue(ActivityUndo.unchangedSinceChange(open, title: "Call mum", newDue: new, oldDue: old, markedDone: false))
        XCTAssertFalse(ActivityUndo.unchangedSinceChange(open, title: "Call mum", newDue: old, oldDue: old, markedDone: false))

        let done = ReminderSnapshot(id: "R1", title: "Call mum", listTitle: "Reminders", due: old, markerURL: nil, isCompleted: true)
        XCTAssertTrue(ActivityUndo.unchangedSinceChange(done, title: "Call mum", newDue: nil, oldDue: old, markedDone: true))
        // Opened again by the user since: nothing to undo.
        let reopened = ReminderSnapshot(id: "R1", title: "Call mum", listTitle: "Reminders", due: old, markerURL: nil)
        XCTAssertFalse(ActivityUndo.unchangedSinceChange(reopened, title: "Call mum", newDue: nil, oldDue: old, markedDone: true))
    }

    func testAMovedEventGoesBackFromItsCurrentOccurrence() {
        let before = event("Dentist", start: date(11, 9), id: CalendarEventSummary.occurrenceID(itemID: "ITEM@x", start: date(11, 9)))
        let after = CalendarEventSummary(id: before.id, title: "Dentist (moved)", start: date(11, 15), end: date(11, 16), allDay: false)
        let back = ActivityUndo.reversed(EventChangePlan(before: before, after: after))

        // Found where Doddy left it, under that occurrence's id …
        XCTAssertEqual(back.before.id, CalendarEventSummary.occurrenceID(itemID: "ITEM@x", start: date(11, 15)))
        XCTAssertEqual(back.before.title, "Dentist (moved)")
        XCTAssertEqual(back.before.start, date(11, 15))
        // … and put back exactly as it was.
        XCTAssertEqual(back.after, before)
    }

    func testOccurrenceIDsRoundTrip() {
        let id = CalendarEventSummary.occurrenceID(itemID: "A@B", start: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(id, "A@B@1790000000")
        XCTAssertEqual(CalendarEventSummary.itemID(fromOccurrence: id), "A@B")
        XCTAssertNil(CalendarEventSummary.itemID(fromOccurrence: "no-at-sign"))
        XCTAssertNil(CalendarEventSummary.itemID(fromOccurrence: "@123"))
        XCTAssertNil(CalendarEventSummary.itemID(fromOccurrence: "item@notanumber"))
    }

    func testPauseAllAndTheConnectionSwitchStopUndoBeforeAnythingIsTouched() {
        let undo = ActivityUndo.addedReminder(key: "k", title: "Buy milk", due: nil)
        XCTAssertEqual(undo.connection, .reminders)
        XCTAssertNil(undo.blocked(pauseAll: false, connectionOn: true))
        XCTAssertEqual(undo.blocked(pauseAll: true, connectionOn: true), "Connections are paused in Settings.")
        XCTAssertEqual(undo.blocked(pauseAll: false, connectionOn: false), "Reminders is off in Settings, Connections.")
        XCTAssertEqual(ActivityUndo.addedEvent(eventID: "E", event: event(start: date(11, 9))).connection, .calendar)
    }

    func testOnlyAReminderDoddyWroteAndReadBackCanBeRemoved() {
        let draft = ReminderDraft(title: "Buy milk", due: nil, notes: nil)
        let receipt = ReminderReceipt(title: "Buy milk", listTitle: "Reminders", due: nil)
        XCTAssertEqual(
            ActivityUndo.addedReminder(.added(receipt), draft: draft),
            .addedReminder(key: ReminderWrite(draft).key, title: "Buy milk", due: nil))
        XCTAssertNil(ActivityUndo.addedReminder(.alreadyThere(receipt), draft: draft))
        XCTAssertNil(ActivityUndo.addedReminder(.unknown, draft: draft))
        XCTAssertNil(ActivityUndo.addedReminder(.notAdded(.notAllowed), draft: draft))
    }

    func testAPlanStepKeepsUndoLikeASingleCard() {
        let added = event(start: date(11, 9))
        let undo = ActivityUndo.addedEvent(eventID: "E1", event: added)
        let request = ActivityRequest(app: .calendar, title: "Add event", detail: nil, isLookup: false)
        let ref = ActivityPlanRef(id: UUID(), step: 2, count: 3)
        let step = ActivityEntry(request: request, reply: "added: \"Dentist\" on Sun 11 Oct 2026, 09:00.", at: now, plan: ref, undo: undo)
        XCTAssertEqual(step.plan, ref)
        XCTAssertTrue(step.canUndo(now: now))
        // An unticked or blocked step never ran, so there is nothing to put back.
        XCTAssertFalse(ActivityEntry(request: request, reply: PlanReply.unticked, at: now, plan: ref, undo: undo).canUndo(now: now))
    }

    // MARK: "Undo that" by voice (ADR-268)

    func testUndoThatFindsTheNewestUndoableChangeFromThisConversationOnly() {
        let undo = ActivityUndo.addedEvent(eventID: "E1", event: event(start: date(11, 9)))
        let start = now.addingTimeInterval(-600)
        func row(_ minutesAgo: Double, outcome: ActivityOutcome = .done, undo: ActivityUndo? = undo) -> ActivityEntry {
            ActivityEntry(at: now.addingTimeInterval(-minutesAgo * 60), app: .calendar, title: "Add event", detail: nil, outcome: outcome, undo: undo)
        }
        let earlierConversation = row(30)
        let first = row(8)
        let newest = row(2)
        let lookup = row(1, outcome: .lookedUp, undo: nil)
        let notSure = row(1, outcome: .notSure)
        var undone = row(0.5)
        undone.undoState = .undone(now)

        let entries = [lookup, notSure, undone, newest, first, earlierConversation]
        XCTAssertEqual(ActivityUndo.latest(in: entries, since: start, now: now), newest)
        XCTAssertEqual(ActivityUndo.latest(in: [first, earlierConversation], since: start, now: now), first)
        // Something from an earlier conversation is never "that".
        XCTAssertNil(ActivityUndo.latest(in: [earlierConversation, lookup, notSure, undone], since: start, now: now))
        XCTAssertNil(ActivityUndo.latest(in: [], since: start, now: now))
    }

    func testUndoThatIsPausedLoggedOnItsRowAndAnswersOnlyWhatHappened() {
        XCTAssertEqual(VoiceToolRequest.parse(name: "undo_last", parametersJSON: Data("{}".utf8)), .undoLast)
        XCTAssertTrue(ConnectionPause.applies(to: .undoLast))
        XCTAssertNil(ActivityRequest.describe(.undoLast, calendar: calendar))
        XCTAssertFalse(TranslatorPolicy.allows(.undoLast))

        let added = ActivityUndo.addedEvent(eventID: "E1", event: event(start: date(11, 9)))
        XCTAssertEqual(VoiceToolReply.undo(.undone, added), "undone: \"Dentist\" was removed from Calendar. Checked.")
        let ticked = ActivityUndo.changedReminder(id: "R1", title: "Call mum", oldDue: nil, newDue: nil, markedDone: true)
        XCTAssertEqual(VoiceToolReply.undo(.undone, ticked), "undone: \"Call mum\" is open again in Reminders. Checked.")
        XCTAssertEqual(
            VoiceToolReply.undo(.leftAlone, ticked),
            "not undone: it changed in Reminders since Doddy did it, so Doddy left it alone. Nothing changed.")
        XCTAssertEqual(
            VoiceToolReply.undo(.notDone("Connections are paused in Settings."), added),
            "failed: not undone. Connections are paused in Settings. Nothing changed.")
        XCTAssertEqual(
            VoiceToolReply.undo(.notSure, added),
            "unknown: Doddy couldn't confirm the undo. Ask the user to check Calendar before trying again.")
        // Only "undone" may be reported as done; nothing else starts with it.
        for result: UndoResult in [.leftAlone, .notDone("x"), .notSure] {
            XCTAssertFalse(VoiceToolReply.undo(result, added).hasPrefix("undone"))
        }
    }

    // MARK: The two Undo buttons agree (ADR-265 merge with the default line's ADR-258)

    func testUndoOnTheVoiceScreenMarksTheSameRowUndone() {
        let before = event(start: date(11, 9), id: CalendarEventSummary.occurrenceID(itemID: "I", start: date(11, 9)))
        let after = CalendarEventSummary(id: before.id, title: "Dentist", start: date(11, 15), end: date(11, 16), allDay: false)
        let plan = EventChangePlan(before: before, after: after)
        let moved = ActivityEntry(at: now, app: .calendar, title: "Change event", detail: nil, outcome: .done, undo: .changedEvent(plan))
        let other = ActivityEntry(at: now, app: .calendar, title: "Add event", detail: nil, outcome: .done,
                                  undo: .addedEvent(eventID: "E", event: before))
        let ticked = ActivityEntry(at: now, app: .reminders, title: "Change reminder", detail: nil, outcome: .done,
                                   undo: .changedReminder(id: "R1", title: "Call mum", oldDue: nil, newDue: nil, markedDone: true))

        let row = ActivityLog.undoneOnScreen([other, moved, ticked], event: plan, reminderID: nil, now: now)
        XCTAssertEqual(row?.id, moved.id)
        XCTAssertEqual(row?.undoState, .undone(now))
        XCTAssertFalse(row!.canUndo(now: now))
        XCTAssertEqual(ActivityLog.undoneOnScreen([other, moved, ticked], event: nil, reminderID: "R1", now: now)?.id, ticked.id)
        // An add is never "the same change" as a receipt for a move or a tick.
        XCTAssertNil(ActivityLog.undoneOnScreen([other], event: plan, reminderID: "R1", now: now))
        // Both Undo paths reverse a move the same way.
        XCTAssertEqual(ActivityUndo.reversed(plan), EventChange.reversed(plan))
    }

    // MARK: What the user is asked

    func testTheSheetIsInPolishOnAPolishIPhone() {
        XCTAssertEqual(NotificationLanguage.preferred(["pl-PL", "en-GB"]), .polish)
        let added = ActivityUndo.addedEvent(eventID: "E1", event: event(start: date(11, 9)))
        XCTAssertEqual(added.question(.polish), "Usunąć „Dentist” z Kalendarza?")
        XCTAssertEqual(added.buttonTitle(.polish), "Usuń")
        XCTAssertEqual(
            added.explanation(calendar: calendar, language: .polish),
            "Doddy dodał to wydarzenie na 2026-10-11 09:00. Usunięte zostanie tylko to wydarzenie i tylko wtedy, gdy od tamtej pory się nie zmieniło.")

        let due = ReminderDue(year: 2026, month: 10, day: 12, hour: 18, minute: 0, timeZoneID: "Europe/Warsaw")
        let reminder = ActivityUndo.addedReminder(key: "k", title: "Kupić mleko", due: due)
        XCTAssertEqual(reminder.question(.polish), "Usunąć „Kupić mleko” z Przypomnień?")
        XCTAssertTrue(reminder.explanation(calendar: calendar, language: .polish).contains("(termin: 2026-10-12 18:00)"))
        XCTAssertTrue(ActivityUndo.addedReminder(key: "k", title: "x", due: nil).explanation(calendar: calendar, language: .polish).contains("bez terminu"))

        let retimed = ActivityUndo.changedReminder(id: "R1", title: "Zadzwonić do mamy", oldDue: nil, newDue: due, markedDone: false)
        XCTAssertEqual(retimed.question(.polish), "Przywrócić poprzedni termin „Zadzwonić do mamy”?")
        XCTAssertEqual(retimed.buttonTitle(.polish), "Przywróć")
        XCTAssertEqual(
            retimed.explanation(calendar: calendar, language: .polish),
            "Termin zostanie usunięty, jak było przed zmianą (teraz: 2026-10-12 18:00). Tylko jeśli od tamtej pory się nie zmienił.")
        let earlier = ReminderDue(year: 2026, month: 10, day: 11, timeZoneID: nil)
        XCTAssertEqual(
            ActivityUndo.changedReminder(id: "R1", title: "x", oldDue: earlier, newDue: due, markedDone: false).explanation(calendar: calendar, language: .polish),
            "Termin wróci na 2026-10-11 z 2026-10-12 18:00. Tylko jeśli od tamtej pory się nie zmienił.")
        let ticked = ActivityUndo.changedReminder(id: "R1", title: "Zadzwonić do mamy", oldDue: nil, newDue: nil, markedDone: true)
        XCTAssertEqual(ticked.buttonTitle(.polish), "Oznacz jako niezrobione")

        let allDay = CalendarEventSummary(title: "Urlop", start: date(12, 0), end: date(13, 0), allDay: true)
        let moved = ActivityUndo.changedEvent(EventChangePlan(before: allDay, after: CalendarEventSummary(title: "Wolne", start: date(14, 0), end: date(15, 0), allDay: true)))
        XCTAssertEqual(moved.question(.polish), "Przywrócić „Urlop”?")
        XCTAssertEqual(
            moved.explanation(calendar: calendar, language: .polish),
            "Wróci na 2026-10-12 (cały dzień) z 2026-10-14 (cały dzień), a jego nazwa wróci z „Wolne”. Tylko jeśli od tamtej pory się nie zmieniło.")
        // English stays the default.
        XCTAssertEqual(moved.question(), "Put “Urlop” back?")
    }

    func testTheSheetNamesExactlyWhatWillHappen() {
        let added = ActivityUndo.addedEvent(eventID: "E1", event: event(start: date(11, 9)))
        XCTAssertEqual(added.question(), "Remove “Dentist” from Calendar?")
        XCTAssertEqual(added.buttonTitle(), "Remove")
        XCTAssertTrue(added.explanation(calendar: calendar).contains("Only this event is removed"))

        let reminder = ActivityUndo.addedReminder(key: "k", title: "Buy milk", due: nil)
        XCTAssertEqual(reminder.question(), "Remove “Buy milk” from Reminders?")
        XCTAssertTrue(reminder.explanation(calendar: calendar).contains("No due date"))

        let ticked = ActivityUndo.changedReminder(id: "R1", title: "Call mum", oldDue: nil, newDue: nil, markedDone: true)
        XCTAssertEqual(ticked.question(), "Mark “Call mum” not done?")
        XCTAssertEqual(ticked.buttonTitle(), "Mark not done")

        let before = event(start: date(11, 9)), after = event("Check-up", start: date(11, 15))
        let moved = ActivityUndo.changedEvent(EventChangePlan(before: before, after: after))
        XCTAssertEqual(moved.question(), "Put “Dentist” back?")
        XCTAssertTrue(moved.explanation(calendar: calendar).contains("its name goes back from “Check-up”"))
        XCTAssertEqual(moved.app, .calendar)
    }
}
