import DoddyCore
import DoddyPersistence
import Foundation
import XCTest

final class ScopedMemoryRecallTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testListsCannotCrowdANoteOutOfALimitedRecall() async throws {
        let repository = try SQLiteMemoryRepository.inMemory()
        let note = try await repository.save(NewMemory(text: "restaurant Zapiecek near Warsaw", capturedAt: now))
        for _ in 0..<25 {
            _ = try await repository.save(NewMemory(text: "restaurant", category: .list, capturedAt: now.addingTimeInterval(1)))
        }
        let outcome = try await RepositoryRecallService(repository: repository).recall("restaurant", limit: 1)
        guard case .matches(let hits) = outcome else { return XCTFail("Lists must not consume the note limit") }
        XCTAssertEqual(hits.map(\.memoryID), [note.id])
    }

    func testPrivateNotesCannotCrowdOutAShareableNote() async throws {
        let repository = try SQLiteMemoryRepository.inMemory()
        let note = try await repository.save(NewMemory(text: "restaurant Zapiecek near Warsaw", capturedAt: now))
        var hidden = Set<UUID>()
        for _ in 0..<25 {
            let record = try await repository.save(NewMemory(text: "restaurant", capturedAt: now.addingTimeInterval(1)))
            hidden.insert(record.id)
        }
        let ids = hidden
        let service = ShareableRecallService(base: RepositoryRecallService(repository: repository), privateIDs: { ids })
        guard case .matches(let hits) = try await service.recall("restaurant", limit: 1) else {
            return XCTFail("Private notes must be excluded before LIMIT")
        }
        XCTAssertEqual(hits.map(\.memoryID), [note.id])
    }

    func testPrivateWordCannotSuppressAShareableFuzzyMatch() async throws {
        let repository = try SQLiteMemoryRepository.inMemory()
        let visible = try await repository.save(NewMemory(text: "Passport expires in May", capturedAt: now))
        let hidden = try await repository.save(NewMemory(text: "Password for the account", capturedAt: now))
        // 'password' and 'passport' are two edits apart: a closer match suppresses the fallback.
        let service = ShareableRecallService(base: RepositoryRecallService(repository: repository), privateIDs: { [hidden.id] })
        guard case .matches(let hits) = try await service.recall("password", limit: 5) else {
            return XCTFail("Hidden text must not affect matching in the shareable corpus")
        }
        XCTAssertEqual(hits.map(\.memoryID), [visible.id])
    }

    func testScopedReadSupportsLargePrivateSetsAndEmptyLimits() async throws {
        let repository = try SQLiteMemoryRepository.inMemory()
        let note = try await repository.save(NewMemory(text: "Restauracja Zapiecek", capturedAt: now))
        let excluded = Set((0..<1_100).map { _ in UUID() })
        let service = RepositoryRecallService(repository: repository)
        let outcome = try await service.recall("restaurant", limit: 1, excluding: excluded)
        XCTAssertEqual(outcome, .matches([MemoryCandidate(record: note, matchedTerms: ["restaurant"])]))
        let zero = try await service.recall("restaurant", limit: 0, excluding: [])
        let negative = try await service.recall("restaurant", limit: -1, excluding: [])
        XCTAssertEqual(zero, .noMatch)
        XCTAssertEqual(negative, .noMatch)
    }

    func testCorrectionDeletionAndReopenStillHonorScopedRecall() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scoped-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = try SQLiteMemoryRepository(path: url.path)
        let note = try await repository.save(NewMemory(text: "Music preference: hypnotic techno", capturedAt: now))
        _ = try await repository.update(id: note.id, currentText: "Music preference: jazz")
        let service = RepositoryRecallService(repository: try SQLiteMemoryRepository(path: url.path))
        let old = try await service.recall("techno", limit: 5, excluding: [])
        XCTAssertEqual(old, .noMatch)
        guard case .matches(let hits) = try await service.recall("jazz", limit: 5, excluding: []) else { return XCTFail() }
        XCTAssertEqual(hits.map(\.memoryID), [note.id])
        try await repository.delete(id: note.id)
        let deleted = try await service.recall("jazz", limit: 5, excluding: [])
        XCTAssertEqual(deleted, .noMatch)
    }
}
