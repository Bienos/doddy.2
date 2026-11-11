import DoddyCore
@testable import DoddyPersistence
import Foundation
import XCTest

/// Private notes (ADR-310) are left out inside the search, before the limit (audit 9 Nov 2026, F03).
/// Before the fix, 21 private matches filled the limit of 20 and a public note with the same word
/// was reported as "not found" by voice, Siri, typed actions and Ask Doddy.
final class PrivateRecallBeforeLimitTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_760_000_000)

    /// More private matches than the limit, each a closer match than the public note.
    private func crowded(_ repo: SQLiteMemoryRepository) async throws -> (privateIDs: Set<UUID>, publicID: UUID) {
        var privateIDs = Set<UUID>()
        for i in 0..<25 {
            let note = try await repo.save(NewMemory(text: "auditkey private \(i)", capturedAt: t.addingTimeInterval(Double(100 + i))))
            privateIDs.insert(note.id)
        }
        let publicNote = try await repo.save(NewMemory(
            text: "auditkey " + String(repeating: "a public description of the place ", count: 30), capturedAt: t))
        return (privateIDs, publicNote.id)
    }

    func testPublicNoteIsFoundPastMorePrivateMatchesThanTheLimit() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let (privateIDs, publicID) = try await crowded(repo)
        let shareable = ShareableRecallService(base: RepositoryRecallService(repository: repo)) { privateIDs }

        let outcome = try await shareable.recall("auditkey", limit: 20)

        guard case .matches(let found) = outcome else { return XCTFail("the public note must be found, got \(outcome)") }
        XCTAssertEqual(found.map(\.memoryID), [publicID])
    }

    func testRepositoryLeavesExcludedNotesOutBeforeTheLimit() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let (privateIDs, publicID) = try await crowded(repo)

        let excluded = try await repo.query("auditkey", limit: 20, excluding: privateIDs)
        XCTAssertEqual(excluded.map(\.memoryID), [publicID])

        // The app's own search screen still finds private notes (shown only after Face ID).
        let everything = try await repo.query("auditkey", limit: 100)
        XCTAssertEqual(everything.count, 26)
        let limited = try await repo.query("auditkey", limit: 20)
        XCTAssertEqual(limited.count, 20)
    }

    func testOnlyPrivateMatchesGiveNoMatch() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let pin = try await repo.save(NewMemory(text: "Bank PIN 4417", capturedAt: t))
        _ = try await repo.save(NewMemory(text: "Keys in the blue tin", capturedAt: t))
        let shareable = ShareableRecallService(base: RepositoryRecallService(repository: repo)) { [pin.id] }

        let outcome = try await shareable.recall("bank pin", limit: 20)
        XCTAssertEqual(outcome, .noMatch, "says nothing was found, not that something is hidden")
    }

    /// The word-rule scan (typos) runs when the index finds too few; it must skip private notes too.
    func testTypoScanSkipsExcludedNotes() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let secret = try await repo.save(NewMemory(text: "Passport number in the drawer", capturedAt: t))
        let open = try await repo.save(NewMemory(text: "Passport photos at the shop", capturedAt: t.addingTimeInterval(1)))

        let found = try await repo.query("pasport", limit: 20, excluding: [secret.id])
        XCTAssertFalse(found.contains { $0.memoryID == secret.id })
        XCTAssertTrue(found.allSatisfy { $0.memoryID == open.id })
    }

    func testALargePrivateSetStaysOneBoundValue() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let note = try await repo.save(NewMemory(text: "Parking level 3", capturedAt: t))
        let ids = Set((0..<1500).map { _ in UUID() })

        let found = try await repo.query("parking", limit: 20, excluding: ids)
        XCTAssertEqual(found.map(\.memoryID), [note.id])
    }

    func testAMarkedNoteIsLeftOutOnTheNextSearch() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let note = try await repo.save(NewMemory(text: "Gate code 2580", capturedAt: t))
        var privateIDs = Set<UUID>()
        let box = Box()
        let shareable = ShareableRecallService(base: RepositoryRecallService(repository: repo)) { box.ids }

        let before = try await shareable.recall("gate code", limit: 20)
        XCTAssertEqual(before, .matches([MemoryCandidate(record: note, matchedTerms: ["gate", "code"])]))
        privateIDs.insert(note.id)
        box.ids = privateIDs
        let after = try await shareable.recall("gate code", limit: 20)
        XCTAssertEqual(after, .noMatch)
    }
}

/// The private set is read at each search, as the app reads it from storage.
private final class Box: @unchecked Sendable {
    var ids: Set<UUID> = []
}
