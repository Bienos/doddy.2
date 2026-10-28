@testable import DoddyCore
@testable import DoddyPersistence
import GRDB
import XCTest

/// The thread with Doddy, kept on the iPhone (ADR-585, `v17_message_thread`).
final class SQLiteMessageThreadRepositoryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    private func user(_ text: String, at offset: TimeInterval, _ delivery: ThreadMessage.Delivery = .sent) -> ThreadMessage {
        ThreadMessage(id: UUID(), sender: .user, text: text, createdAt: t0.addingTimeInterval(offset), delivery: delivery)
    }

    private func doddy(_ text: String, at offset: TimeInterval, notes: [UUID] = []) -> ThreadMessage {
        ThreadMessage(
            id: UUID(), sender: .doddy, text: text, createdAt: t0.addingTimeInterval(offset), delivery: .sent,
            basis: notes.isEmpty ? .general : .savedNotes, noteIDs: notes, notesSent: notes.count)
    }

    func testAppendReadsBackAndRecentIsOldestFirstWithTheNewestLimit() async throws {
        let repo = SQLiteMessageThreadRepository(database: try DoddyDatabase.inMemory())
        let note = UUID()
        let all = [user("one", at: 0), doddy("two", at: 1, notes: [note]), user("three", at: 2), doddy("four", at: 3)]
        for message in all { try await repo.append(message) }

        let everything = try await repo.recent(limit: 10)
        XCTAssertEqual(everything.map(\.text), ["one", "two", "three", "four"])
        XCTAssertEqual(everything[1].noteIDs, [note])
        XCTAssertEqual(everything[1].basis, .savedNotes)

        let lastTwo = try await repo.recent(limit: 2)
        XCTAssertEqual(lastTwo.map(\.text), ["three", "four"], "the newest are kept, still oldest first")
        let none = try await repo.recent(limit: 0)
        XCTAssertEqual(none, [])
    }

    func testTimesAreKeptToTheMillisecondAndTiesKeepTheirOrder() async throws {
        let repo = SQLiteMessageThreadRepository(database: try DoddyDatabase.inMemory())
        let same = t0.addingTimeInterval(0.0004)
        let first = ThreadMessage(id: UUID(), sender: .user, text: "first", createdAt: same, delivery: .sent)
        let second = ThreadMessage(id: UUID(), sender: .doddy, text: "second", createdAt: same, delivery: .sent, basis: .general)
        try await repo.append(first)
        try await repo.append(second)
        let read = try await repo.recent(limit: 5)
        XCTAssertEqual(read.map(\.text), ["first", "second"])
        XCTAssertEqual(read[0].createdAt, DoddyDatabase.truncatedToMilliseconds(same))
    }

    func testDeliveryChangesAreReadBackAndOnlyForUserMessages() async throws {
        let repo = SQLiteMessageThreadRepository(database: try DoddyDatabase.inMemory())
        let sending = user("hello", at: 0, .sending)
        let answer = doddy("hi", at: 1)
        try await repo.append(sending)
        try await repo.append(answer)

        try await repo.setDelivery(id: sending.id, .failed)
        var read = try await repo.recent(limit: 5)
        XCTAssertEqual(read[0].delivery, .failed)
        try await repo.setDelivery(id: sending.id, .sent)
        read = try await repo.recent(limit: 5)
        XCTAssertEqual(read[0].delivery, .sent)

        do {
            try await repo.setDelivery(id: answer.id, .failed)
            XCTFail("Doddy's messages are never 'failed'")
        } catch {
            XCTAssertEqual(error as? MessageThreadError, .notFound)
        }
        do {
            try await repo.setDelivery(id: UUID(), .sent)
            XCTFail("an unknown message")
        } catch {
            XCTAssertEqual(error as? MessageThreadError, .notFound)
        }
    }

    func testAMessageLeftSendingWhenTheAppWasClosedBecomesNotDelivered() async throws {
        let repo = SQLiteMessageThreadRepository(database: try DoddyDatabase.inMemory())
        try await repo.append(user("answered", at: 0))
        try await repo.append(user("left hanging", at: 5, .sending))
        let changed = try await repo.failUnfinished()
        XCTAssertEqual(changed, 1)
        let read = try await repo.recent(limit: 5)
        XCTAssertEqual(read.map(\.delivery), [.sent, .failed])
        let again = try await repo.failUnfinished()
        XCTAssertEqual(again, 0)
    }

    func testDeleteOneAndDeleteAllAreReadBackAsGone() async throws {
        let repo = SQLiteMessageThreadRepository(database: try DoddyDatabase.inMemory())
        let keep = user("keep", at: 0)
        let drop = user("drop", at: 1)
        try await repo.append(keep)
        try await repo.append(drop)
        try await repo.delete(id: drop.id)
        let left = try await repo.recent(limit: 5)
        XCTAssertEqual(left.map(\.text), ["keep"])
        try await repo.deleteAll()
        let none = try await repo.recent(limit: 5)
        XCTAssertEqual(none, [])
    }

    func testExportHoldsEveryWordAndTheSource() async throws {
        let repo = SQLiteMessageThreadRepository(database: try DoddyDatabase.inMemory())
        let note = UUID()
        try await repo.append(user("Co mam w piątek?", at: 0))
        try await repo.append(doddy("Dentystę o 9.", at: 1, notes: [note]))
        let text = String(decoding: try await repo.export(), as: UTF8.self)
        XCTAssertTrue(text.contains("Co mam w piątek?"))
        XCTAssertTrue(text.contains("Dentystę o 9."))
        XCTAssertTrue(text.localizedCaseInsensitiveContains(note.uuidString))
    }

    func testTheTableRefusesWhatTheRulesNeverProduce() async throws {
        let db = try DoddyDatabase.inMemory()
        try await db.queue.write { db in
            // A Doddy message that is not "sent".
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO thread_messages (id, sender, text, created_at_ms, delivery, basis) VALUES ('a', 'doddy', 'x', 1, 'failed', 'general')
                """))
            // A user message with a basis.
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO thread_messages (id, sender, text, created_at_ms, delivery, basis) VALUES ('b', 'user', 'x', 1, 'sent', 'general')
                """))
            // A Doddy message without a basis: nobody said where it came from.
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO thread_messages (id, sender, text, created_at_ms, delivery) VALUES ('c', 'doddy', 'x', 1, 'sent')
                """))
            // Empty text, an unknown sender.
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO thread_messages (id, sender, text, created_at_ms, delivery) VALUES ('d', 'user', '', 1, 'sent')
                """))
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO thread_messages (id, sender, text, created_at_ms, delivery) VALUES ('e', 'bot', 'x', 1, 'sent')
                """))
        }
    }

    func testADuplicateIdIsNotSavedTwice() async throws {
        let repo = SQLiteMessageThreadRepository(database: try DoddyDatabase.inMemory())
        let message = user("once", at: 0)
        try await repo.append(message)
        do {
            try await repo.append(message)
            XCTFail("the same message cannot be saved twice")
        } catch {}
        let read = try await repo.recent(limit: 5)
        XCTAssertEqual(read.count, 1)
    }

    func testDeletedWordsAreNotLeftInTheDatabaseFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("thread-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("doddy.sqlite").path
        let secret = "zxqvwjkunique-thread-secret-\(UUID().uuidString)"

        let database = try DoddyDatabase(path: path)
        let repo = SQLiteMessageThreadRepository(database: database)
        try await repo.append(user(secret, at: 0))
        try await repo.append(doddy("odpowiedź: \(secret)", at: 1))

        // Control: the words really are in the file before they are deleted, so the check below can fail.
        let before = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .contains { (try? Data(contentsOf: dir.appendingPathComponent($0)))?.range(of: Data(secret.utf8)) != nil }
        XCTAssertTrue(before)

        try await repo.deleteAll()

        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) {
            let bytes = try Data(contentsOf: dir.appendingPathComponent(name))
            XCTAssertNil(bytes.range(of: Data(secret.utf8)), "\(name) still holds a deleted message")
        }
    }

    func testAPhotoMessageKeepsOnlyThatItHadAPhoto() async throws {
        let repo = SQLiteMessageThreadRepository(database: try DoddyDatabase.inMemory())
        let withPhoto = ThreadMessage(id: UUID(), sender: .user, text: "Co to?", createdAt: t0, delivery: .sent, hasPhoto: true)
        try await repo.append(withPhoto)
        try await repo.append(user("bez zdjęcia", at: 1))
        let stored = try await repo.recent(limit: 10)
        XCTAssertEqual(stored.map(\.hasPhoto), [true, false])
    }
}
