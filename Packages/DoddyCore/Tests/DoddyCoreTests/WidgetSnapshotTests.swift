import DoddyCore
import Foundation
import XCTest

/// ADR-215. Synthetic notes only.
final class WidgetSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func record(_ text: String, source: MemorySource = .explicitText) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: source, capturedAt: now.addingTimeInterval(-3600))
    }

    private func reminder(_ memory: MemoryRecord, in minutes: Double?) -> MemoryReminder {
        if let minutes {
            return MemoryReminder(id: UUID(), memoryID: memory.id, fireAt: now.addingTimeInterval(minutes * 60), timeZoneID: "Europe/Warsaw", createdAt: now)
        }
        let place = try! ReminderPlace(name: "Home", latitude: 52.2, longitude: 21.0, radiusMeters: 200, onArrival: true)
        return MemoryReminder(id: UUID(), memoryID: memory.id, trigger: .place(place), createdAt: now)
    }

    func testPinnedNotesInPinOrderUpToThreeAndOnlyExistingOnes() throws {
        let notes = try (1...5).map { try record("Note \($0)") }
        let sample = try record("Sample", source: .sampleFixture)
        // Stored oldest pin first; shown newest pin first, as on the Memories list.
        let pins = PinnedNotes(ids: [notes[1].id, notes[2].id, notes[0].id, sample.id, UUID(), notes[4].id])
        let snapshot = WidgetSnapshot.make(memories: notes + [sample], pins: pins, reminders: [], showsNoteWords: true, now: now)
        XCTAssertEqual(snapshot.pinned.map(\.text), ["Note 5", "Note 1", "Note 3"], "deleted and sample pins skipped, max 3")
        XCTAssertEqual(PinnedNotes(ids: pins.ids).apply(to: notes).prefix(3).map(\.currentText), ["Note 5", "Note 1", "Note 3"],
                       "the same order as the Memories list")
    }

    func testUpcomingRemindersSoonestFirstAndPlacesCounted() throws {
        let a = try record("Bring the key"), b = try record("Call Adam"), c = try record("Old one"), d = try record("At home")
        let snapshot = WidgetSnapshot.make(
            memories: [a, b, c, d], pins: PinnedNotes(),
            reminders: [reminder(b, in: 120), reminder(a, in: 30), reminder(c, in: -5), reminder(d, in: nil)],
            showsNoteWords: true, now: now)
        XCTAssertEqual(snapshot.upcoming.map(\.text), ["Bring the key", "Call Adam"], "past reminders left out")
        XCTAssertEqual(snapshot.placeReminders, 1)
        XCTAssertEqual(snapshot.next(after: now)?.text, "Bring the key")
        XCTAssertEqual(snapshot.next(after: now.addingTimeInterval(31 * 60))?.text, "Call Adam", "moves on as times pass")
        XCTAssertNil(snapshot.next(after: now.addingTimeInterval(121 * 60)))
        XCTAssertEqual(snapshot.redrawTimes(after: now).count, 2)
    }

    func testNoteWordsOffMeansNoWordsInTheFileAtAll() throws {
        let a = try record("Gate code 4821")
        let snapshot = WidgetSnapshot.make(memories: [a], pins: PinnedNotes(ids: [a.id]), reminders: [reminder(a, in: 10)],
                                           showsNoteWords: false, now: now)
        XCTAssertNil(snapshot.pinned[0].text)
        XCTAssertNil(snapshot.upcoming[0].text)
        let json = String(decoding: try snapshot.encoded(), as: UTF8.self)
        XCTAssertFalse(json.contains("4821"), "not just hidden in the view: never written")
    }

    func testLongAndMultilineNotesAreClippedForTheWidgetOnly() throws {
        let long = try record("Parcel locker\n\nCode 1234\n" + String(repeating: "x", count: 300))
        let snapshot = WidgetSnapshot.make(memories: [long], pins: PinnedNotes(ids: [long.id]), reminders: [], showsNoteWords: true, now: now)
        let text = try XCTUnwrap(snapshot.pinned[0].text)
        XCTAssertTrue(text.hasPrefix("Parcel locker · Code 1234 · xxx"))
        XCTAssertEqual(text.count, WidgetSnapshot.maxTextLength)
        XCTAssertTrue(text.hasSuffix("…"))
    }

    func testRoundTripAndOtherVersionsAreRefused() throws {
        let a = try record("Bring the key")
        let snapshot = WidgetSnapshot.make(memories: [a], pins: PinnedNotes(ids: [a.id]), reminders: [reminder(a, in: 10)], showsNoteWords: true, now: now)
        XCTAssertEqual(WidgetSnapshot.decode(try snapshot.encoded()), snapshot)
        let future = WidgetSnapshot(version: 99, generatedAt: now, showsNoteWords: true, pinned: [], upcoming: [], placeReminders: 0)
        XCTAssertNil(WidgetSnapshot.decode(try future.encoded()))
        XCTAssertNil(WidgetSnapshot.decode(Data("not json".utf8)))
    }

    func testEverythingDeletedMeansAnEmptySnapshot() {
        let snapshot = WidgetSnapshot.make(memories: [], pins: PinnedNotes(ids: [UUID()]), reminders: [], showsNoteWords: true, now: now)
        XCTAssertEqual(snapshot.pinned, [])
        XCTAssertEqual(snapshot.upcoming, [])
    }

    func testNoteLinks() throws {
        let id = UUID()
        let url = NoteLink.url(for: id)
        XCTAssertEqual(url.absoluteString, "doddy://note/\(id.uuidString.lowercased())")
        XCTAssertEqual(NoteLink.id(from: url), id)
        XCTAssertNil(NoteLink.id(from: URL(string: "doddy://note/not-a-uuid")!))
        XCTAssertNil(NoteLink.id(from: URL(string: "https://note/\(id.uuidString)")!))
        XCTAssertNil(NoteLink.id(from: URL(string: "doddy://memories")!))
        XCTAssertNil(DeepLink(url: url), "the place links don't claim note links")
    }
}
