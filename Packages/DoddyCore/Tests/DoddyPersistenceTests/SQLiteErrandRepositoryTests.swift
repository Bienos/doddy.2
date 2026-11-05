@testable import DoddyCore
@testable import DoddyPersistence
import GRDB
import XCTest

/// Tasks handed to Doddy, kept on the iPhone (ADR-570, `v15_errands`).
final class SQLiteErrandRepositoryTests: XCTestCase {
    private let words = "chcę jechać do Rzymu w przyszłym miesiącu na 7 dni,\nsprawdź loty i hotele do 2000 zł"

    private func result() -> ErrandResult {
        ErrandResult(
            answer: "Najlepszy układ: wylot 12.11, powrót 19.11.",
            sections: [.init(heading: "Loty", kind: .options, items: [
                .init(title: "Ryanair WAW–CIA", detail: "bezpośredni", when: "12.11–19.11", price: "389 zł / os.", url: "https://www.ryanair.com/pl/pl", site: "ryanair.com"),
            ])],
            recommendation: "Ryanair.", budget: .init(asked: "hotele do 2000 zł", within: .yes), next: ["Inny tydzień?"],
            sources: [.init(title: "Ryanair", url: "https://www.ryanair.com/pl/pl", site: "ryanair.com")], checkedAt: "2026-10-21T09:12:00Z")
    }

    func testSaveReadsBackTheWordsTheResultAndTheAck() async throws {
        let repo = SQLiteErrandRepository(database: try DoddyDatabase.inMemory())
        let draft = ErrandDraft(words: words, brief: "Loty i hotel w Rzymie.", title: "Rzym, 7 dni")
        let id = UUID()
        let saved = try await repo.save(StoredErrand(id: id, createdAt: Date(timeIntervalSince1970: 1_792_000_000.1234), state: .queued, draft: draft))
        XCTAssertEqual(saved.draft.words, words, "the user's words, exactly")
        XCTAssertEqual(saved.createdAt, DoddyDatabase.truncatedToMilliseconds(Date(timeIntervalSince1970: 1_792_000_000.1234)))

        var record = saved
        record.state = .done
        record.updatedAt = saved.createdAt.addingTimeInterval(600)
        record.result = result()
        record.resultDigest = String(repeating: "c", count: 64)
        let done = try await repo.save(record)
        XCTAssertEqual(done.result, result())
        XCTAssertTrue(done.needsAcknowledgement)

        record = done
        record.deletions = [ErrandDeletion(what: "words", deletedAt: "2026-10-21T09:13:00Z"), ErrandDeletion(what: "result", deletedAt: "2026-10-21T09:13:00Z")]
        record.acknowledgedAt = done.updatedAt.addingTimeInterval(1.0005)
        let acked = try await repo.save(record)
        XCTAssertFalse(acked.needsAcknowledgement)
        XCTAssertEqual(acked.deletions.count, 2)
        let fetched = try await repo.get(id)
        XCTAssertEqual(fetched, acked)

        let export = String(decoding: try await repo.export(), as: UTF8.self)
        XCTAssertTrue(export.contains("Ryanair WAW–CIA"))
        XCTAssertTrue(export.contains("Rzymu"))

        try await repo.delete(id)
        let gone = try await repo.get(id)
        XCTAssertNil(gone)
    }

    func testFailuresAndUnknownStatesAreKept() async throws {
        let repo = SQLiteErrandRepository(database: try DoddyDatabase.inMemory())
        let draft = ErrandDraft(words: "w", brief: "b", title: "t")
        let failed = try await repo.save(StoredErrand(id: UUID(), createdAt: Date(), state: .failed, draft: draft, failure: .timeLimit))
        XCTAssertEqual(failed.failure, .timeLimit)
        let unsure = try await repo.save(StoredErrand(id: UUID(), createdAt: Date(), state: .unknown, draft: draft))
        XCTAssertEqual(unsure.state, .unknown)
    }

    func testListIsNewestFirstAndDeleteAllEmptiesIt() async throws {
        let repo = SQLiteErrandRepository(database: try DoddyDatabase.inMemory())
        let draft = ErrandDraft(words: "w", brief: "b", title: "t")
        let old = try await repo.save(StoredErrand(id: UUID(), createdAt: Date(timeIntervalSince1970: 1_000), state: .done, draft: draft))
        let new = try await repo.save(StoredErrand(id: UUID(), createdAt: Date(timeIntervalSince1970: 2_000), state: .running, draft: draft))
        let listed = try await repo.list()
        XCTAssertEqual(listed.map(\.id), [new.id, old.id])
        try await repo.deleteAll()
        let none = try await repo.list()
        XCTAssertEqual(none, [])
    }

    func testTheTableRefusesAnAckWithoutAResultAndAResultWithoutItsDigest() async throws {
        let db = try DoddyDatabase.inMemory()
        try await db.queue.write { db in
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO errands (id, state, created_at_ms, updated_at_ms, draft_json, result_json) VALUES ('a', 'done', 1, 1, '{}', '{}')
                """), "a result needs its digest")
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO errands (id, state, created_at_ms, updated_at_ms, draft_json, acknowledged_at_ms) VALUES ('b', 'done', 1, 1, '{}', 2)
                """), "acknowledged without a saved result")
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO errands (id, state, created_at_ms, updated_at_ms, draft_json) VALUES ('c', 'queued', 5, 1, '{}')
                """), "updated before created")
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO errands (id, state, created_at_ms, updated_at_ms, draft_json) VALUES ('d', '', 1, 1, '{}')
                """), "no state")
        }
    }

    func testARowThatDoesntDecodeIsReportedNotDropped() async throws {
        let db = try DoddyDatabase.inMemory()
        let id = UUID()
        try await db.queue.write { db in
            try db.execute(sql: "INSERT INTO errands (id, state, created_at_ms, updated_at_ms, draft_json) VALUES (?, 'queued', 1, 1, 'not json')",
                           arguments: [id.uuidString])
        }
        let repo = SQLiteErrandRepository(database: db)
        do {
            _ = try await repo.list()
            XCTFail("a corrupt row must not be skipped")
        } catch {
            XCTAssertEqual(error as? LearningStoreError, .corruptRecord(id.uuidString))
        }
    }

    func testMigratesFromTheLastShippedSchema() throws {
        let queue = try DatabaseQueue()
        try DoddyDatabase.migrator.migrate(queue, upTo: "v14_call_cases")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO call_cases (id, kind, state, created_at_ms, updated_at_ms, brief_json) VALUES ('x', 'call', 'draft', 1, 1, '{}')")
        }
        try DoddyDatabase.migrator.migrate(queue)
        let tables = try queue.read { db in try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'") }
        XCTAssertTrue(tables.contains("errands"))
        let calls = try queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM call_cases") }
        XCTAssertEqual(calls, 1, "earlier tables are untouched")
    }
}
