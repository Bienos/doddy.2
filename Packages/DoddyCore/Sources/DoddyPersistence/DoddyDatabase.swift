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
        // M4a: one note reminder per memory, deleted with it (foreign keys are on in GRDB).
        migrator.registerMigration("v3_note_reminders") { db in
            try db.create(table: "note_reminders") { t in
                t.primaryKey("id", .text)
                t.column("memory_id", .text).notNull().unique()
                    .references("memories", column: "id", onDelete: .cascade)
                t.column("fire_at_ms", .integer).notNull()
                t.column("time_zone_id", .text).notNull()
                t.column("created_at_ms", .integer).notNull()
            }
            try db.create(index: "note_reminders_fire_at", on: "note_reminders", columns: ["fire_at_ms"])
        }
        // ADR-196: a note reminder fires at a time or at a place. SQLite can't relax NOT NULL in
        // place, so the table is rebuilt; every existing (time) reminder is copied across.
        migrator.registerMigration("v4_note_reminder_places") { db in
            try db.execute(sql: """
                CREATE TABLE note_reminders_v4 (
                    id TEXT PRIMARY KEY NOT NULL,
                    memory_id TEXT NOT NULL UNIQUE REFERENCES memories(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL CHECK (kind IN ('time', 'place')),
                    fire_at_ms INTEGER,
                    time_zone_id TEXT,
                    place_name TEXT,
                    latitude REAL,
                    longitude REAL,
                    radius_m INTEGER,
                    on_arrival INTEGER,
                    created_at_ms INTEGER NOT NULL,
                    CHECK ((kind = 'time' AND fire_at_ms IS NOT NULL AND time_zone_id IS NOT NULL
                            AND place_name IS NULL AND latitude IS NULL AND longitude IS NULL
                            AND radius_m IS NULL AND on_arrival IS NULL)
                        OR (kind = 'place' AND fire_at_ms IS NULL AND time_zone_id IS NULL
                            AND length(place_name) BETWEEN 1 AND 60
                            AND latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180
                            AND radius_m BETWEEN 100 AND 1000 AND on_arrival IN (0, 1)))
                );
                INSERT INTO note_reminders_v4 (id, memory_id, kind, fire_at_ms, time_zone_id, created_at_ms)
                    SELECT id, memory_id, 'time', fire_at_ms, time_zone_id, created_at_ms FROM note_reminders;
                DROP TABLE note_reminders;
                ALTER TABLE note_reminders_v4 RENAME TO note_reminders;
                CREATE INDEX note_reminders_fire_at ON note_reminders(fire_at_ms);
                """)
        }
        // Repeating reminders and snooze (ADR-205). New columns only; existing rows stay one-offs.
        migrator.registerMigration("v5_note_reminder_repeat") { db in
            try db.execute(sql: """
                ALTER TABLE note_reminders ADD COLUMN repeat_rule TEXT
                    CHECK (repeat_rule IS NULL OR (kind = 'time' AND repeat_rule IN ('daily', 'weekdays', 'weekly', 'monthly')));
                ALTER TABLE note_reminders ADD COLUMN last_done_at_ms INTEGER
                    CHECK (last_done_at_ms IS NULL OR repeat_rule IS NOT NULL);
                ALTER TABLE note_reminders ADD COLUMN snoozed_until_ms INTEGER
                    CHECK (snoozed_until_ms IS NULL OR repeat_rule IS NOT NULL);
                ALTER TABLE note_reminders ADD COLUMN first_set_for_ms INTEGER
                    CHECK (first_set_for_ms IS NULL OR (kind = 'time' AND repeat_rule IS NULL));
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
