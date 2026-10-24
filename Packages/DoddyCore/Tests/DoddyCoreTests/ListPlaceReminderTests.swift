import XCTest
@testable import DoddyCore

/// ADR-621: a list's reminder at a place says how many things are left on the list, and offers
/// "Open list". The place's name is never in the notification (ReminderPlace).
final class ListPlaceReminderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_000_000)

    private func placeReminder() -> MemoryReminder {
        MemoryReminder(
            id: UUID(), memoryID: UUID(),
            trigger: .place(try! ReminderPlace(name: "Biedronka Mokotów", latitude: 52.2, longitude: 21.0, radiusMeters: 200, onArrival: true)),
            createdAt: now)
    }

    func testThePolishCountReadsNaturally() {
        XCTAssertEqual(NoteReminderCopy.itemsOnList(0, .polish), "wszystko odhaczone")
        XCTAssertEqual(NoteReminderCopy.itemsOnList(1, .polish), "1 rzecz na liście")
        XCTAssertEqual(NoteReminderCopy.itemsOnList(2, .polish), "2 rzeczy na liście")
        XCTAssertEqual(NoteReminderCopy.itemsOnList(12, .polish), "12 rzeczy na liście")
        XCTAssertEqual(NoteReminderCopy.itemsOnList(0, .english), "everything is ticked off")
        XCTAssertEqual(NoteReminderCopy.itemsOnList(1, .english), "1 item on the list")
        XCTAssertEqual(NoteReminderCopy.itemsOnList(4, .english), "4 items on the list")
    }

    func testTheListNameIsInTheBodyOnlyWhenTheUserAllowsIt() {
        XCTAssertEqual(NoteReminderCopy.listPlaceBody(listName: nil, openItems: 4, language: .polish), "4 rzeczy na liście")
        XCTAssertEqual(NoteReminderCopy.listPlaceBody(listName: "Zakupy", openItems: 4, language: .polish), "Zakupy · 4 rzeczy na liście")
        XCTAssertEqual(NoteReminderCopy.listPlaceBody(listName: "  ", openItems: 1, language: .english), "1 item on the list")
        XCTAssertNil(NoteReminderCopy.listPlaceBody(listName: "Zakupy", openItems: nil, language: .polish), "an unknown count keeps the plain text")
        let long = NoteReminderCopy.listPlaceBody(listName: String(repeating: "a", count: 200), openItems: 3, language: .english)!
        XCTAssertLessThan(long.count, 120)
    }

    func testAListAtAPlaceGetsTheCountAndOpenList() throws {
        let reminder = placeReminder()
        let asked = NoteReminderNotification.requests(
            for: reminder, noteText: "Zakupy", showNoteText: true, at: now, language: .polish, isList: true, openItems: 4)
        let request = try XCTUnwrap(asked.first)
        XCTAssertEqual(asked.count, 1)
        XCTAssertEqual(request.category, .placeList)
        XCTAssertEqual(request.body, "Zakupy · 4 rzeczy na liście")
        XCTAssertEqual(request.title, "Przypomnienie")
        XCTAssertFalse(request.title.contains("Biedronka") || request.body.contains("Biedronka"), "the place's name is never in the notification")
        // The private default: the count, never the list's name.
        let hidden = try XCTUnwrap(NoteReminderNotification.requests(
            for: reminder, noteText: "Zakupy", showNoteText: false, at: now, language: .polish, isList: true, openItems: 4).first)
        XCTAssertEqual(hidden.body, "4 rzeczy na liście")
        XCTAssertFalse(hidden.body.contains("Zakupy"))
    }

    func testWithoutACountAListKeepsItsPlainPrivateText() throws {
        let request = try XCTUnwrap(NoteReminderNotification.requests(
            for: placeReminder(), noteText: "Zakupy", showNoteText: false, at: now, language: .polish, isList: true).first)
        XCTAssertEqual(request.body, NoteReminderCopy.privateListBody(.polish))
        XCTAssertEqual(request.category, .placeList)
    }

    func testANoteAtAPlaceAndAListAtATimeAreUnchanged() throws {
        let note = try XCTUnwrap(NoteReminderNotification.requests(
            for: placeReminder(), noteText: "Kod 4471", showNoteText: true, at: now, language: .polish, isList: false).first)
        XCTAssertEqual(note.category, .place)
        XCTAssertEqual(note.body, "Kod 4471")
        let timed = MemoryReminder(id: UUID(), memoryID: UUID(), fireAt: now.addingTimeInterval(3_600), timeZoneID: "Europe/Warsaw", createdAt: now)
        let list = try XCTUnwrap(NoteReminderNotification.requests(
            for: timed, noteText: "Zakupy", showNoteText: true, at: now, language: .polish, isList: true, openItems: 4).first)
        XCTAssertEqual(list.category, .once)
        XCTAssertEqual(list.body, "Zakupy")
        XCTAssertEqual(NoteReminderCopy.action(.openList, .polish), "Otwórz listę")
    }
}
