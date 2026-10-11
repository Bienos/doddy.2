import DoddyCore
import XCTest

/// Widgets (ADR-219): what the shared snapshot holds, and how a widget tick is checked.
final class WidgetSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(_ text: String, category: MemoryCategory = .other, at offset: TimeInterval = 0) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: .explicitText, category: category,
                         capturedAt: now.addingTimeInterval(offset))
    }

    private func item(_ text: String, list: UUID, done: Bool = false, position: Int) -> ListItem {
        ListItem(id: UUID(), listID: list, text: text, source: .typed, addedAt: now,
                 doneAt: done ? now : nil, position: position)
    }

    func testPinnedNotesRemindersAndListsAreShortenedAndOrdered() throws {
        let wifi = try note("Wi-Fi: Doddy5G\nPassword: tin-kettle-42")
        let parking = try note("Parking level -2, C 14")
        let dentist = try note("Dentist: bring the referral")
        let shoppingRecord = try note("Shopping", category: .list, at: 10)
        let olderRecord = try note("Trip", category: .list, at: -10)
        let shopping = DoddyList(record: shoppingRecord, items: [
            item("milk", list: shoppingRecord.id, done: true, position: 0),
            item("eggs", list: shoppingRecord.id, position: 1),
        ])
        let trip = DoddyList(record: olderRecord, items: [])
        let soon = MemoryReminder(id: UUID(), memoryID: dentist.id, fireAt: now.addingTimeInterval(3600), timeZoneID: "Europe/Warsaw", createdAt: now)
        let past = MemoryReminder(id: UUID(), memoryID: parking.id, fireAt: now.addingTimeInterval(-60), timeZoneID: "Europe/Warsaw", createdAt: now)
        let gone = MemoryReminder(id: UUID(), memoryID: UUID(), fireAt: now.addingTimeInterval(60), timeZoneID: "UTC", createdAt: now)

        let snapshot = WidgetSnapshot.make(
            memories: [wifi, parking, dentist], lists: [trip, shopping],
            pinned: PinnedNotes(ids: [parking.id, UUID(), wifi.id]), reminders: [past, gone, soon],
            showReminderText: false, isOn: true, now: now)

        XCTAssertEqual(snapshot.pinned.map(\.text), ["Parking level -2, C 14", "Wi-Fi: Doddy5G"], "pin order, first line, deleted pins skipped")
        XCTAssertEqual(snapshot.reminders.count, 1, "past reminders and reminders of deleted notes are left out")
        XCTAssertEqual(snapshot.reminders.first?.memoryID, dentist.id)
        XCTAssertNil(snapshot.reminders.first?.text, "note text stays out when notifications hide it")
        XCTAssertEqual(snapshot.lists.map(\.name), ["Shopping", "Trip"], "newest list first")
        XCTAssertEqual(snapshot.lists.first?.items.map(\.text), ["eggs", "milk"], "open items first, then ticked")
        XCTAssertEqual(snapshot.lists.first?.openCount, 1)
        XCTAssertEqual(snapshot.lists.first?.doneCount, 1)
        XCTAssertTrue(snapshot.reminders(after: now.addingTimeInterval(7200)).isEmpty)

        let shown = WidgetSnapshot.make(
            memories: [dentist], lists: [], pinned: PinnedNotes(), reminders: [soon],
            showReminderText: true, isOn: true, now: now)
        XCTAssertEqual(shown.reminders.first?.text, "Dentist: bring the referral")
    }

    func testOffLeavesNothingOfTheUsersInTheSharedFile() throws {
        let wifi = try note("Wi-Fi password")
        let snapshot = WidgetSnapshot.make(
            memories: [wifi], lists: [], pinned: PinnedNotes(ids: [wifi.id]), reminders: [],
            showReminderText: true, isOn: false, now: now)
        XCTAssertFalse(snapshot.isOn)
        XCTAssertTrue(snapshot.pinned.isEmpty && snapshot.reminders.isEmpty && snapshot.lists.isEmpty)
        let json = String(decoding: try snapshot.encoded(), as: UTF8.self)
        XCTAssertFalse(json.contains("Wi-Fi"))
    }

    func testParkingGivesTimeAndWordsNeverThePosition() throws {
        let spot = ParkingSpot(latitude: 52.229_676, longitude: 21.012_229, accuracyMeters: 8, savedAt: now, note: "level 2, row C")
        let snapshot = WidgetSnapshot.make(memories: [], lists: [], pinned: PinnedNotes(ids: []), reminders: [],
                                           showReminderText: true, isOn: true, now: now, parking: spot)
        XCTAssertEqual(snapshot.parking, WidgetSnapshot.Parked(savedAt: now, note: "level 2, row C"))
        let json = String(decoding: try snapshot.encoded(), as: UTF8.self)
        XCTAssertFalse(json.contains("52.2") || json.contains("21.01"), "the position stays in the app")
        XCTAssertEqual(WidgetSnapshot.decoded(try snapshot.encoded()), snapshot)
        // Switched off: no parking either.
        XCTAssertNil(WidgetSnapshot.make(memories: [], lists: [], pinned: PinnedNotes(ids: []), reminders: [],
                                         showReminderText: true, isOn: false, now: now, parking: spot).parking)
        // A snapshot written before parking existed still reads.
        let old = #"{"isOn":true,"lists":[],"pinned":[],"reminders":[],"version":1,"writtenAt":1800000000000}"#
        XCTAssertNil(try XCTUnwrap(WidgetSnapshot.decoded(Data(old.utf8))).parking)
    }

    func testShortenedCutsOnAWord() {
        let long = Array(repeating: "word", count: 60).joined(separator: " ")
        let short = WidgetSnapshot.shortened(long)
        XCTAssertLessThanOrEqual(short.count, WidgetSnapshot.maxTextLength)
        XCTAssertTrue(short.hasSuffix("word…"))
        XCTAssertEqual(WidgetSnapshot.shortened("  Hi \n second"), "Hi")
    }

    /// ADR-331: "Hide character artwork" reaches widgets and the watch, even with content off,
    /// and a snapshot written without it still reads (pictures shown).
    func testHideCharacterArtTravelsAndOldSnapshotsStillRead() throws {
        let shown = WidgetSnapshot.make(memories: [], lists: [], pinned: PinnedNotes(ids: []), reminders: [],
                                        showReminderText: false, isOn: true, now: now)
        XCTAssertFalse(shown.hidesPictures)
        XCTAssertFalse(String(decoding: try shown.encoded(), as: UTF8.self).contains("hidesDoddy"))
        let hidden = WidgetSnapshot.make(memories: [], lists: [], pinned: PinnedNotes(ids: []), reminders: [],
                                         showReminderText: false, isOn: true, now: now, hidesDoddy: true)
        XCTAssertEqual(WidgetSnapshot.decoded(try hidden.encoded())?.hidesPictures, true)
        let off = WidgetSnapshot.make(memories: [], lists: [], pinned: PinnedNotes(ids: []), reminders: [],
                                      showReminderText: false, isOn: false, now: now, hidesDoddy: true)
        XCTAssertTrue(off.hidesPictures)
        let old = Data(#"{"version":\#(WidgetSnapshot.currentVersion),"writtenAt":0,"isOn":true,"pinned":[],"reminders":[],"lists":[]}"#.utf8)
        XCTAssertEqual(WidgetSnapshot.decoded(old)?.hidesPictures, false)
    }

    func testRoundTripAndRefusesOtherVersionsOrDamage() throws {
        let snapshot = WidgetSnapshot(writtenAt: now, isOn: true, pinned: [.init(id: UUID(), text: "Kod: 4512")], reminders: [], lists: [])
        XCTAssertEqual(WidgetSnapshot.decoded(try snapshot.encoded()), snapshot)
        let future = WidgetSnapshot(version: 99, writtenAt: now, isOn: true, pinned: [], reminders: [], lists: [])
        XCTAssertNil(WidgetSnapshot.decoded(try future.encoded()))
        XCTAssertNil(WidgetSnapshot.decoded(Data("{".utf8)))
    }

    func testWidgetLinkOpensOneNoteOnly() {
        let id = UUID()
        XCTAssertEqual(WidgetLink.memoryID(from: WidgetLink.open(id)), id)
        XCTAssertNil(WidgetLink.memoryID(from: URL(string: "doddy://open/not-a-uuid")!))
        XCTAssertNil(WidgetLink.memoryID(from: URL(string: "doddy://delete/\(id.uuidString)")!))
        XCTAssertNil(WidgetLink.memoryID(from: URL(string: "https://open/\(id.uuidString)")!))
        XCTAssertNil(DeepLink(url: WidgetLink.open(id)), "home/memories/settings links are unchanged")
    }

    func testATickFromAStaleWidgetChangesNothing() {
        let list = UUID()
        let eggs = item("eggs", list: list, position: 0)
        XCTAssertEqual(WidgetTick.wanted(item: eggs, shownDone: false), true)
        XCTAssertNil(WidgetTick.wanted(item: eggs, shownDone: true), "the app already changed it")
        XCTAssertNil(WidgetTick.wanted(item: nil, shownDone: false))
        let ticked = ListItem(id: eggs.id, listID: list, text: "eggs", source: .typed, addedAt: now, doneAt: now, position: 0)
        XCTAssertEqual(WidgetTick.outcome(after: [ticked], itemID: eggs.id, wantedDone: true), .ticked)
        XCTAssertEqual(WidgetTick.outcome(after: [eggs], itemID: eggs.id, wantedDone: true), .failed, "not read back as ticked")
        XCTAssertEqual(WidgetTick.outcome(after: [], itemID: eggs.id, wantedDone: false), .failed)
    }
}
