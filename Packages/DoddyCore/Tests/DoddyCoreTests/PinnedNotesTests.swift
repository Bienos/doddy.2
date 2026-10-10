import DoddyCore
import Foundation
import XCTest

final class PinnedNotesTests: XCTestCase {
    private func note(_ text: String) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: .explicitText, capturedAt: Date())
    }

    func testPinnedNotesComeFirstNewestPinOnTopAndTheRestKeepTheirOrder() throws {
        let a = try note("a"), b = try note("b"), c = try note("c"), d = try note("d")
        var pins = PinnedNotes()
        XCTAssertEqual(pins.toggle(c.id, existing: [a, b, c, d]), .pinned)
        XCTAssertEqual(pins.toggle(a.id, existing: [a, b, c, d]), .pinned)
        XCTAssertEqual(pins.apply(to: [a, b, c, d]), [a, c, b, d])
        XCTAssertEqual(pins.toggle(a.id, existing: [a, b, c, d]), .unpinned)
        XCTAssertEqual(pins.apply(to: [a, b, c, d]), [c, a, b, d])
        XCTAssertEqual(PinnedNotes().apply(to: [a, b]), [a, b])
    }

    func testDeletedNotesAreIgnoredAndDontUseUpTheLimit() throws {
        let gone = try note("gone"), kept = try note("kept")
        var pins = PinnedNotes(ids: [gone.id])
        XCTAssertEqual(pins.apply(to: [kept]), [kept], "a pin for a missing note shows nothing")
        pins.toggle(kept.id, existing: [kept])
        XCTAssertEqual(pins.ids, [kept.id], "the stale pin was dropped when pinning")
    }

    func testAtMostTenPinsAndTheElevenAskedForIsRefused() throws {
        let notes = try (0..<11).map { try note("n\($0)") }
        var pins = PinnedNotes()
        for n in notes.prefix(10) { XCTAssertEqual(pins.toggle(n.id, existing: notes), .pinned) }
        XCTAssertTrue(pins.isFull)
        XCTAssertEqual(pins.toggle(notes[10].id, existing: notes), .full)
        XCTAssertFalse(pins.isPinned(notes[10].id))
        XCTAssertEqual(pins.toggle(notes[0].id, existing: notes), .unpinned, "unpinning still works when full")
    }

    func testStoredValueRoundTripsAndDamageMeansNoPins() throws {
        let a = UUID(), b = UUID()
        let pins = PinnedNotes(ids: [a, b, a])
        XCTAssertEqual(pins.ids, [a, b], "no repeats")
        XCTAssertEqual(PinnedNotes(stored: pins.stored), pins)
        XCTAssertEqual(PinnedNotes(stored: "not json"), PinnedNotes())
        XCTAssertEqual(PinnedNotes(stored: nil), PinnedNotes())
        XCTAssertEqual(PinnedNotes(stored: "[\"nope\", \"\(a.uuidString)\"]").ids, [a], "a bad entry is skipped")
    }
}
