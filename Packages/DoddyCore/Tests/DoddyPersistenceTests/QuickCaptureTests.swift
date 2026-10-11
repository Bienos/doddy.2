import DoddyCore
import DoddyPersistence
import Foundation
import XCTest

/// The Mac menu bar's capture (ADR-435) against real SQLite: saved only from the read-back,
/// nothing written for words that need changing, and a failed save never called saved.
final class QuickCaptureTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    func testASavedNoteIsTheOneReadBackAndSurvivesReopening() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("doddy-mac-\(UUID()).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        let outcome = await QuickCapture.save("Ask Marta about the bike lock", to: try SQLiteMemoryRepository(path: path), at: t0)
        guard case .saved(let record) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(record.currentText, "Ask Marta about the bike lock")
        XCTAssertEqual(record.category, .other)
        XCTAssertEqual(record.source, .explicitText)

        let reopened = try await SQLiteMemoryRepository(path: path).list(limit: nil)
        XCTAssertEqual(reopened.map(\.id), [record.id])
    }

    func testWordsThatNeedChangingWriteNothing() async throws {
        let repo = try SQLiteMemoryRepository.inMemory()
        let empty = await QuickCapture.save("   \n ", to: repo, at: t0)
        XCTAssertEqual(empty, .needsChange("Say or type a few words first."))
        let long = await QuickCapture.save(String(repeating: "a", count: MemoryLimits.maxTextLength + 1), to: repo, at: t0)
        XCTAssertEqual(long, .needsChange("A note can be up to \(MemoryLimits.maxTextLength) characters."))
        let stored = try await repo.list(limit: nil)
        XCTAssertTrue(stored.isEmpty)
    }

    func testAFailedSaveIsUnconfirmedNeverSaved() async {
        // Every write throws, as a full disk or a database that won't open would.
        let outcome = await QuickCapture.save("Buy stamps", to: UnavailableMemoryRepository(), at: t0)
        XCTAssertEqual(outcome, .unconfirmed)
    }
}

