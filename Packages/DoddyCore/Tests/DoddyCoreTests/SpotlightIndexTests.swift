import XCTest
@testable import DoddyCore

/// Notes and lists in iPhone search (ADR-330).
final class SpotlightIndexTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(_ text: String, category: MemoryCategory = .other) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: .explicitText, category: category, capturedAt: now)
    }

    func testOffMeansNothingAndPrivateNotesAreNeverIndexed() throws {
        let gate = try note("Gate code 4512 #home")
        let secret = try note("Bank PIN hint")
        let shopRecord = try note("Shopping", category: .list)
        let shop = DoddyList(record: shopRecord, items: [
            ListItem(id: UUID(), listID: shopRecord.id, text: "Milk", source: .typed, addedAt: now, doneAt: nil, position: 0),
            ListItem(id: UUID(), listID: shopRecord.id, text: "Eggs", source: .typed, addedAt: now, doneAt: now, position: 1),
        ])
        let privateNotes = PrivateNotes(ids: [secret.id])
        XCTAssertEqual(SpotlightIndex.entries(memories: [gate, secret, shopRecord], lists: [shop], privateNotes: privateNotes, isOn: false), [])
        let entries = SpotlightIndex.entries(memories: [gate, secret, shopRecord], lists: [shop], privateNotes: privateNotes, isOn: true)
        XCTAssertEqual(entries.map(\.id), [gate.id, shop.id])
        XCTAssertEqual(entries[0].keywords, ["home"])
        XCTAssertEqual(entries[1].kind, .list)
        XCTAssertEqual(entries[1].content, "Milk", "ticked items aren't searched")
    }

    func testSignatureChangesOnlyWithContent() throws {
        let gate = try note("Gate code 4512")
        let a = SpotlightIndex.entries(memories: [gate], lists: [], privateNotes: PrivateNotes(), isOn: true)
        XCTAssertEqual(SpotlightIndex.signature(a), SpotlightIndex.signature(a))
        let edited = try MemoryRecord(id: gate.id, rawText: "Gate code 4513", source: .explicitText, category: .other, capturedAt: now)
        let b = SpotlightIndex.entries(memories: [edited], lists: [], privateNotes: PrivateNotes(), isOn: true)
        XCTAssertNotEqual(SpotlightIndex.signature(a), SpotlightIndex.signature(b))
    }
}
