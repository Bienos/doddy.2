import DoddyCore
@testable import DoddyPersistence
import Foundation
import GRDB
import XCTest

/// ADR-236 (OP-003): every correction of a note is kept, against real SQLite.
final class MemoryHistoryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_630_120)

    private func tempPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("doddy-\(UUID()).sqlite").path
    }

    /// A clock that moves one minute per reading, so each correction has its own time.
    private final class Clock: @unchecked Sendable {
        private var next: Date
        init(_ start: Date) { next = start }
        func tick() -> Date { defer { next += 60 }; return next }
    }

    func testEveryCorrectionIsKeptInOrderAndSurvivesReopening() async throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let clock = Clock(t0.addingTimeInterval(3600))
        var repo = try SQLiteMemoryRepository(path: path, now: clock.tick)
        let note = try await repo.save(NewMemory(text: "Tom's shoe size is 43", capturedAt: t0))
        _ = try await repo.update(id: note.id, currentText: "Tom's shoe size is 42")
        _ = try await repo.update(id: note.id, currentText: "Tom's shoe size is 42.5")
        let last = try await repo.update(id: note.id, currentText: "Tom's shoe size is 42 (Asics 42.5)")

        repo = try SQLiteMemoryRepository(path: path)
        let corrections = try await repo.corrections(of: note.id)
        XCTAssertEqual(corrections.map(\.number), [1, 2, 3])
        XCTAssertEqual(corrections.map(\.text), ["Tom's shoe size is 42", "Tom's shoe size is 42.5", "Tom's shoe size is 42 (Asics 42.5)"])
        XCTAssertEqual(corrections.map(\.correctedAt), [3600, 3660, 3720].map { t0.addingTimeInterval($0) })

        let reloaded = try await repo.list(limit: nil)
        let history = MemoryHistory(record: try XCTUnwrap(reloaded.first), corrections: corrections)
        XCTAssertTrue(history.isComplete)
        XCTAssertEqual(history.versions.map(\.text), ["Tom's shoe size is 43"] + corrections.map(\.text))
        XCTAssertEqual(history.versions.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(history.versions.last?.isCurrent, true)
        XCTAssertEqual(history.versions.last?.text, last.currentText)
        XCTAssertEqual(history.earlier.map(\.number), [3, 2, 1], "earlier versions, newest first")
        XCTAssertEqual(history.versions.first?.savedAt, t0)
    }

    func testOnlyTheCurrentWordingIsSearchable() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let note = try await repo.save(NewMemory(text: "Spare keys in the blue tin", capturedAt: t0))
        _ = try await repo.update(id: note.id, currentText: "Spare keys in the green tin")
        _ = try await repo.update(id: note.id, currentText: "Spare keys in the red tin")
        let recall = RepositoryRecallService(repository: repo)
        let green = try await recall.recall("green", limit: 5)
        XCTAssertEqual(green, .noMatch, "a corrected-away wording is history, not an answer")
        guard case .matches(let red) = try await recall.recall("red tin", limit: 5) else { return XCTFail() }
        XCTAssertEqual(red.map(\.memoryID), [note.id])
    }

    func testDeletingANoteDeletesItsHistory() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let a = try await repo.save(NewMemory(text: "Gate code 4471", capturedAt: t0))
        let b = try await repo.save(NewMemory(text: "Wifi Sunflower", capturedAt: t0))
        _ = try await repo.update(id: a.id, currentText: "Gate code 4472")
        _ = try await repo.update(id: b.id, currentText: "Wifi Sunflower-2291")
        try await repo.delete(id: a.id)
        var all = try await repo.allCorrections()
        XCTAssertEqual(all.map(\.memoryID), [b.id])
        do {
            _ = try await repo.corrections(of: a.id)
            XCTFail("a deleted note has no history to read")
        } catch let error as MemoryStoreError {
            XCTAssertEqual(error, .notFound(a.id))
        }
        try await repo.deleteAll()
        all = try await repo.allCorrections()
        XCTAssertEqual(all, [])
    }

    func testUndoAndRestoreBringTheWholeHistoryBack() async throws {
        let source = try SQLiteMemoryRepository.inMemory()
        let note = try await source.save(NewMemory(text: "Dentist Thursday 14:30", capturedAt: t0))
        _ = try await source.update(id: note.id, currentText: "Dentist Thursday 15:00")
        let current = try await source.update(id: note.id, currentText: "Dentist Friday 15:00")
        let history = try await source.corrections(of: note.id)

        // Undo after delete: the copy kept in memory goes back with its corrections.
        try await source.delete(id: note.id)
        let undone = try await source.restore([current], corrections: history)
        XCTAssertEqual(undone, [current])
        let afterUndo = try await source.corrections(of: note.id)
        XCTAssertEqual(afterUndo, history)

        // Export → restore on another iPhone.
        let file = try MemoryRestore.read(try await source.export())
        XCTAssertEqual(file.corrections, history)
        let target = try SQLiteMemoryRepository.inMemory()
        let plan = MemoryRestore.plan(file.records, corrections: file.corrections, existing: [], exportedAt: file.exportedAt)
        XCTAssertEqual(plan.corrections, history)
        _ = try await target.restore(plan.toAdd, corrections: plan.corrections)
        let restored = try await target.corrections(of: note.id)
        XCTAssertEqual(restored, history)
    }

    func testRestoreLeavesOutCorrectionsThatAreNotTheNotesWholeHistory() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let record = try MemoryRecord(
            id: UUID(), rawText: "A", currentText: "C", source: .explicitText, capturedAt: t0,
            updatedAt: t0.addingTimeInterval(120), userEdited: true)
        // Numbered 1 and 3: a gap, so this isn't its whole history.
        let gappy = [
            try MemoryCorrection(memoryID: record.id, number: 1, text: "B", correctedAt: t0.addingTimeInterval(60)),
            try MemoryCorrection(memoryID: record.id, number: 3, text: "C", correctedAt: t0.addingTimeInterval(120)),
        ]
        let added = try await repo.restore([record], corrections: gappy)
        XCTAssertEqual(added, [record], "the note itself is still added")
        let stored = try await repo.corrections(of: record.id)
        XCTAssertEqual(stored, [])
        let history = MemoryHistory(record: record, corrections: stored)
        XCTAssertFalse(history.isComplete)
        XCTAssertEqual(history.versions.map(\.text), ["A", "C"])
    }

    /// A note corrected before history was kept (or restored from an older export) keeps the
    /// wording it has now when it is corrected again: nothing is lost.
    func testCorrectingANoteWithoutHistoryKeepsItsCurrentWording() async throws {
        let repo = try SQLiteMemoryRepository.inMemory(now: { Date(timeIntervalSince1970: 1_791_640_000) })
        let legacy = try MemoryRecord(
            id: UUID(), rawText: "A", currentText: "B", source: .explicitText, capturedAt: t0,
            updatedAt: t0.addingTimeInterval(60), userEdited: true)
        _ = try await repo.restore([legacy])
        _ = try await repo.update(id: legacy.id, currentText: "C")
        let corrections = try await repo.corrections(of: legacy.id)
        XCTAssertEqual(corrections.map(\.text), ["B", "C"])
        XCTAssertEqual(corrections.first?.correctedAt, t0.addingTimeInterval(60), "B keeps the time it was made")
    }

    /// A database written by the previous version (v4) gets one correction per edited note:
    /// its current wording. Unedited notes get none.
    func testUpgradeFromV4KeepsEditedNotesCurrentWordingAsHistory() async throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let edited = UUID(), untouched = UUID()
        do {
            let queue = try DatabaseQueue(path: path)
            try DoddyDatabase.migrator.migrate(queue, upTo: "v4_note_reminder_places")
            try await queue.write { db in
                try db.execute(sql: """
                    INSERT INTO memories (id, raw_text, current_text, source, captured_at_ms, updated_at_ms, user_edited, search_text)
                    VALUES (?, 'Size 43', 'Size 42', 'explicit_text', 1791630120000, 1791630180000, 1, 'size 42');
                    INSERT INTO memories (id, raw_text, current_text, source, captured_at_ms, search_text)
                    VALUES (?, 'Old note', 'Old note', 'explicit_text', 1791630120000, 'old note');
                    """, arguments: [edited.uuidString, untouched.uuidString])
            }
        }
        let repo = try SQLiteMemoryRepository(path: path)
        let all = try await repo.allCorrections()
        XCTAssertEqual(all, [try MemoryCorrection(
            memoryID: edited, number: 1, text: "Size 42", correctedAt: Date(timeIntervalSince1970: 1_791_630_180))])
        _ = try await repo.update(id: edited, currentText: "Size 42.5")
        let next = try await repo.corrections(of: edited)
        XCTAssertEqual(next.map(\.number), [1, 2])
    }

    func testTheTableRefusesBadRowsEvenFromABug() async throws {
        let note = UUID()
        // Straight into the table: a correction for a missing note, number 0, blank text.
        let queue = try DatabaseQueue()
        try DoddyDatabase.migrator.migrate(queue)
        try await queue.write { db in
            try db.execute(sql: """
                INSERT INTO memories (id, raw_text, current_text, source, captured_at_ms, search_text)
                VALUES (?, 'Note', 'Note', 'explicit_text', 1, 'note')
                """, arguments: [note.uuidString])
        }
        for (memoryID, number, text) in [(UUID().uuidString, 1, "x"), (note.uuidString, 0, "x"), (note.uuidString, 1, "  ")] {
            do {
                try await queue.write { db in
                    try db.execute(
                        sql: "INSERT INTO memory_corrections (memory_id, number, text, corrected_at_ms) VALUES (?, ?, ?, 1)",
                        arguments: [memoryID, number, text])
                }
                XCTFail("stored a bad correction: \(memoryID) \(number) '\(text)'")
            } catch is DatabaseError {}
        }
    }
}
