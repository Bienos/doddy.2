import Foundation
import XCTest
@testable import DoddyCore

/// What "What Doddy did" keeps of notes and lists over time (review C2, DODDY Brain audit §5 #7,
/// ADR-446): Undo's copy of a note or of list items lasts only as long as Undo is offered, goes
/// when the note or list is deleted, and "Delete all memories" takes the Notes rows with it.
final class ActivityRetentionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let secret = "Locker code 4821"

    private func savedNote(_ id: UUID = UUID(), text: String? = nil, hoursAgo: Double) -> ActivityEntry {
        ActivityEntry(
            at: now.addingTimeInterval(-hoursAgo * 3_600), app: .memories, title: "Save a note", detail: nil,
            outcome: .done, undo: .savedNote(id: id, text: text ?? secret), tool: VoiceToolName.saveMemory)
    }

    private func listAdd(_ listID: UUID, hoursAgo: Double) -> ActivityEntry {
        let item = ListItem(id: UUID(), listID: listID, text: "oat milk", source: .voice, addedAt: now, doneAt: nil, position: 0)
        return ActivityEntry(
            at: now.addingTimeInterval(-hoursAgo * 3_600), app: .memories, title: "Add to list", detail: "1 item",
            outcome: .done, undo: .listAdded(listID: listID, list: "Shopping", items: [item]))
    }

    private func calendarAdd(hoursAgo: Double) -> ActivityEntry {
        let start = now.addingTimeInterval(86_400)
        let event = CalendarEventSummary(id: "ev1", title: "Dentist", start: start, end: start.addingTimeInterval(3_600), allDay: false)
        return ActivityEntry(
            at: now.addingTimeInterval(-hoursAgo * 3_600), app: .calendar, title: "Add event", detail: "“Dentist”",
            outcome: .done, undo: .addedEvent(eventID: "ev1", event: event))
    }

    private func encoded(_ entries: [ActivityEntry]) throws -> String {
        String(decoding: try JSONEncoder().encode(entries), as: UTF8.self)
    }

    // MARK: Undo's copy lasts as long as Undo

    func testUndoDataGoesWhenUndoIsNoLongerOffered() throws {
        let fresh = savedNote(hoursAgo: 23)
        let old = savedNote(text: "Old secret 1234", hoursAgo: 25)
        let pruned = ActivityLog.pruned([fresh, old], now: now)
        XCTAssertNotNil(pruned.first { $0.id == fresh.id }?.undo, "still offered for a day")
        XCTAssertTrue(pruned.first { $0.id == fresh.id }!.canUndo(now: now))
        let kept = try XCTUnwrap(pruned.first { $0.id == old.id })
        XCTAssertNil(kept.undo)
        // The row itself stays, as it was.
        XCTAssertEqual(kept.outcome, .done)
        XCTAssertEqual(kept.title, "Save a note")
        XCTAssertEqual(kept.tool, VoiceToolName.saveMemory)
        // And the note's words are no longer in what is saved to disk.
        XCTAssertFalse(try encoded(pruned).contains("Old secret 1234"))
        XCTAssertTrue(try encoded(pruned).contains(secret), "the fresh one keeps it while Undo is offered")
    }

    func testAnUndoResultStaysAfterItsDataGoes() {
        var used = savedNote(hoursAgo: 30)
        used = ActivityLog.undid(used, result: .undone, at: now.addingTimeInterval(-29 * 3_600))
        let kept = ActivityLog.pruned([used], now: now)[0]
        XCTAssertNil(kept.undo)
        XCTAssertNotNil(kept.undoState)
        XCTAssertEqual(kept.note, used.note)
    }

    func testAppendingPrunesTheOldUndoDataToo() throws {
        // The app prunes on every new entry and saves, so the file loses it then.
        let old = listAdd(UUID(), hoursAgo: 48)
        let entries = ActivityLog.appending(calendarAdd(hoursAgo: 0), to: [old], now: now)
        XCTAssertNil(entries.first { $0.id == old.id }?.undo)
        XCTAssertFalse(try encoded(entries).contains("oat milk"))
    }

    // MARK: Deleting a note or a list

    func testDeletingANoteDropsOnlyItsUndoData() throws {
        let noteID = UUID(), otherID = UUID(), listID = UUID()
        let mine = savedNote(noteID, hoursAgo: 1)
        let other = savedNote(otherID, text: "Keep me", hoursAgo: 1)
        let list = listAdd(listID, hoursAgo: 1)
        let event = calendarAdd(hoursAgo: 1)
        let after = ActivityLog.forgetting(memoryID: noteID, in: [mine, other, list, event])
        XCTAssertEqual(after.count, 4, "rows stay")
        XCTAssertNil(after[0].undo)
        XCTAssertFalse(try encoded(after).contains(secret))
        XCTAssertNotNil(after[1].undo)
        XCTAssertNotNil(after[2].undo)
        XCTAssertNotNil(after[3].undo)
        // A deleted list the same way: its items go from Undo's copy.
        let afterList = ActivityLog.forgetting(memoryID: listID, in: after)
        XCTAssertNil(afterList[2].undo)
        XCTAssertFalse(try encoded(afterList).contains("oat milk"))
    }

    // MARK: Delete all memories

    func testDeleteAllTakesTheNotesRowsAndLeavesOtherApps() throws {
        let entries = [savedNote(hoursAgo: 2), listAdd(UUID(), hoursAgo: 2), calendarAdd(hoursAgo: 2)]
        let after = ActivityLog.forgettingNotes(entries)
        XCTAssertEqual(after.map(\.app), [.calendar])
        XCTAssertNotNil(after[0].undo, "a Calendar change can still be undone")
        XCTAssertFalse(try encoded(after).contains(secret))
        XCTAssertFalse(try encoded(after).contains("oat milk"))
    }

    func testMemoryIDNamesOnlyNotesAndLists() {
        let id = UUID()
        XCTAssertEqual(ActivityUndo.savedNote(id: id, text: "x").memoryID, id)
        XCTAssertEqual(ActivityUndo.listTicked(listID: id, list: "L", items: []).memoryID, id)
        XCTAssertEqual(ActivityUndo.listRemoved(listID: id, list: "L", items: []).memoryID, id)
        XCTAssertNil(calendarAdd(hoursAgo: 0).undo?.memoryID)
        XCTAssertNil(ActivityUndo.addedReminder(key: "k", title: "t", due: nil).memoryID)
    }
}
