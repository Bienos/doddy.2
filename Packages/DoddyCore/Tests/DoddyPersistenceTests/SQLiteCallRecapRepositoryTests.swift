@testable import DoddyCore
@testable import DoddyPersistence
import GRDB
import XCTest

/// Recaps of calls with Doddy, kept on the iPhone (ADR-693, `v21_call_recaps`).
final class SQLiteCallRecapRepositoryTests: XCTestCase {
    private func recap() -> CallRecap {
        CallRecap(
            callId: "6f9619ff-8b86-4d11-b42d-00c04fc964ff", direction: "inbound", startedAt: "2026-11-02T12:00:00.000Z", durationSecs: 42,
            summary: "Poprosiłeś o notatkę o dentyście.", summaryBy: "doddy_model", language: "pl",
            agreed: [CallRecapPointer(text: "Dentysta jutro", line: 1, quote: "jutro o 10 mam dentystę")],
            notes: [CallRecapNote(id: "n1", text: "Jutro o 10 dentysta", createdAt: "2026-11-02T12:00:20.000Z")],
            transcript: [CallRecapLine(speaker: "doddy", text: "Hi, this is Doddy.", atSecs: 0),
                         CallRecapLine(speaker: "caller", text: "Mój PIN to ••••. Zapisz, że jutro o 10 mam dentystę.", atSecs: 3.5)],
            builtAt: "2026-11-02T12:01:00.000Z")
    }

    func testSaveReadsBackTheRecapThenTheAcknowledgement() async throws {
        let repo = SQLiteCallRecapRepository(database: try DoddyDatabase.inMemory())
        let id = UUID()
        let saved = try await repo.save(StoredCallRecap(callId: id, recap: recap(), digest: String(repeating: "b", count: 64),
                                                         savedAt: Date(timeIntervalSince1970: 1_793_600_000.1234)))
        XCTAssertEqual(saved.recap, recap(), "the recap, exactly as the server built it")
        XCTAssertTrue(saved.serverCopyPending)

        var acked = saved
        acked.acknowledgedAt = saved.savedAt.addingTimeInterval(2.0005)
        acked.deletions = [CallRecapDeletion(what: "recap", reason: "acked", deletedAt: "2026-11-02T12:02:00Z")]
        let stored = try await repo.save(acked)
        XCTAssertFalse(stored.serverCopyPending)
        XCTAssertEqual(stored.deletions.map(\.reason), ["acked"])
        let read = try await repo.get(id)
        XCTAssertEqual(read, stored)
        let listed = try await repo.list()
        XCTAssertEqual(listed.map(\.callId), [id])
    }

    func testDeleteAndDeleteAll() async throws {
        let repo = SQLiteCallRecapRepository(database: try DoddyDatabase.inMemory())
        let a = UUID(), b = UUID()
        for id in [a, b] {
            _ = try await repo.save(StoredCallRecap(callId: id, recap: recap(), digest: String(repeating: "c", count: 64), savedAt: Date()))
        }
        try await repo.delete(a)
        let afterOne = try await repo.list()
        XCTAssertEqual(afterOne.map(\.callId), [b])
        try await repo.deleteAll()
        let afterAll = try await repo.list()
        XCTAssertTrue(afterAll.isEmpty)
    }

    func testADigestThatIsNotSixtyFourCharactersIsRefused() async throws {
        let repo = SQLiteCallRecapRepository(database: try DoddyDatabase.inMemory())
        do {
            _ = try await repo.save(StoredCallRecap(callId: UUID(), recap: recap(), digest: "short", savedAt: Date()))
            XCTFail("the table's check must refuse it")
        } catch {}
    }
}
