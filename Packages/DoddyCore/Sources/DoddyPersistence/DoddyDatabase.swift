import DoddyCore
import Foundation
import GRDB

public enum DoddyDatabaseError: Error, Equatable, Sendable {
    /// The file was written by a newer version of Doddy. It is left untouched.
    case newerSchema
}

/// The one local SQLite file (ADR-003). Memories and the reviewed profile live in the same
/// file but in separate tables; deleting one never touches the other.
public final class DoddyDatabase: Sendable {
    let queue: DatabaseQueue

    /// Opens (or creates) the database at `path` and runs migrations. Never deletes or resets
    /// an existing file: a failure is thrown to the caller untouched.
    public convenience init(path: String) throws {
        try self.init(queue: DatabaseQueue(path: path, configuration: Self.configuration()))
    }

    /// In-memory database for tests and UI-test launches. Nothing is written to disk.
    public static func inMemory() throws -> DoddyDatabase {
        try DoddyDatabase(queue: DatabaseQueue(configuration: configuration()))
    }

    private init(queue: DatabaseQueue) throws {
        if try queue.read({ try Self.migrator.hasBeenSuperseded($0) }) {
            throw DoddyDatabaseError.newerSchema
        }
        try Self.migrator.migrate(queue)
        self.queue = queue
    }

    private static func configuration() -> Configuration {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA secure_delete = ON")
        }
        return config
    }

    /// Shipped migrations are never edited; add a new one instead.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_memories") { db in
            try db.create(table: "memories") { t in
                t.primaryKey("id", .text)
                t.column("raw_text", .text).notNull()
                t.column("current_text", .text).notNull()
                t.column("category", .text).notNull().defaults(to: MemoryCategory.other.rawValue)
                t.column("source", .text).notNull()
                t.column("captured_at_ms", .integer)
                t.column("updated_at_ms", .integer)
                t.column("user_edited", .boolean).notNull().defaults(to: false)
                // Folded copy of current_text (SearchFolding) — the only indexed column.
                t.column("search_text", .text).notNull()
                t.column("schema_version", .integer).notNull().defaults(to: MemoryRecord.schemaVersion)
            }
            try db.create(index: "memories_captured_at", on: "memories", columns: ["captured_at_ms"])
            try db.create(virtualTable: "memories_fts", using: FTS5()) { t in
                t.synchronize(withTable: "memories")
                t.tokenizer = .unicode61()
                t.column("search_text")
            }
        }
        migrator.registerMigration("v2_profile_onboarding") { db in
            // Reviewed profile: one row per approved field. The CHECKs repeat the domain rules
            // so a bad row can't be written even by a bug in the app.
            try db.execute(sql: """
                CREATE TABLE profile_fields (
                    key TEXT PRIMARY KEY NOT NULL CHECK (key IN (\(sqlList(ProfileKey.allCases.map(\.rawValue))))),
                    value TEXT NOT NULL CHECK (length(value) BETWEEN 1 AND \(ProfileKey.allCases.map(\.maxLength).max()!)),
                    source TEXT NOT NULL CHECK (source = '\(ProfileSource.explicitUserReview.rawValue)'),
                    approved_at_ms INTEGER NOT NULL,
                    revision INTEGER NOT NULL CHECK (revision > 0)
                );
                CREATE TABLE onboarding_progress (
                    id INTEGER PRIMARY KEY NOT NULL CHECK (id = 1),
                    walkthrough_version TEXT NOT NULL,
                    setup_decision TEXT NOT NULL CHECK (setup_decision IN (\(sqlList(SetupDecision.allCases.map(\.rawValue))))),
                    setup_step TEXT CHECK (setup_step IN (\(sqlList(SetupStep.allCases.map(\.rawValue))))),
                    intro_decision TEXT NOT NULL CHECK (intro_decision IN (\(sqlList(IntroDecision.allCases.map(\.rawValue))))),
                    updated_at_ms INTEGER NOT NULL
                );
                """)
        }
        return migrator
    }

    /// Values are fixed enum raw values (letters only), so inlining them is safe.
    private static func sqlList(_ values: [String]) -> String {
        values.map { "'\($0)'" }.joined(separator: ", ")
    }

    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }

    static func truncatedToMilliseconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds(date)) / 1000)
    }

    static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }
}
