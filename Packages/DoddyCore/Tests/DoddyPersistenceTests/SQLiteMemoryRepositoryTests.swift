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
        // "book" also matches: English "book" finds Polish "książkę" (RecallMatching.bilingual).
        XCTAssertEqual(Set(hits[0].matchedTerms), ["book", "marta", "polecila", "lodz"])
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

    /// The searches that failed on the owner's iPhone on 2026-10-09 (V1_VOICE_STATUS.md), plus
    /// typos and Polish endings, on real SQLite.
    func testRecallAcrossLanguagesSpokenNumbersEndingsAndTypos() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let code = try await repo.save(NewMemory(text: "Kod: pięć, sześć, siedem, osiem.", capturedAt: t0))
        let birthday = try await repo.save(NewMemory(text: "Moje urodziny są jutro.", capturedAt: t0))
        let dentist = try await repo.save(NewMemory(text: "Dentist appointment on Friday at 9.", capturedAt: t0))
        let locker = try await repo.save(NewMemory(text: "Paczkomat code 4821", capturedAt: t0))
        let recall = RepositoryRecallService(repository: repo)

        func ids(_ question: String) async throws -> [UUID] {
            guard case .matches(let hits) = try await recall.recall(question, limit: 5) else { return [] }
            return hits.map(\.memoryID)
        }

        // English question, Polish note.
        var found = try await ids("what code you have saved?")
        XCTAssertEqual(found.first, locker.id, "both mention a code; the one with 'code' in it ranks first")
        XCTAssertTrue(found.contains(code.id))
        // Digits find a code saved as number words.
        found = try await ids("5678")
        XCTAssertEqual(found, [code.id])
        found = try await ids("five six seven eight")
        XCTAssertEqual(found, [code.id])
        // Polish ending and English counterpart.
        found = try await ids("kiedy mam urodziny?")
        XCTAssertEqual(found, [birthday.id])
        found = try await ids("when is my birthday")
        XCTAssertEqual(found, [birthday.id])
        // Typos.
        found = try await ids("dentsit")
        XCTAssertEqual(found, [dentist.id])
        found = try await ids("paczkomta")
        XCTAssertEqual(found, [locker.id])
        // Nothing related: still an honest no-match.
        let none = try await recall.recall("passport number", limit: 5)
        XCTAssertEqual(none, .noMatch)
    }
}
