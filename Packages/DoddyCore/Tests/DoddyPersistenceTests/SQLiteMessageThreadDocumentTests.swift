@testable import DoddyCore
@testable import DoddyPersistence
import GRDB
import XCTest

/// A file Doddy made, kept in the thread (ADR-606, `v18_thread_document`).
final class SQLiteMessageThreadDocumentTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_792_000_000)
    private let link = URL(string: "https://doddy.example.com/d/abc")!

    func testAFileBubbleIsReadBackWithItsNameKindAndLink() async throws {
        let database = try DoddyDatabase.inMemory()
        let repo = SQLiteMessageThreadRepository(database: database)
        let file = ThreadMessage.file(ThreadDocument(url: link, name: "Plan bety.pptx", kind: "deck"), now: t0)
        try await repo.append(file)
        let read = try await repo.recent(limit: 5)
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read[0].document, ThreadDocument(url: link, name: "Plan bety.pptx", kind: "deck"))
        XCTAssertEqual(read[0].text, "Plan bety.pptx")
    }

    func testMessagesWithoutAFileHaveNoDocumentAndOlderRowsStillRead() async throws {
        let database = try DoddyDatabase.inMemory()
        let repo = SQLiteMessageThreadRepository(database: database)
        try await repo.append(ThreadMessage(sender: .user, text: "hej", createdAt: t0, delivery: .sent))
        // A row written before v18 has no document column value at all.
        let later = DoddyDatabase.milliseconds(t0.addingTimeInterval(1))
        try await database.queue.write { db in
            try db.execute(sql: """
                INSERT INTO thread_messages (id, sender, text, created_at_ms, delivery, basis) VALUES (?, 'doddy', 'cześć', ?, 'sent', 'general')
                """, arguments: [UUID().uuidString, later])
        }
        let read = try await repo.recent(limit: 5)
        XCTAssertEqual(read.map(\.text), ["hej", "cześć"])
        XCTAssertTrue(read.allSatisfy { $0.document == nil })
    }

    func testAnUnreadableDocumentIsACorruptRecordNotAGuess() async throws {
        let database = try DoddyDatabase.inMemory()
        let repo = SQLiteMessageThreadRepository(database: database)
        let now = DoddyDatabase.milliseconds(t0)
        try await database.queue.write { db in
            try db.execute(sql: """
                INSERT INTO thread_messages (id, sender, text, created_at_ms, delivery, basis, document_json) VALUES (?, 'doddy', 'x', ?, 'sent', 'general', '{"nope":1}')
                """, arguments: [UUID().uuidString, now])
        }
        do {
            _ = try await repo.recent(limit: 5)
            XCTFail("a document that cannot be read must not be shown as if it were fine")
        } catch {
            XCTAssertTrue(error is LearningStoreError)
        }
    }

    func testDeletingTheConversationRemovesTheFileBubbleToo() async throws {
        let database = try DoddyDatabase.inMemory()
        let repo = SQLiteMessageThreadRepository(database: database)
        try await repo.append(ThreadMessage.file(ThreadDocument(url: link, name: "Plan bety.pptx", kind: "deck"), now: t0))
        try await repo.deleteAll()
        let none = try await repo.recent(limit: 5)
        XCTAssertEqual(none, [])
    }
}
