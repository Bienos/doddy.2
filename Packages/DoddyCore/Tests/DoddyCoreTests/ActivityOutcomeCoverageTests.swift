import XCTest
@testable import DoddyCore

/// Every result the app sends the agent lands on an honest row in "What Doddy did" (ADR-269):
/// a change that happened is "Done", one that didn't is "Didn't happen", and only a result
/// Doddy really can't confirm is "Not sure". Built from the app's own reply builders, so a new
/// wording that the log doesn't know fails here instead of showing "Not sure" for real work.
final class ActivityOutcomeCoverageTests: XCTestCase {
    private let list = UUID()

    private func item(_ text: String, done: Bool = false) -> ListItem {
        ListItem(id: UUID(), listID: list, text: text, source: .voice, addedAt: Date(timeIntervalSince1970: 0),
                 doneAt: done ? Date(timeIntervalSince1970: 1) : nil, position: 0)
    }

    private func outcome(_ reply: String) -> ActivityOutcome {
        ActivityEntry.outcome(of: reply, isLookup: false).0
    }

    func testListChangesAreDoneWhenTheyHappenedAndNotDoneWhenNothingChanged() throws {
        let added = ListAddResult(added: [item("milk")], alreadyThere: ["eggs"], tooLong: [], noRoom: [])
        XCTAssertEqual(outcome(VoiceToolReply.listAdded(added, list: "Shopping")), .done)

        let nothingNew = ListAddResult(added: [], alreadyThere: ["eggs"], tooLong: [], noRoom: [])
        XCTAssertEqual(outcome(VoiceToolReply.listAdded(nothingNew, list: "Shopping")), .alreadyThere)
        let full = ListAddResult(added: [], alreadyThere: [], tooLong: [], noRoom: ["bread"])
        XCTAssertEqual(outcome(VoiceToolReply.listAdded(full, list: "Shopping")), .notDone)

        let ticked = VoiceToolReply.listChanged(verb: "ticked", changed: [item("milk", done: true)], list: "Shopping", notFound: ["tea"], ambiguous: [])
        XCTAssertEqual(outcome(ticked), .done)
        let removed = VoiceToolReply.listChanged(verb: "removed", changed: [item("milk")], list: "Shopping", notFound: [], ambiguous: [])
        XCTAssertEqual(outcome(removed), .done)
        let none = VoiceToolReply.listChanged(verb: "ticked", changed: [], list: "Shopping", notFound: ["tea"], ambiguous: [])
        XCTAssertEqual(outcome(none), .notDone)

        let record = try MemoryRecord(id: list, rawText: "Trip", source: .explicitVoice, category: .list, capturedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(outcome(VoiceToolReply.listCreated(DoddyList(record: record, items: [item("passport")]))), .done)
        XCTAssertEqual(outcome(VoiceToolReply.listNameTaken("Trip")), .notDone)
    }

    func testEveryOtherChangeDoddyMakesIsDoneWhenItsReplySaysSo() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 9))!
        let event = CalendarEventDraft(title: "Dentist", start: start, end: start.addingTimeInterval(3_600), allDay: false, location: nil, notes: nil)
        let note = try MemoryRecord(id: UUID(), rawText: "Keys in the tin", source: .explicitVoice, category: .other, capturedAt: start)
        let receipt = ReminderReceipt(title: "Buy milk", listTitle: "Reminders", due: nil)
        let summary = CalendarEventSummary(title: "Dentist", start: start, end: start.addingTimeInterval(3_600), allDay: false)

        let done = [
            VoiceToolReply.eventAdded(event, calendar: calendar),
            VoiceToolReply.reminder(.added(receipt)),
            VoiceToolReply.timerAdded(TimerDraft(seconds: 600, label: "Eggs"), endsAt: start, calendar: calendar),
            VoiceToolReply.saved(note),
            VoiceToolReply.eventChanged(summary, calendar: calendar),
            VoiceToolReply.reminderChanged("Buy milk", due: nil),
            VoiceToolReply.reminderCompleted("Buy milk"),
            // The default line's deletes and alarms (ADR-259, ADR-260).
            VoiceToolReply.eventDeleted(summary, calendar: calendar),
            VoiceToolReply.reminderDeleted("Buy milk"),
            VoiceToolReply.alarmSet(AlarmDraft(first: ReminderDue(year: 2026, month: 10, day: 12, hour: 7, minute: 0, timeZoneID: "Europe/Warsaw"), repeats: nil, label: "Gym")),
        ]
        for reply in done {
            XCTAssertEqual(outcome(reply), .done, reply)
        }
        // Only what really can't be confirmed is "Not sure".
        for reply in [VoiceToolReply.addUnconfirmed, VoiceToolReply.reminder(.unknown), VoiceToolReply.eventChangeUnconfirmed,
                      VoiceToolReply.deleteUnconfirmed, VoiceToolReply.alarmUnconfirmed] {
            XCTAssertEqual(outcome(reply), .notSure, reply)
        }
    }

    func testAListThatSaysAnItemIsAlreadyThereIsNotMistakenForOtherKinds() {
        // "added to" must not catch a reply that starts differently but mentions it.
        XCTAssertEqual(outcome("failed: couldn't save. Nothing was added to the list."), .notDone)
        XCTAssertEqual(outcome("something added to \"Shopping\""), .notSure)
    }
}
