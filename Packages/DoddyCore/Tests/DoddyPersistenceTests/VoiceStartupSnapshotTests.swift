import DoddyCore
@testable import DoddyPersistence
import Foundation
import XCTest

final class VoiceStartupSnapshotTests: XCTestCase {
    func testBoundsAndPrivacyAreAppliedBeforeLimitAndReadsCurrentWording() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let t = Date(timeIntervalSince1970: 1_760_000_000)
        var privateIDs = Set<UUID>()
        for i in 0..<40 {
            let record = try await repo.save(NewMemory(text: "Private \(i)", capturedAt: t.addingTimeInterval(Double(100 + i))))
            privateIDs.insert(record.id)
        }
        var publicIDs = Set<UUID>()
        for i in 0..<30 {
            let record = try await repo.save(NewMemory(text: "Public \(i)", capturedAt: t.addingTimeInterval(Double(i))))
            publicIDs.insert(record.id)
        }
        let before = try await repo.voiceStartupSnapshot(excluding: privateIDs)
        XCTAssertEqual(before.notes.count, VoiceStartupSnapshot.notesLimit)
        XCTAssertTrue(before.notesTruncated)
        XCTAssertTrue(Set(before.notes.map(\.id)).isSubset(of: publicIDs))
        XCTAssertTrue(before.notes.allSatisfy { !privateIDs.contains($0.id) })
        let id = try XCTUnwrap(before.notes.first?.id)
        _ = try await repo.update(id: id, currentText: "Corrected current wording")
        let after = try await repo.voiceStartupSnapshot(excluding: privateIDs)
        XCTAssertEqual(after.notes.first?.currentText, "Corrected current wording")
        XCTAssertFalse(after.notesContext(excluding: [id]).text.contains("Corrected current wording"),
                       "A note made private after the awaited read is checked again before rendering")
    }

    func testListsAreCountsOnlyAndSamplesNeverEnterNotes() async throws {
        let db = try DoddyDatabase.inMemory()
        let repo = SQLiteMemoryRepository(database: db)
        let lists = SQLiteListRepository(database: db)
        let list = try await lists.create(name: "Groceries", items: ["secret body one", "secret body two"], source: .typed)
        _ = try await lists.setDone([list.items[0].id], done: true)
        try await db.queue.write { db in
            try db.execute(sql: """
                INSERT INTO memories (id, raw_text, current_text, category, source, captured_at_ms,
                                      user_edited, search_text, schema_version)
                VALUES (?, 'Fixture must stay out', 'Fixture must stay out', 'other', 'sample_fixture', NULL,
                        0, 'fixture must stay out', 1)
                """, arguments: [UUID().uuidString])
        }
        let snapshot = try await repo.voiceStartupSnapshot(excluding: [])
        XCTAssertTrue(snapshot.notes.isEmpty, "A list title is not a saved note")
        XCTAssertEqual(snapshot.lists, [.init(id: list.id, name: "Groceries", open: 1, done: 1)])
        XCTAssertFalse(snapshot.listsContext(excluding: []).contains("secret body"))
        let hidden = try await repo.voiceStartupSnapshot(excluding: [list.id])
        XCTAssertTrue(hidden.lists.isEmpty)
    }

    func testLargePrivateSetDoesNotExceedSQLiteVariableLimitAndEmptyIsHonest() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let ids = Set((0..<1500).map { _ in UUID() })
        let snapshot = try await repo.voiceStartupSnapshot(excluding: ids)
        XCTAssertEqual(snapshot.notesContext(excluding: ids).text, "(no saved notes)")
        XCTAssertFalse(snapshot.notesTruncated)
        XCTAssertNotEqual(VoiceStartupSnapshot.unavailableNotes.text, "(no saved notes)")
        XCTAssertTrue(VoiceStartupSnapshot.unavailableNotes.truncated)
    }
}
