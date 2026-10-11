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
