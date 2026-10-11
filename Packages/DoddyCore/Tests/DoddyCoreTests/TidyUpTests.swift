import DoddyCore
import XCTest

/// Weekly tidy-up (ADR-228): what is suggested, and what never is.
final class TidyUpTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(_ text: String, daysAgo: Double, category: MemoryCategory = .other, source: MemorySource = .explicitText) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: source, category: category, capturedAt: now.addingTimeInterval(-daysAgo * 86_400))
    }

    func testSuggestionsFindCopiesForgottenRemindersAndFinishedLists() throws {
        let first = try note("Gate code: 4821.", daysAgo: 30)
        let copy = try note("gate code 4821", daysAgo: 2)
        let other = try note("Gate code 4822", daysAgo: 1)
        let sample = try note("gate code 4821", daysAgo: 1, source: .sampleFixture)
        let doneRecord = try note("Packing", daysAgo: 5, category: .list)
        let packing = DoddyList(record: doneRecord, items: [
            ListItem(id: UUID(), listID: doneRecord.id, text: "socks", source: .voice, addedAt: now, doneAt: now, position: 0),
        ])
        let emptyRecord = try note("Ideas", daysAgo: 5, category: .list)
        let empty = DoddyList(record: emptyRecord, items: [])
        let old = MemoryReminder(id: UUID(), memoryID: other.id, fireAt: now.addingTimeInterval(-3 * 86_400), timeZoneID: "UTC", createdAt: now)
        let recent = MemoryReminder(id: UUID(), memoryID: first.id, fireAt: now.addingTimeInterval(-3600), timeZoneID: "UTC", createdAt: now)
        let gone = MemoryReminder(id: UUID(), memoryID: UUID(), fireAt: now.addingTimeInterval(-3 * 86_400), timeZoneID: "UTC", createdAt: now)
        let weekly = MemoryReminder(
            id: UUID(), memoryID: first.id, trigger: .time(fireAt: now.addingTimeInterval(-30 * 86_400), timeZoneID: "UTC"),
            createdAt: now, repeats: .weekly)

        let tidy = TidyUp.suggestions(
            memories: [first, copy, other, sample], lists: [packing, empty], reminders: [old, recent, gone, weekly], now: now)

        XCTAssertEqual(tidy.duplicates.count, 1)
        XCTAssertEqual(tidy.duplicates.first?.keep.id, first.id, "the first saved copy is the one kept")
        XCTAssertEqual(tidy.duplicates.first?.copies.map(\.id), [copy.id], "samples and different numbers aren't copies")
        XCTAssertEqual(tidy.passedReminders.map(\.id), [old.id], "not recent, not repeating, not for a deleted note")
        XCTAssertEqual(tidy.finishedLists.map(\.id), [packing.id], "an empty list isn't finished")
        XCTAssertEqual(tidy.count, 3)
    }

    func testNotesWithAPhotoOrVoiceMemoAreNeverCopies() throws {
        let first = try note("Parking spot", daysAgo: 3)
        let photo = try note("Parking spot", daysAgo: 2)
        let memo = try note("parking spot", daysAgo: 1)
        let memories = [first, photo, memo]
        XCTAssertEqual(TidyUp.suggestions(memories: memories, lists: [], reminders: [], now: now).duplicates.first?.copies.count, 2)
        let tidy = TidyUp.suggestions(memories: memories, lists: [], reminders: [], now: now, withAttachments: [photo.id, memo.id])
        XCTAssertTrue(tidy.duplicates.isEmpty)
        let kept = TidyUp.suggestions(memories: memories, lists: [], reminders: [], now: now, withAttachments: [first.id])
        XCTAssertEqual(kept.duplicates.first?.keep.id, photo.id, "the note with an attachment is left out of the group")
        XCTAssertEqual(kept.duplicates.first?.copies.map(\.id), [memo.id])
    }

    func testNothingToTidy() throws {
        let tidy = TidyUp.suggestions(memories: [try note("one", daysAgo: 1)], lists: [], reminders: [], now: now)
        XCTAssertTrue(tidy.isEmpty)
    }

    func testOffByDefaultAndNeutralWords() {
        let defaults = UserDefaults(suiteName: "TidyUpTests-\(UUID().uuidString)")!
        XCTAssertEqual(TidyUpSettings.stored(defaults), TidyUpSettings())
        XCTAssertFalse(TidyUpSettings.stored(defaults).isOn)
        TidyUpSettings(isOn: true, weekday: 9, hour: -1).store(defaults)
        XCTAssertEqual(TidyUpSettings.stored(defaults), TidyUpSettings(isOn: true, weekday: 7, hour: 0))
        XCTAssertEqual(TidyUp.body(.english), "A few minutes to tidy up?")
        XCTAssertEqual(TidyUp.body(.polish), "Kilka minut na porządki?")
    }
}
