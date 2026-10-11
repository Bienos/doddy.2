import DoddyCore
import XCTest

/// Moving and renaming events, changing and completing reminders by voice (ADR-229).
final class CalendarChangeTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 8))! }
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    private func parse(_ name: String, _ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: name, parametersJSON: Data(json.utf8), now: now, calendar: calendar)
    }

    func testParsingNeedsTheEventAndOneChange() {
        guard case .changeCalendarEvent(let draft) = parse(VoiceToolName.changeCalendarEvent,
            #"{"title":"Dentist","start":"2026-10-10T09:30","new_start":"2026-10-12T15:00"}"#) else { return XCTFail() }
        XCTAssertEqual(draft.currentStart, at(10, 9, 30))
        XCTAssertEqual(draft.newStart, at(12, 15))
        XCTAssertFalse(draft.currentIsDayOnly)

        guard case .invalid = parse(VoiceToolName.changeCalendarEvent, #"{"title":"Dentist","start":"2026-10-10T09:30"}"#) else {
            return XCTFail("a change with nothing new is refused")
        }
        guard case .needsClarification = parse(VoiceToolName.changeCalendarEvent,
            #"{"title":"Dentist","start":"2026-10-10T09:30","new_start":"2026-10-01T15:00"}"#) else {
            return XCTFail("a new time in the past is asked about, not used")
        }
        guard case .changeReminder(let done) = parse(VoiceToolName.changeReminder, #"{"title":"Call mum","done":true}"#), done.markDone else {
            return XCTFail()
        }
        guard case .invalid = parse(VoiceToolName.changeReminder, #"{"title":"Call mum","done":true,"new_due":"2026-10-12"}"#) else {
            return XCTFail("either a new due or done, never both")
        }
        XCTAssertEqual(VoiceConnection.serving(VoiceToolName.changeCalendarEvent), .calendar)
        XCTAssertEqual(VoiceConnection.serving(VoiceToolName.changeReminder), .reminders)
    }

    func testMatchesExactlyOneEventAndNeverGuesses() {
        let dentist = CalendarEventSummary(id: "a", title: "Dentist – Dr. Nowak", start: at(10, 9, 30), end: at(10, 10, 30), allDay: false)
        let other = CalendarEventSummary(id: "b", title: "Dentist", start: at(10, 9, 30), end: at(10, 10), allDay: false)
        let later = CalendarEventSummary(id: "c", title: "dentist", start: at(10, 16), end: at(10, 17), allDay: false)
        let draft = EventChangeDraft(title: "dentist", currentStart: at(10, 9, 30), currentIsDayOnly: false, newStart: at(12, 15), newEnd: nil, newTitle: nil)
        XCTAssertEqual(EventChange.match(draft, in: [dentist, other, later], calendar: calendar), .one(other), "same words, same minute")
        let dayOnly = EventChangeDraft(title: "Dentist", currentStart: at(10, 0), currentIsDayOnly: true, newStart: nil, newEnd: nil, newTitle: "x")
        XCTAssertEqual(EventChange.match(dayOnly, in: [other, later], calendar: calendar), .several([other, later]))
        let missing = EventChangeDraft(title: "Doctor", currentStart: at(10, 9, 30), currentIsDayOnly: false, newStart: nil, newEnd: nil, newTitle: "x")
        XCTAssertEqual(EventChange.match(missing, in: [dentist, other], calendar: calendar), .none)
    }

    func testPlanKeepsTheLengthAndShowsBeforeAndAfter() throws {
        let event = CalendarEventSummary(id: "a", title: "Dentist", start: at(10, 9, 30), end: at(10, 10, 30), allDay: false)
        let move = EventChangeDraft(title: "Dentist", currentStart: at(10, 9, 30), currentIsDayOnly: false, newStart: at(12, 15), newEnd: nil, newTitle: nil)
        let plan = try XCTUnwrap(EventChange.plan(move, for: event, calendar: calendar))
        XCTAssertEqual(plan.before, event)
        XCTAssertEqual(plan.after.start, at(12, 15))
        XCTAssertEqual(plan.after.end, at(12, 16), "one hour, as before")
        let rename = EventChangeDraft(title: "Dentist", currentStart: at(10, 9, 30), currentIsDayOnly: false, newStart: nil, newEnd: nil, newTitle: "Dentist (Nowak)")
        XCTAssertEqual(EventChange.plan(rename, for: event, calendar: calendar)?.after.title, "Dentist (Nowak)")
        let backwards = EventChangeDraft(title: "Dentist", currentStart: at(10, 9, 30), currentIsDayOnly: false, newStart: nil, newEnd: at(10, 9), newTitle: nil)
        XCTAssertNil(EventChange.plan(backwards, for: event, calendar: calendar), "end before start")
        let same = EventChangeDraft(title: "Dentist", currentStart: at(10, 9, 30), currentIsDayOnly: false, newStart: at(10, 9, 30), newEnd: nil, newTitle: nil)
        XCTAssertNil(EventChange.plan(same, for: event, calendar: calendar), "nothing would change")

        let allDay = CalendarEventSummary(id: "d", title: "Trip", start: at(14, 0), end: at(16, 0), allDay: true)
        let moveTrip = EventChangeDraft(title: "Trip", currentStart: at(14, 0), currentIsDayOnly: true, newStart: at(20, 0), newEnd: nil, newTitle: nil)
        let trip = try XCTUnwrap(EventChange.plan(moveTrip, for: allDay, calendar: calendar))
        XCTAssertEqual(trip.after.start, at(20, 0))
        XCTAssertEqual(trip.after.end, at(22, 0), "still two days, still all day")
        XCTAssertTrue(trip.after.allDay)
    }

    /// Review C7: "move the dentist to Monday" keeps 09:30; it never lands at midnight.
    func testADayOnlyMoveKeepsTheTimeOfDay() throws {
        guard case .changeCalendarEvent(let draft) = parse(VoiceToolName.changeCalendarEvent,
            #"{"title":"Dentist","start":"2026-10-10T09:30","new_start":"2026-10-12"}"#) else { return XCTFail() }
        XCTAssertTrue(draft.newStartIsDayOnly)
        let event = CalendarEventSummary(id: "a", title: "Dentist", start: at(10, 9, 30), end: at(10, 10, 30), allDay: false)
        let plan = try XCTUnwrap(EventChange.plan(draft, for: event, calendar: calendar))
        XCTAssertEqual(plan.after.start, at(12, 9, 30))
        XCTAssertEqual(plan.after.end, at(12, 10, 30))
        XCTAssertFalse(plan.after.allDay)
        XCTAssertEqual(ActivityRequest.describe(.changeCalendarEvent(draft), calendar: calendar)?.detail, "“Dentist” to 2026-10-12")
        // A time the clocks skip that day is not shifted: there is no plan, and the agent asks.
        let night = CalendarEventSummary(id: "b", title: "Night shift", start: at(20, 2, 30), end: at(20, 3, 30), allDay: false)
        let toSpringForward = EventChangeDraft(
            title: "Night shift", currentStart: night.start, currentIsDayOnly: false,
            newStart: calendar.date(from: DateComponents(year: 2027, month: 3, day: 28))!, newEnd: nil, newTitle: nil, newStartIsDayOnly: true)
        XCTAssertNil(EventChange.plan(toSpringForward, for: night, calendar: calendar))
        // A written-out time still moves to that time.
        guard case .changeCalendarEvent(let timed) = parse(VoiceToolName.changeCalendarEvent,
            #"{"title":"Dentist","start":"2026-10-10T09:30","new_start":"2026-10-12T00:00"}"#) else { return XCTFail() }
        XCTAssertFalse(timed.newStartIsDayOnly)
        XCTAssertEqual(EventChange.plan(timed, for: event, calendar: calendar)?.after.start, at(12, 0))
    }

    func testTheCardCanGoStaleAndReadBackComparesWallClock() throws {
        let event = CalendarEventSummary(id: "a", title: "Dentist", start: at(10, 9, 30), end: at(10, 10, 30), allDay: false)
        let move = EventChangeDraft(title: "Dentist", currentStart: at(10, 9, 30), currentIsDayOnly: false, newStart: at(12, 15), newEnd: nil, newTitle: nil)
        let plan = try XCTUnwrap(EventChange.plan(move, for: event, calendar: calendar))
        XCTAssertFalse(EventChange.startPassed(plan, now: now, calendar: calendar))
        XCTAssertTrue(EventChange.startPassed(plan, now: at(12, 15, 1), calendar: calendar))
        let range = EventChange.searchRange(move, calendar: calendar)
        XCTAssertEqual(range.start, at(10, 0))
        XCTAssertEqual(range.end, at(11, 0))
        let written = ReminderDue(year: 2026, month: 10, day: 12, hour: 9, minute: 0, timeZoneID: "Europe/Warsaw")
        let readBack = ReminderDue(year: 2026, month: 10, day: 12, hour: 9, minute: nil, timeZoneID: nil)
        XCTAssertTrue(EventChange.sameDue(written, readBack))
        XCTAssertFalse(EventChange.sameDue(written, nil))
        XCTAssertEqual(EventChange.moment(written, local: calendar), at(12, 9))
        XCTAssertTrue(EventChange.duePassed(written, now: at(12, 9), local: calendar))
        XCTAssertFalse(EventChange.duePassed(ReminderDue(year: 2026, month: 10, day: 9, timeZoneID: nil), now: now, local: calendar), "a day without a time never counts as passed")
    }

    /// ADR-258: undo is the same checked change backwards, with the moved occurrence's id.
    func testUndoIsTheChangeBackwards() throws {
        let event = CalendarEventSummary(id: "abc@\(Int(at(10, 9, 30).timeIntervalSince1970))", title: "Dentist", start: at(10, 9, 30), end: at(10, 10, 30), allDay: false)
        let move = EventChangeDraft(title: "Dentist", currentStart: at(10, 9, 30), currentIsDayOnly: false, newStart: at(12, 15), newEnd: nil, newTitle: "Dentist (Nowak)")
        let plan = try XCTUnwrap(EventChange.plan(move, for: event, calendar: calendar))
        let undo = EventChange.reversed(plan)
        XCTAssertEqual(undo.before.id, "abc@\(Int(at(12, 15).timeIntervalSince1970))")
        XCTAssertEqual(undo.before.title, "Dentist (Nowak)")
        XCTAssertEqual(undo.after, event, "back exactly as it was")
    }

    /// ADR-259: deleting names the thing exactly; it is paused and logged like other app changes.
    func testDeletingIsParsedPausedAndLogged() {
        guard case .deleteCalendarEvent(let draft) = parse(VoiceToolName.deleteCalendarEvent, #"{"title":"Dentist","start":"2026-10-10T09:30"}"#) else {
            return XCTFail()
        }
        XCTAssertEqual(draft.currentStart, at(10, 9, 30))
        guard case .invalid = parse(VoiceToolName.deleteCalendarEvent, #"{"title":"Dentist"}"#) else { return XCTFail("the start is needed") }
        XCTAssertEqual(parse(VoiceToolName.deleteReminder, #"{"title":"Call mum"}"#), .deleteReminder(title: "Call mum"))
        XCTAssertEqual(VoiceConnection.serving(VoiceToolName.deleteCalendarEvent), .calendar)
        XCTAssertEqual(VoiceConnection.serving(VoiceToolName.deleteReminder), .reminders)
        XCTAssertTrue(ConnectionPause.applies(to: .deleteReminder(title: "x")))
        XCTAssertEqual(ActivityRequest.describe(.deleteReminder(title: "Call mum"), calendar: calendar)?.title, "Delete reminder")
        XCTAssertTrue(VoiceToolReply.reminderDeleted("Call mum").hasPrefix("deleted:"))
    }

    func testRemindersMatchOpenOnesOnly() {
        let open = ReminderSnapshot(id: "1", title: "Call mum", listTitle: "Home", due: nil, markerURL: nil)
        let done = ReminderSnapshot(id: "2", title: "call mum", listTitle: "Home", due: nil, markerURL: nil, isCompleted: true)
        XCTAssertEqual(EventChange.matchReminder("CALL MUM", in: [open, done]), .one(open))
        XCTAssertTrue(VoiceToolReply.reminderCompleted("Call mum").hasPrefix("completed:"))
    }

    func testPausedAndLoggedLikeOtherAppChanges() {
        let draft = ReminderChangeDraft(title: "Call mum", newDue: nil, markDone: true)
        XCTAssertTrue(ConnectionPause.applies(to: .changeReminder(draft)))
        XCTAssertEqual(ActivityRequest.describe(.changeReminder(draft), calendar: calendar)?.title, "Change reminder")
    }
}

/// Event details by voice (ADR-281): a new place, a line added to the notes.
final class EventDetailsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 8))! }
    private var dentist: CalendarEventSummary {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 9, minute: 30))!
        return CalendarEventSummary(id: "abc@1", title: "Dentist", start: start, end: start.addingTimeInterval(3600), allDay: false)
    }

    func testAPlaceOrANoteAloneIsAChange() {
        guard case .changeCalendarEvent(let draft) = VoiceToolRequest.parse(name: VoiceToolName.changeCalendarEvent,
            parametersJSON: Data(#"{"title":"Dentist","start":"2026-10-10T09:30","new_location":"Marszałkowska 10","add_note":"Bring the X-ray"}"#.utf8),
            now: now, calendar: calendar) else { return XCTFail() }
        let plan = EventChange.plan(draft, for: dentist, locationBefore: "Old clinic", calendar: calendar)
        XCTAssertEqual(plan?.after, dentist, "the time and title stay")
        XCTAssertEqual(plan?.newLocation, "Marszałkowska 10")
        XCTAssertEqual(plan?.addNote, "Bring the X-ray")
        let reply = VoiceToolReply.eventChanged(plan!, calendar: calendar)
        XCTAssertTrue(reply.hasPrefix("changed: the event is now "))
        XCTAssertTrue(reply.contains(" Its place changed. A line was added to its notes. Checked in Calendar.\n"), reply)
        XCTAssertTrue(reply.hasSuffix("<<<DATA\nTitle: \"Dentist\"\nNew place: \"Marszałkowska 10\"\nAdded to its notes: \"Bring the X-ray\"\nDATA>>>"), reply)
        XCTAssertFalse(reply.contains("Old clinic"), "the old place is never sent to the agent")
        // The same place again is no change.
        let same = EventChangeDraft(title: "Dentist", currentStart: dentist.start, currentIsDayOnly: false, newStart: nil, newEnd: nil, newTitle: nil, newLocation: "Old clinic")
        XCTAssertNil(EventChange.plan(same, for: dentist, locationBefore: "Old clinic", calendar: calendar))
    }

    func testNotesAreOnlyAddedToAndUndoTakesTheLineOffAgain() {
        XCTAssertEqual(EventChange.notes(nil, adding: "Bring the X-ray"), "Bring the X-ray")
        XCTAssertEqual(EventChange.notes("Floor 2", adding: "Bring the X-ray"), "Floor 2\nBring the X-ray")
        XCTAssertEqual(EventChange.notes("Floor 2\nBring the X-ray", removing: "Bring the X-ray"), .some("Floor 2"))
        XCTAssertEqual(EventChange.notes("Bring the X-ray", removing: "Bring the X-ray"), .some(nil))
        XCTAssertNil(EventChange.notes("Floor 2\nBring the X-ray\nedited", removing: "Bring the X-ray"), "changed since: Undo leaves it")
        let plan = EventChangePlan(before: dentist, after: dentist, locationBefore: "Old clinic", newLocation: "New clinic", addNote: "Bring the X-ray")
        let back = EventChange.reversed(plan)
        XCTAssertEqual(back.newLocation, "Old clinic")
        XCTAssertEqual(back.locationBefore, "New clinic")
        XCTAssertEqual(back.removeNote, "Bring the X-ray")
        XCTAssertNil(back.addNote)
    }

    func testTooLongDetailsAreRefused() {
        let long = String(repeating: "x", count: 501)
        guard case .invalid = VoiceToolRequest.parse(name: VoiceToolName.changeCalendarEvent,
            parametersJSON: Data(#"{"title":"Dentist","start":"2026-10-10T09:30","add_note":"\#(long)"}"#.utf8),
            now: now, calendar: calendar) else { return XCTFail() }
    }
}
