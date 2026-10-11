import XCTest
@testable import DoddyCore

final class ReminderDetailsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    private let now = ISO8601DateFormatter().date(from: "2026-10-11T08:00:00Z")!

    private func parse(_ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: "change_reminder", parametersJSON: Data(json.utf8), now: now, calendar: calendar)
    }

    func testDetailsAloneOrWithANewDue() {
        guard case .changeReminder(let draft) = parse(#"{"title": "Call the bank", "add_note": "ask about the card", "priority": "High", "move_to_list": "work"}"#) else {
            return XCTFail("details alone are a change")
        }
        XCTAssertEqual(draft.addNote, "ask about the card")
        XCTAssertEqual(draft.priority, .high)
        XCTAssertEqual(draft.listName, "work")
        XCTAssertNil(draft.newDue)
        XCTAssertTrue(draft.changesDetails)

        guard case .changeReminder(let both) = parse(#"{"title": "Call the bank", "new_due": "2026-10-12T09:00", "priority": "none"}"#) else {
            return XCTFail("a due and a detail together")
        }
        XCTAssertNotNil(both.newDue)
        XCTAssertEqual(both.priority, ReminderPriority.none)
    }

    func testDoneStaysOnItsOwnAndNonsenseIsRefused() {
        if case .invalid = parse(#"{"title": "X", "done": true, "priority": "high"}"#) {} else { XCTFail("done goes alone") }
        if case .invalid = parse(#"{"title": "X", "priority": "urgent"}"#) {} else { XCTFail("unknown priority") }
        if case .invalid = parse(#"{"title": "X"}"#) {} else { XCTFail("nothing to change") }
        if case .changeReminder(let draft) = parse(#"{"title": "X", "done": true}"#) { XCTAssertFalse(draft.changesDetails) } else { XCTFail() }
    }

    func testPriorityAsRemindersStoresIt() {
        XCTAssertEqual(ReminderPriority.high.eventKitValue, 1)
        XCTAssertEqual(ReminderPriority.from(eventKit: 3), .high)
        XCTAssertEqual(ReminderPriority.from(eventKit: 5), .medium)
        XCTAssertEqual(ReminderPriority.from(eventKit: 7), .low)
        XCTAssertEqual(ReminderPriority.from(eventKit: 0), ReminderPriority.none)
        for priority in ReminderPriority.allCases { XCTAssertEqual(ReminderPriority.from(eventKit: priority.eventKitValue), priority) }
    }

    func testListMatchingNeverGuesses() {
        let lists = [ReminderListRef(id: "a", title: "Work"), ReminderListRef(id: "b", title: "Zakupy"), ReminderListRef(id: "c", title: "Home"), ReminderListRef(id: "d", title: "home!")]
        XCTAssertEqual(ReminderDetails.matchList("work", in: lists), .one(lists[0]))
        XCTAssertEqual(ReminderDetails.matchList("zakupy", in: lists), .one(lists[1]))
        XCTAssertEqual(ReminderDetails.matchList("Home", in: lists), .several([lists[2], lists[3]]))
        XCTAssertEqual(ReminderDetails.matchList("Wor", in: lists), .none)
        XCTAssertTrue(VoiceToolReply.reminderListNotFound("Office", lists: lists).hasPrefix("not found:"))
    }

    func testReadBackMustShowEveryChange() {
        let list = ReminderListRef(id: "w", title: "Work")
        let change = ReminderDetailsChange(addNote: "ask about the card", priority: .high, toList: list)
        let good = ReminderSnapshot(id: "1", title: "Call the bank", listTitle: "Work", due: nil, markerURL: nil, priority: .high, listID: "w")
        XCTAssertTrue(ReminderDetails.confirms(good, notes: "old\nask about the card", change: change, newDue: nil))
        XCTAssertFalse(ReminderDetails.confirms(good, notes: "old", change: change, newDue: nil), "note missing")
        let wrongList = ReminderSnapshot(id: "1", title: "Call the bank", listTitle: "Home", due: nil, markerURL: nil, priority: .high, listID: "h")
        XCTAssertFalse(ReminderDetails.confirms(wrongList, notes: "ask about the card", change: change, newDue: nil))
        let done = ReminderSnapshot(id: "1", title: "Call the bank", listTitle: "Work", due: nil, markerURL: nil, isCompleted: true, priority: .high, listID: "w")
        XCTAssertFalse(ReminderDetails.confirms(done, notes: "ask about the card", change: change, newDue: nil))
    }

    func testNothingNewIsSaidSo() {
        let reminder = ReminderSnapshot(id: "1", title: "X", listTitle: "Work", due: nil, markerURL: nil, priority: .high, listID: "w")
        XCTAssertTrue(ReminderDetails.changesNothing(reminder, change: ReminderDetailsChange(priority: .high, toList: ReminderListRef(id: "w", title: "Work")), newDue: nil))
        XCTAssertFalse(ReminderDetails.changesNothing(reminder, change: ReminderDetailsChange(priority: .low), newDue: nil))
        XCTAssertFalse(ReminderDetails.changesNothing(reminder, change: ReminderDetailsChange(addNote: "x"), newDue: nil))
    }

    func testReplyAndLogNameTheChangesNotTheNote() {
        let change = ReminderDetailsChange(addNote: "PIN 4417", priority: .high, toList: ReminderListRef(id: "w", title: "Work"))
        let reply = VoiceToolReply.reminderDetailsChanged("Call the bank", change: change, due: nil)
        XCTAssertEqual(reply, "changed: reminder \"Call the bank\": note added, high priority, moved to the list \"Work\". Checked in Reminders.")
        let request = ActivityRequest.describe(.changeReminder(ReminderChangeDraft(title: "Call the bank", newDue: nil, markDone: false, addNote: "PIN 4417", priority: .high, listName: "Work")), calendar: calendar)
        XCTAssertNotNil(request)
        XCTAssertFalse(request?.detail?.contains("4417") ?? true, "the note's text isn't logged")
    }
}

/// Rename, repeat and replace notes (ADR-312).
final class ReminderRenameRepeatTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    private let now = ISO8601DateFormatter().date(from: "2026-10-11T08:00:00Z")!

    private func parse(_ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: "change_reminder", parametersJSON: Data(json.utf8), now: now, calendar: calendar)
    }

    func testRenameRepeatAndNotes() {
        guard case .changeReminder(let draft) = parse(#"{"title": "Gym", "new_title": "Gym with Tom", "repeat": "weekly", "replace_notes": "bring the towel"}"#) else {
            return XCTFail("a rename with a repeat and new notes is one change")
        }
        XCTAssertEqual(draft.newTitle, "Gym with Tom")
        XCTAssertEqual(draft.repeatChange, .set(CalendarRepeat(frequency: .weekly)))
        XCTAssertEqual(draft.replaceNotes, "bring the towel")
        XCTAssertTrue(draft.changesDetails)

        guard case .changeReminder(let stop) = parse(#"{"title": "Gym", "repeat": "none", "clear_notes": true}"#) else { return XCTFail() }
        XCTAssertEqual(stop.repeatChange, .stop)
        XCTAssertEqual(stop.replaceNotes, "")
    }

    func testConflictingAsksAreRefused() {
        if case .invalid = parse(#"{"title": "Gym", "add_note": "x", "replace_notes": "y"}"#) {} else { XCTFail("add or replace, not both") }
        if case .invalid = parse(#"{"title": "Gym", "clear_notes": true, "replace_notes": "y"}"#) {} else { XCTFail("clear or replace, not both") }
        if case .invalid = parse(#"{"title": "Gym", "repeat": "fortnightly"}"#) {} else { XCTFail("unknown repeat") }
        if case .invalid = parse(#"{"title": "Gym", "repeat": "none", "repeat_until": "2026-12-31"}"#) {} else { XCTFail("until with none") }
        if case .invalid = parse(#"{"title": "Gym", "new_title": "   "}"#) {} else { XCTFail("empty title") }
    }

    func testReadBackAndNothingNew() {
        let weekly = CalendarRepeat(frequency: .weekly)
        let change = ReminderDetailsChange(newTitle: "Gym with Tom", repeatChange: .set(weekly), replaceNotes: "towel")
        let back = ReminderSnapshot(id: "1", title: "Gym with Tom", listTitle: "Home", due: nil, markerURL: nil, repeats: weekly, notes: "towel")
        XCTAssertTrue(ReminderDetails.confirms(back, notes: "towel", change: change, newDue: nil))
        XCTAssertFalse(ReminderDetails.confirms(back, notes: "old notes", change: change, newDue: nil))
        let notRenamed = ReminderSnapshot(id: "1", title: "Gym", listTitle: "Home", due: nil, markerURL: nil, repeats: weekly, notes: "towel")
        XCTAssertFalse(ReminderDetails.confirms(notRenamed, notes: "towel", change: change, newDue: nil))
        let stillRepeats = ReminderSnapshot(id: "1", title: "Gym", listTitle: "Home", due: nil, markerURL: nil, repeats: weekly)
        XCTAssertFalse(ReminderDetails.confirms(stillRepeats, notes: nil, change: ReminderDetailsChange(repeatChange: .stop), newDue: nil))
        XCTAssertTrue(ReminderDetails.changesNothing(stillRepeats, change: ReminderDetailsChange(repeatChange: .set(weekly)), newDue: nil))
        XCTAssertFalse(ReminderDetails.changesNothing(stillRepeats, change: ReminderDetailsChange(repeatChange: .stop), newDue: nil))
    }

    func testReplyAndLogNeverCarryTheNotes() {
        let change = ReminderDetailsChange(newTitle: "Gym with Tom", repeatChange: .stop, replaceNotes: "PIN 4417")
        let reply = VoiceToolReply.reminderDetailsChanged("Gym", change: change, due: nil)
        XCTAssertTrue(reply.hasPrefix("changed: reminder \"Gym\": renamed to \"Gym with Tom\", notes replaced, no longer repeats"), reply)
        XCTAssertFalse(reply.contains("4417"))
        let draft = ReminderChangeDraft(title: "Gym", newDue: nil, markDone: false, newTitle: "Gym with Tom", repeatChange: .stop, replaceNotes: "PIN 4417")
        let row = ActivityRequest.describe(.changeReminder(draft), calendar: calendar)
        XCTAssertFalse(row?.detail?.contains("4417") ?? true)
    }
}

/// An event's notes replaced or cleared (ADR-312), with Undo that puts them back.
final class EventReplaceNotesTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    func testReplacePlanAndUndo() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let event = CalendarEventSummary(id: "e1@1800000000", title: "Dentist", start: start, end: start.addingTimeInterval(3600), allDay: false)
        let draft = EventChangeDraft(title: "Dentist", currentStart: start, currentIsDayOnly: false, newStart: nil, newEnd: nil, newTitle: nil,
                                     replaceNotes: "Bring the X-ray")
        let plan = try XCTUnwrap(EventChange.plan(draft, for: event, notesBefore: "Old notes", calendar: calendar))
        XCTAssertEqual(plan.replaceNotes, "Bring the X-ray")
        XCTAssertEqual(plan.notesBefore, "Old notes")
        XCTAssertTrue(plan.changesDetails)
        let undo = EventChange.reversed(plan)
        XCTAssertEqual(undo.replaceNotes, "Old notes", "Undo puts the old notes back")
        XCTAssertEqual(undo.notesBefore, "Bring the X-ray", "only if they still are what Doddy wrote")

        let same = EventChangeDraft(title: "Dentist", currentStart: start, currentIsDayOnly: false, newStart: nil, newEnd: nil, newTitle: nil,
                                    replaceNotes: "Old notes")
        XCTAssertNil(EventChange.plan(same, for: event, notesBefore: "Old notes", calendar: calendar), "the same notes are no change")
    }

    func testToolCall() {
        let json = #"{"title": "Dentist", "start": "2027-01-15T10:00", "clear_notes": true}"#
        guard case .changeCalendarEvent(let draft) = VoiceToolRequest.parse(name: "change_calendar_event", parametersJSON: Data(json.utf8), calendar: calendar) else {
            return XCTFail("clearing the notes is a change")
        }
        XCTAssertEqual(draft.replaceNotes, "")
        let both = #"{"title": "Dentist", "start": "2027-01-15T10:00", "add_note": "a", "replace_notes": "b"}"#
        if case .invalid = VoiceToolRequest.parse(name: "change_calendar_event", parametersJSON: Data(both.utf8), calendar: calendar) {} else {
            XCTFail("add or replace, not both")
        }
    }
}
