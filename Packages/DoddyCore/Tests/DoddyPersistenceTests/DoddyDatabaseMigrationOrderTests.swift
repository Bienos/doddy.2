@testable import DoddyCore
@testable import DoddyPersistence
import GRDB
import XCTest

/// `v16_recordings` (Capture, ADR-588) and `v17_message_thread` (Messages, ADR-585) came from two
/// lines of work that were built on phones separately before they were merged. A phone that ran
/// only one of them must open the merged build: the other migration is simply applied, and the
/// file is never refused as "written by a newer version" (`DoddyDatabaseError.newerSchema`).
final class DoddyDatabaseMigrationOrderTests: XCTestCase {
    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("doddy-order-\(UUID()).sqlite").path
    }

    private func tables(in path: String) throws -> Set<String> {
        let queue = try DatabaseQueue(path: path)
        return try queue.read { db in
            Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type IN ('table', 'view')"))
        }
    }

    private func applied(in path: String) throws -> Set<String> {
        let queue = try DatabaseQueue(path: path)
        return try queue.read { db in Set(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")) }
    }

    /// A phone that ran only the Messages line: v17 is in its file, v16 is not.
    func testAFileThatHasMessagesButNotRecordingsOpensAndGetsRecordings() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        _ = try DoddyDatabase(path: path)

        let queue = try DatabaseQueue(path: path)
        try queue.write { db in
            try db.execute(sql: "DROP TABLE recording_segments_fts")
            for table in ["recording_memories", "recording_segments", "recording_parts", "recordings"] {
                try db.execute(sql: "DROP TABLE \(table)")
            }
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v16_recordings'")
        }
        XCTAssertTrue(try applied(in: path).contains("v17_message_thread"))
        XCTAssertFalse(try applied(in: path).contains("v16_recordings"))
        XCTAssertFalse(try tables(in: path).contains("recordings"))

        XCTAssertNoThrow(try DoddyDatabase(path: path), "the merged build opens a file that has only v17")
        XCTAssertTrue(try applied(in: path).isSuperset(of: ["v16_recordings", "v17_message_thread"]))
        XCTAssertTrue(try tables(in: path).isSuperset(of: ["recordings", "recording_segments", "thread_messages"]))
    }

    /// A phone that ran only the Capture line (the web line's build): v16 is in its file, v17 is not.
    func testAFileThatHasRecordingsButNotMessagesOpensAndGetsMessages() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        _ = try DoddyDatabase(path: path)

        let queue = try DatabaseQueue(path: path)
        try queue.write { db in
            try db.execute(sql: "DROP TABLE thread_messages")
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v17_message_thread'")
        }
        XCTAssertTrue(try applied(in: path).contains("v16_recordings"))
        XCTAssertFalse(try applied(in: path).contains("v17_message_thread"))

        XCTAssertNoThrow(try DoddyDatabase(path: path), "the merged build opens a file that has only v16")
        XCTAssertTrue(try applied(in: path).isSuperset(of: ["v16_recordings", "v17_message_thread"]))
        XCTAssertTrue(try tables(in: path).contains("thread_messages"))
    }

    /// The refusal itself still works: a migration this build has never heard of is "newer".
    func testAMigrationFromAFutureBuildIsStillRefusedAndTheFileIsLeftAlone() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        _ = try DoddyDatabase(path: path)
        let queue = try DatabaseQueue(path: path)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO grdb_migrations(identifier) VALUES ('v999_from_the_future')")
        }
        XCTAssertThrowsError(try DoddyDatabase(path: path)) { error in
            XCTAssertEqual(error as? DoddyDatabaseError, .newerSchema)
        }
        XCTAssertTrue(try applied(in: path).contains("v999_from_the_future"), "the file is not touched")
    }
}
