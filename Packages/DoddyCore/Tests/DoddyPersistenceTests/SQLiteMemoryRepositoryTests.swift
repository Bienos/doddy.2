import DoddyCore
import DoddyPersistence
import Foundation
import XCTest

/// Minimal checks of the storage contract: real SQLite, real FTS5, no mocks.
final class SQLiteMemoryRepositoryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000.123_456)

    func testSaveCorrectSearchDeleteAndReopen() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("doddy-\(UUID()).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        var repo = try SQLiteMemoryRepository(path: path)
        let keys = try await repo.save(NewMemory(text: "The spare keys are in the blue tin above the fridge.", capturedAt: t0))
        let book = try await repo.save(NewMemory(text: "Marta poleciła książkę „Lalka” — Łódź, środa.", category: .recommendation, capturedAt: t0))
        XCTAssertEqual(keys.rawText, "The spare keys are in the blue tin above the fridge.")

        let corrected = try await repo.update(id: keys.id, currentText: "The spare keys are in the red tin.")
        XCTAssertEqual(corrected.rawText, keys.rawText)
        XCTAssertTrue(corrected.userEdited)

        // Search uses current text, diacritic-insensitive, prefix terms, stopwords ignored.
        let recall = RepositoryRecallService(repository: repo)
        guard case .matches(let hits) = try await recall.recall("What book did Marta polecila? lodz", limit: 5) else {
            return XCTFail("expected a match")
        }
        XCTAssertEqual(hits.map(\.memoryID), [book.id])
        XCTAssertEqual(Set(hits[0].matchedTerms), ["marta", "polecila", "lodz"])
        guard case .matches(let red) = try await recall.recall("red tin", limit: 5) else { return XCTFail() }
        XCTAssertEqual(red.map(\.memoryID), [keys.id])
        let blue = try await recall.recall("blue", limit: 5)
        XCTAssertEqual(blue, .noMatch, "edited-away text is not indexed")

        // Survives reopening the file (A-05 at the storage layer).
        repo = try SQLiteMemoryRepository(path: path)
        let reloaded = try await repo.list(limit: nil)
        XCTAssertEqual(Set(reloaded), [corrected, book])

        // Delete removes record and index entry, also after reopen (A-08).
        try await repo.delete(id: book.id)
        repo = try SQLiteMemoryRepository(path: path)
        let afterDelete = try await RepositoryRecallService(repository: repo).recall("Marta", limit: 5)
        XCTAssertEqual(afterDelete, .noMatch)
        do {
            try await repo.delete(id: book.id)
            XCTFail("second delete must report notFound")
        } catch {
            XCTAssertEqual(error as? MemoryStoreError, .notFound(book.id))
        }

        try await repo.deleteAll()
        let afterDeleteAll = try await repo.list(limit: nil)
        XCTAssertEqual(afterDeleteAll, [])
    }

    func testExportContainsExactTextAndProvenance() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let saved = try await repo.save(NewMemory(text: "Zażółć 🙂", capturedAt: t0))
        let data = try await repo.export()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let memories = try XCTUnwrap(json["memories"] as? [[String: Any]])
        XCTAssertEqual(memories.first?["rawText"] as? String, "Zażółć 🙂")
        XCTAssertEqual(memories.first?["id"] as? String, saved.id.uuidString)
        XCTAssertEqual(memories.first?["source"] as? String, "explicit_text")
    }
}

final class SQLiteReminderActionStoreTests: XCTestCase {
    func testActionsRoundTripAndAreErasedWithAllMemories() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let store = repo.reminderActionStore()
        let date = Date(timeIntervalSince1970: 1_791_619_200)
        var action = ReminderAction(
            operationID: UUID(), state: .userConfirmed,
            payload: ReminderPayload(title: "Zadzwonić do Anny", notes: "piątek",
                                     due: ReminderDue(year: 2026, month: 10, day: 16, hour: 9, minute: 30, timeZoneID: "Europe/Warsaw")),
            sourceMemoryID: UUID(), createdAt: date, updatedAt: date)
        try await store.put(action)
        try action.move(to: .pendingExternalWrite, at: date)
        try await store.put(action)
        try action.move(to: .verifiedSucceeded, at: date, externalID: "EK-123")
        try await store.put(action)

        let back = try await store.get(action.operationID)
        XCTAssertEqual(back?.state, .verifiedSucceeded)
        XCTAssertEqual(back?.externalID, "EK-123")
        XCTAssertEqual(back?.payload, action.payload)
        XCTAssertEqual(back?.sourceMemoryID, action.sourceMemoryID)
        XCTAssertNotNil(back?.verifiedAt)
        let pending = try await store.inStates([.pendingExternalWrite])
        XCTAssertTrue(pending.isEmpty)
        let recent = try await store.recent(limit: 10)
        XCTAssertEqual(recent.count, 1)

        try await repo.deleteAll()
        let afterDelete = try await store.recent(limit: 10)
        XCTAssertTrue(afterDelete.isEmpty, "delete-all also removes the local records of reminders")
    }
}
