@testable import DoddyCore
@testable import DoddyPersistence
import GRDB
import XCTest

final class SQLiteCallCaseRepositoryTests: XCTestCase {
    private func card() throws -> CallResultCard {
        try JSONDecoder().decode(CallResultCard.self, from: Data("""
        {"outcome":"answered","source":"elevenlabs","confidence":"high","confidenceReasons":[],"summary":"Odpowiedź: „Tak.”",
         "summaryBy":"rules","quote":{"text":"Tak, gotowy.","line":1},
         "transcript":[{"speaker":"doddy","text":"Dzień dobry","atSecs":0},{"speaker":"callee","text":"Tak, gotowy.","atSecs":4.5}],
         "nextStep":{"kind":"save_note","text":"Zapisz odpowiedź w notatkach."},"warnings":[],"callbackPromised":false,"durationSecs":35}
        """.utf8))
    }

    func testSaveReadsBackAndKeepsTheTranscriptOnTheDevice() async throws {
        let repo = SQLiteCallCaseRepository(database: try DoddyDatabase.inMemory())
        let draft = CallBriefDraft(calleeName: "Serwis", phone: "221234567", principalName: "Anna", goal: "Cel", question: "Czy gotowe?",
                                   facts: [CallFactDraft(kind: .pesel, text: "44051401359", ticked: false)])
        let id = UUID()
        var record = StoredCallCase(id: id, createdAt: Date(timeIntervalSince1970: 1_760_000_000.1234), state: "awaiting_approval", brief: draft)
        let saved = try await repo.save(record)
        XCTAssertEqual(saved.brief, draft, "unticked facts stay on the iPhone too")

        record = saved
        record.state = "finished"
        record.updatedAt = saved.createdAt.addingTimeInterval(60)
        record.resultAttemptId = UUID()
        record.result = try card()
        record.cost = CaseCost(currency: "USD", totalMicros: 117_000, complete: true, approximate: true, pending: false, unknownParts: [],
                               items: [.init(component: "twilio_call", ref: "", status: "reported", amountMicros: 27_000, currency: "USD", quantity: 0.6, unit: "minute")])
        record.deletions = [DeletionReceipt(item: "call_result", location: "doddy_server", reason: "acked", result: "deleted",
                                            requestedAt: "2026-10-19T09:31:00.000Z", settledAt: "2026-10-19T09:31:00.000Z", rows: 1)]
        let updated = try await repo.save(record)
        XCTAssertEqual(updated.result?.transcript.last?.text, "Tak, gotowy.")
        XCTAssertEqual(updated.cost?.totalMicros, 117_000)
        let fetched = try await repo.get(id)
        XCTAssertEqual(fetched, updated)
        let all = try await repo.list()
        XCTAssertEqual(all.map(\.id), [id])

        let export = String(decoding: try await repo.export(), as: UTF8.self)
        XCTAssertTrue(export.contains("Tak, gotowy."))

        try await repo.delete(id)
        let gone = try await repo.get(id)
        XCTAssertNil(gone)
    }

    func testAResultNeedsItsAttempt() async throws {
        let db = try DoddyDatabase.inMemory()
        try await db.queue.write { db in
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO call_cases (id, kind, state, created_at_ms, updated_at_ms, brief_json, result_json)
                VALUES ('x', 'call', 'finished', 1, 1, '{}', '{}')
                """))
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO call_cases (id, kind, state, created_at_ms, updated_at_ms, brief_json) VALUES ('y', 'meeting', 's', 1, 1, '{}')
                """))
        }
    }

    func testMigratesFromTheLastShippedSchema() throws {
        let queue = try DatabaseQueue()
        try DoddyDatabase.migrator.migrate(queue, upTo: "v13_outcome_events")
        try DoddyDatabase.migrator.migrate(queue)
        let tables = try queue.read { db in try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'") }
        XCTAssertTrue(tables.contains("call_cases"))
    }
}
