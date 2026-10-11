import DoddyCore
import DoddyPersistence
import Foundation
import XCTest

/// ADR-450: "Remember something" in the Mac menu only reports `saved` after a real save.
final class MenuBarCaptureTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_630_120)

    /// A repository whose writes fail, to prove nothing is reported as saved.
    private struct FailingRepository: MemoryRepository {
        struct Failure: Error {}
        func save(_ draft: NewMemory) async throws -> MemoryRecord { throw Failure() }
        func list(limit: Int?) async throws -> [MemoryRecord] { [] }
        func query(_ query: String, limit: Int) async throws -> [MemoryCandidate] { [] }
        func update(id: UUID, currentText: String) async throws -> MemoryRecord { throw Failure() }
        func delete(id: UUID) async throws {}
        func deleteAll() async throws {}
        func export() async throws -> Data { Data() }
    }

    func testSavedNoteIsStoredAsExplicitTextWithTheTypedWords() async throws {
        let repository = try SQLiteMemoryRepository.inMemory()
        let result = await MenuBarCapture.save("Sarah recommended the Thai place", to: repository, at: now)
        guard case .saved(let record) = result else { return XCTFail("expected saved, got \(result)") }
        XCTAssertEqual(record.currentText, "Sarah recommended the Thai place")
        XCTAssertEqual(record.source, .explicitText)
        XCTAssertEqual(record.capturedAt, now)
        let stored = try await repository.list(limit: nil)
        XCTAssertEqual(stored.map(\.id), [record.id])
    }

    func testEmptyTextIsRejectedAndNothingIsStored() async throws {
        let repository = try SQLiteMemoryRepository.inMemory()
        let result = await MenuBarCapture.save("   \n ", to: repository, at: now)
        XCTAssertEqual(result, .rejected(.empty))
        let stored = try await repository.list(limit: nil)
        XCTAssertTrue(stored.isEmpty)
    }

    func testFailedWriteIsNeverReportedAsSaved() async {
        let result = await MenuBarCapture.save("Gate code 4821", to: FailingRepository(), at: now)
        guard case .notSaved(let message) = result else { return XCTFail("expected notSaved, got \(result)") }
        XCTAssertTrue(message.contains("Nothing was marked as saved"))
    }

    func testSavedNoteIsFoundByTheMenusFind() async throws {
        let repository = try SQLiteMemoryRepository.inMemory()
        _ = await MenuBarCapture.save("Gate code 4821", to: repository, at: now)
        let outcome = try await RepositoryRecallService(repository: repository).recall("gate code", limit: 5)
        guard case .matches(let found) = outcome else { return XCTFail("expected a match") }
        XCTAssertEqual(found.first?.record.currentText, "Gate code 4821")
    }
}
