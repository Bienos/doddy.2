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

    func testRestoreAddsExportedNotesExactlyOnceAndKeepsNotesAlreadyHere() async throws {
        let source = try SQLiteMemoryRepository.inMemory()
        let keys = try await source.save(NewMemory(text: "Spare keys in the blue tin", capturedAt: t0))
        let corrected = try await source.update(id: keys.id, currentText: "Spare keys in the red tin")
        let code = try await source.save(NewMemory(text: "Kod do bramy 4821", source: .explicitVoice, capturedAt: t0.addingTimeInterval(1)))
        // Many dates with odd milliseconds must survive export and restore exactly.
        var many: [MemoryRecord] = []
        for i in 0..<200 {
            many.append(try await source.save(NewMemory(
                text: "Note \(i)", capturedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 0.001 + 0.0007))))
        }
        let exported = try MemoryRestore.read(try await source.export()).records
        XCTAssertEqual(exported.count, 202)

        let target = try SQLiteMemoryRepository.inMemory()
        let mine = try await target.save(NewMemory(text: "Already on the new phone", capturedAt: t0))
        let added = try await target.restore(exported)
        XCTAssertEqual(Set(added), Set([corrected, code] + many))
        let listed = try await target.list(limit: nil)
        XCTAssertEqual(Set(listed), Set([mine, corrected, code] + many))

        // Restored notes are searchable by their current text.
        let recall = RepositoryRecallService(repository: target)
        guard case .matches(let hits) = try await recall.recall("red tin", limit: 5) else { return XCTFail("expected a match") }
        XCTAssertEqual(hits.map(\.memoryID), [keys.id])

        // A second restore of the same file adds nothing, and a note changed here since the
        // export is not overwritten by the file's older version.
        let changedHere = try await target.update(id: keys.id, currentText: "Spare keys with Ania")
        let again = try await target.restore(exported)
        XCTAssertEqual(again, [])
        let afterAgain = try await target.list(limit: nil)
        XCTAssertEqual(afterAgain.first { $0.id == keys.id }, changedHere)
    }

    func testChangingTheTypeKeepsTheWordsDatesAndEditedState() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let saved = try await repo.save(NewMemory(text: "Gate code 4821", source: .explicitVoice, capturedAt: t0))
        XCTAssertEqual(saved.category, .other)
        let corrected = try await repo.update(id: saved.id, currentText: "Gate code 4822")

        let filed = try await repo.setCategory(id: saved.id, to: .place)
        XCTAssertEqual(filed.category, .place)
        XCTAssertEqual(filed.rawText, saved.rawText)
        XCTAssertEqual(filed.currentText, "Gate code 4822")
        XCTAssertEqual(filed.capturedAt, corrected.capturedAt)
        XCTAssertEqual(filed.updatedAt, corrected.updatedAt, "filing is not a correction")
        XCTAssertEqual(filed.source, .explicitVoice)
        XCTAssertTrue(filed.userEdited)

        let listed = try await repo.list(limit: nil)
        XCTAssertEqual(listed, [filed], "stored, not just returned")

        // A note that was never corrected stays "not edited".
        let plain = try await repo.save(NewMemory(text: "Call Ania", capturedAt: t0))
        let plainFiled = try await repo.setCategory(id: plain.id, to: .commitment)
        XCTAssertFalse(plainFiled.userEdited)
        XCTAssertNil(plainFiled.updatedAt)

        do {
            _ = try await repo.setCategory(id: UUID(), to: .fact)
            XCTFail("a missing note can't be filed")
        } catch {
            XCTAssertTrue(error is MemoryStoreError)
        }
    }

    /// A restore that fails its read-back must leave nothing behind, not even the notes before the
    /// bad one (ADR-178). A date with sub-millisecond precision can't be stored exactly, so the
    /// read-back doesn't match: a failure injected through the public API.
    func testRestoreThatFailsItsReadBackAddsNothing() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let mine = try await repo.save(NewMemory(text: "Already here", capturedAt: t0))
        let good = try MemoryRecord(id: UUID(), rawText: "Fine note", source: .explicitText, capturedAt: Date(timeIntervalSince1970: 1_760_000_000.123))
        let unstorable = try MemoryRecord(id: UUID(), rawText: "Odd date", source: .explicitText, capturedAt: Date(timeIntervalSince1970: 1_760_000_000.1234567))

        do {
            _ = try await repo.restore([good, unstorable])
            XCTFail("the read-back should not match")
        } catch {
            XCTAssertEqual(error as? MemoryStoreError, .verificationFailed)
        }
        let listed = try await repo.list(limit: nil)
        XCTAssertEqual(listed, [mine], "the good note before the bad one was rolled back too")
        let recall = RepositoryRecallService(repository: repo)
        let search = try await recall.recall("Fine note", limit: 5)
        XCTAssertEqual(search, .noMatch, "and it is not in the search index either")
    }

    /// The search index must follow a delete and an undo (A-08): gone after delete, back after restore.
    func testSearchFollowsDeleteAndUndo() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let recall = RepositoryRecallService(repository: repo)
        let saved = try await repo.save(NewMemory(text: "Locker twelve code 4821", capturedAt: t0))

        try await repo.delete(id: saved.id)
        let gone = try await recall.recall("locker code", limit: 5)
        XCTAssertEqual(gone, .noMatch)

        _ = try await repo.restore([saved])
        guard case .matches(let hits) = try await recall.recall("locker code", limit: 5) else { return XCTFail("expected the restored note") }
        XCTAssertEqual(hits.map(\.memoryID), [saved.id])
    }

    func testUndoAfterDeleteBringsTheExactNoteBack() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let saved = try await repo.save(NewMemory(text: "Locker 12, code 4821", capturedAt: t0))
        let corrected = try await repo.update(id: saved.id, currentText: "Locker 14, code 4821")
        try await repo.delete(id: saved.id)
        let afterDelete = try await repo.list(limit: nil)
        XCTAssertTrue(afterDelete.isEmpty)

        let restored = try await repo.restore([corrected])
        XCTAssertEqual(restored, [corrected])
        let listed = try await repo.list(limit: nil)
        XCTAssertEqual(listed, [corrected], "same id, original and corrected text, dates")
    }
}
