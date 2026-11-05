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

    /// `secure_delete` overwrites a deleted row's pages but not the words an FTS5 index keeps of it:
    /// FTS5 records a delete as new index entries and leaves the old ones until its segments merge
    /// (measured: a deleted note's words were still in the file). Merging them in the same write
    /// transaction as the delete or rewrite is what makes the words leave the file (ADR-584).
    /// `index` is the name of one of the FTS5 tables below, never user input.
    static func compactSearchIndex(_ index: String, in db: Database) throws {
        try db.execute(sql: "INSERT INTO \(index)(\(index)) VALUES('optimize')")
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
        // Repeating reminders and snooze (ADR-211). New columns only; existing rows stay one-offs.
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
        // Lists (ADR-216): a list is a `memories` row with category 'list'; its items go with it.
        migrator.registerMigration("v6_list_items") { db in
            try db.execute(sql: """
                CREATE TABLE list_items (
                    id TEXT PRIMARY KEY NOT NULL,
                    list_id TEXT NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
                    text TEXT NOT NULL CHECK (length(trim(text)) BETWEEN 1 AND \(ListLimits.itemLength)),
                    source TEXT NOT NULL CHECK (source IN (\(sqlList(ListItemSource.allCases.map(\.rawValue))))),
                    added_at_ms INTEGER NOT NULL,
                    done_at_ms INTEGER,
                    position INTEGER NOT NULL CHECK (position >= 0)
                );
                CREATE INDEX list_items_list ON list_items(list_id, position);
                """)
        }
        // Photo notes (ADR-218): one photo per note, deleted with it. The file name is checked.
        migrator.registerMigration("v7_memory_photos") { db in
            try db.execute(sql: """
                CREATE TABLE memory_photos (
                    memory_id TEXT PRIMARY KEY NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
                    file_name TEXT NOT NULL CHECK (length(file_name) = 40 AND file_name LIKE '%.jpg'),
                    width INTEGER NOT NULL CHECK (width BETWEEN 1 AND \(PhotoLimits.maxPixels)),
                    height INTEGER NOT NULL CHECK (height BETWEEN 1 AND \(PhotoLimits.maxPixels)),
                    added_at_ms INTEGER NOT NULL
                );
                """)
        }
        // Voice memos (ADR-230): one recording per note, deleted with it. The file name is checked.
        migrator.registerMigration("v8_memory_audio") { db in
            try db.execute(sql: """
                CREATE TABLE memory_audio (
                    memory_id TEXT PRIMARY KEY NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
                    file_name TEXT NOT NULL CHECK (length(file_name) = 40 AND file_name LIKE '%.m4a'),
                    duration_ms INTEGER NOT NULL CHECK (duration_ms BETWEEN \(VoiceMemoLimits.minMilliseconds) AND \(VoiceMemoLimits.maxSeconds * 1000 + 999)),
                    added_at_ms INTEGER NOT NULL
                );
                """)
        }
        // ADR-252: every correction of a note is kept (text and time), numbered from 1, and
        // deleted with the note. The original stays in memories.raw_text. Notes corrected before
        // this get one correction, their current wording: the in-between ones were never stored.
        migrator.registerMigration("v9_memory_corrections") { db in
            try db.execute(sql: """
                CREATE TABLE memory_corrections (
                    memory_id TEXT NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
                    number INTEGER NOT NULL CHECK (number >= 1),
                    text TEXT NOT NULL CHECK (length(trim(text)) > 0),
                    corrected_at_ms INTEGER NOT NULL,
                    PRIMARY KEY (memory_id, number)
                ) WITHOUT ROWID;
                INSERT INTO memory_corrections (memory_id, number, text, corrected_at_ms)
                    SELECT id, 1, current_text, updated_at_ms FROM memories
                    WHERE user_edited = 1 AND updated_at_ms IS NOT NULL;
                """)
        }
        // Shared lists (ADR-263): which local list is linked to which iCloud zone, and what both
        // sides had at the last sync (JSON). Deleted with the list.
        migrator.registerMigration("v10_list_shares") { db in
            try db.execute(sql: """
                CREATE TABLE list_shares (
                    list_id TEXT PRIMARY KEY NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
                    zone_name TEXT NOT NULL CHECK (length(zone_name) BETWEEN 1 AND 100),
                    zone_owner TEXT NOT NULL CHECK (length(zone_owner) BETWEEN 1 AND 200),
                    role TEXT NOT NULL CHECK (role IN (\(sqlList(ListShareRole.allCases.map(\.rawValue))))),
                    base_json TEXT NOT NULL,
                    synced_at_ms INTEGER NOT NULL
                );
                """)
        }
        // Learning loop (ADR-440, docs/architecture/LEARNING_LOOP.md §8). Three tables of learned
        // data, never code. Facts and procedures carry provenance and an evidence digest; the
        // approval of a procedure step is not stored (derived from the tool name at run time).
        migrator.registerMigration("v11_learned_facts") { db in
            try db.execute(sql: """
                CREATE TABLE learned_facts (
                    id TEXT PRIMARY KEY NOT NULL,
                    kind TEXT NOT NULL CHECK (kind IN (\(sqlList(LearnedFactKind.allCases.map(\.rawValue))))),
                    value TEXT NOT NULL CHECK (length(trim(value)) BETWEEN 1 AND \(LearnedFact.maxValueLength)),
                    search_text TEXT NOT NULL,
                    scope TEXT NOT NULL DEFAULT 'general',
                    confidence INTEGER NOT NULL CHECK (confidence BETWEEN 0 AND 100),
                    provenance_json TEXT NOT NULL,
                    source_episode_ids_json TEXT NOT NULL,
                    evidence_digest TEXT NOT NULL UNIQUE,
                    status TEXT NOT NULL CHECK (status IN (\(sqlList(LearningStatus.allCases.map(\.rawValue))))),
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    expires_at_ms INTEGER,
                    confirmed_at_ms INTEGER,
                    schema_version INTEGER NOT NULL DEFAULT \(LearnedFact.schemaVersion),
                    CHECK ((status = 'confirmed') = (confirmed_at_ms IS NOT NULL))
                );
                CREATE INDEX learned_facts_status ON learned_facts(status, expires_at_ms);
                CREATE TABLE learned_fact_revisions (
                    fact_id TEXT NOT NULL REFERENCES learned_facts(id) ON DELETE CASCADE,
                    number INTEGER NOT NULL CHECK (number >= 1),
                    value TEXT NOT NULL CHECK (length(trim(value)) > 0),
                    confirmed_at_ms INTEGER NOT NULL,
                    PRIMARY KEY (fact_id, number)
                ) WITHOUT ROWID;
                """)
            try db.create(virtualTable: "learned_facts_fts", using: FTS5()) { t in
                t.synchronize(withTable: "learned_facts")
                t.tokenizer = .unicode61()
                t.column("search_text")
            }
        }
        migrator.registerMigration("v12_procedures") { db in
            try db.execute(sql: """
                CREATE TABLE procedures (
                    id TEXT PRIMARY KEY NOT NULL,
                    trigger_text TEXT NOT NULL CHECK (length(trim(trigger_text)) BETWEEN 1 AND \(Procedure.maxTriggerLength)),
                    search_text TEXT NOT NULL,
                    steps_json TEXT NOT NULL,
                    version INTEGER NOT NULL CHECK (version >= 1),
                    scope TEXT NOT NULL DEFAULT 'general',
                    status TEXT NOT NULL CHECK (status IN (\(sqlList(LearningStatus.allCases.map(\.rawValue))))),
                    provenance_json TEXT NOT NULL,
                    source_episode_ids_json TEXT NOT NULL,
                    evidence_digest TEXT NOT NULL UNIQUE,
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    confirmed_at_ms INTEGER,
                    last_used_at_ms INTEGER,
                    use_count INTEGER NOT NULL DEFAULT 0 CHECK (use_count >= 0),
                    schema_version INTEGER NOT NULL DEFAULT \(Procedure.schemaVersion),
                    CHECK ((status = 'confirmed') = (confirmed_at_ms IS NOT NULL))
                );
                CREATE INDEX procedures_status ON procedures(status, last_used_at_ms);
                """)
            try db.create(virtualTable: "procedures_fts", using: FTS5()) { t in
                t.synchronize(withTable: "procedures")
                t.tokenizer = .unicode61()
                t.column("search_text")
            }
        }
        migrator.registerMigration("v13_outcome_events") { db in
            try db.execute(sql: """
                CREATE TABLE outcome_events (
                    id TEXT PRIMARY KEY NOT NULL,
                    request_id TEXT NOT NULL,
                    kind TEXT NOT NULL CHECK (kind IN (\(sqlList(OutcomeKind.allCases.map(\.rawValue))))),
                    detail_json TEXT NOT NULL,
                    created_at_ms INTEGER NOT NULL
                );
                CREATE INDEX outcome_events_created ON outcome_events(created_at_ms);
                CREATE INDEX outcome_events_request ON outcome_events(request_id);
                """)
        }
        // Calls Doddy places for the user (ADR-500): the brief, the answer card with its transcript,
        // the cost and the server's deletion receipts. The transcript is kept only here once the
        // server's copy is deleted.
        migrator.registerMigration("v14_call_cases") { db in
            try db.execute(sql: """
                CREATE TABLE call_cases (
                    id TEXT PRIMARY KEY NOT NULL,
                    kind TEXT NOT NULL CHECK (kind IN (\(sqlList(CaseKind.allCases.map(\.rawValue))))),
                    state TEXT NOT NULL CHECK (length(state) BETWEEN 1 AND 40),
                    outcome TEXT,
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
                    brief_json TEXT NOT NULL,
                    preview_json TEXT,
                    result_attempt_id TEXT,
                    result_json TEXT,
                    cost_json TEXT,
                    deletions_json TEXT NOT NULL DEFAULT '[]',
                    CHECK ((result_json IS NULL) = (result_attempt_id IS NULL))
                );
                CREATE INDEX call_cases_created ON call_cases(created_at_ms);
                """)
        }
        // Tasks handed to Doddy (ADR-570): the user's words and Doddy's brief, the result card and
        // the server's deletion report. The result lives only here once the server deleted its copy
        // (`ack`), so a row can't say acknowledged without a result, nor hold a result without its digest.
        migrator.registerMigration("v15_errands") { db in
            try db.execute(sql: """
                CREATE TABLE errands (
                    id TEXT PRIMARY KEY NOT NULL,
                    state TEXT NOT NULL CHECK (length(state) BETWEEN 1 AND 40),
                    failure TEXT CHECK (failure IS NULL OR length(failure) BETWEEN 1 AND 40),
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
                    draft_json TEXT NOT NULL,
                    result_json TEXT,
                    result_digest TEXT,
                    deletions_json TEXT NOT NULL DEFAULT '[]',
                    acknowledged_at_ms INTEGER,
                    CHECK ((result_json IS NULL) = (result_digest IS NULL)),
                    CHECK (acknowledged_at_ms IS NULL OR result_json IS NOT NULL)
                );
                CREATE INDEX errands_created ON errands(created_at_ms);
                """)
        }
        // DODDY Capture (ADR-588): recordings, their audio parts, their words (searchable) and the
        // notes the user chose to remember from them. A row exists before the audio does, so a kill
        // leaves something to recover. Values are checked by length rather than by list, so a later
        // build can add a kind or a phase without a new migration. A note's link to its recording
        // is cleared, not deleted, with the recording: the note is the user's.
        migrator.registerMigration("v16_recordings") { db in
            try db.execute(sql: """
                CREATE TABLE recordings (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL DEFAULT '' CHECK (length(title) <= \(CaptureLimits.maxTitleCharacters)),
                    kind TEXT NOT NULL CHECK (length(kind) BETWEEN 1 AND 40),
                    origin TEXT NOT NULL CHECK (length(origin) BETWEEN 1 AND 40),
                    phase TEXT NOT NULL CHECK (length(phase) BETWEEN 1 AND 40),
                    language TEXT NOT NULL CHECK (length(language) BETWEEN 2 AND 35),
                    started_at_ms INTEGER NOT NULL,
                    ended_at_ms INTEGER CHECK (ended_at_ms IS NULL OR ended_at_ms >= started_at_ms),
                    duration_ms INTEGER NOT NULL DEFAULT 0 CHECK (duration_ms >= 0),
                    end_reason TEXT CHECK (end_reason IS NULL OR length(end_reason) BETWEEN 1 AND 40),
                    transcription TEXT NOT NULL DEFAULT 'notStarted' CHECK (length(transcription) BETWEEN 1 AND 40),
                    gaps_json TEXT NOT NULL DEFAULT '[]',
                    CHECK ((phase = 'recording') = (ended_at_ms IS NULL))
                );
                CREATE INDEX recordings_started ON recordings(started_at_ms);

                CREATE TABLE recording_parts (
                    recording_id TEXT NOT NULL REFERENCES recordings(id) ON DELETE CASCADE,
                    idx INTEGER NOT NULL CHECK (idx BETWEEN 1 AND 9999),
                    file_name TEXT NOT NULL CHECK (file_name GLOB 'part-[0-9][0-9][0-9][0-9].caf'),
                    start_offset_ms INTEGER NOT NULL CHECK (start_offset_ms >= 0),
                    duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms >= 0),
                    PRIMARY KEY (recording_id, idx)
                ) WITHOUT ROWID;

                CREATE TABLE recording_segments (
                    recording_id TEXT NOT NULL REFERENCES recordings(id) ON DELETE CASCADE,
                    idx INTEGER NOT NULL CHECK (idx >= 0),
                    start_ms INTEGER NOT NULL CHECK (start_ms >= 0),
                    end_ms INTEGER NOT NULL CHECK (end_ms >= start_ms),
                    text TEXT NOT NULL CHECK (length(trim(text)) > 0),
                    original_text TEXT NOT NULL,
                    confidence REAL CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
                    search_text TEXT NOT NULL,
                    UNIQUE (recording_id, idx)
                );
                CREATE INDEX recording_segments_time ON recording_segments(recording_id, start_ms);

                CREATE TABLE recording_memories (
                    memory_id TEXT PRIMARY KEY NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
                    recording_id TEXT REFERENCES recordings(id) ON DELETE SET NULL,
                    at_ms INTEGER NOT NULL CHECK (at_ms >= 0),
                    recording_title TEXT NOT NULL,
                    linked_at_ms INTEGER NOT NULL
                );
                CREATE INDEX recording_memories_recording ON recording_memories(recording_id);
                """)
            try db.create(virtualTable: "recording_segments_fts", using: FTS5()) { t in
                t.synchronize(withTable: "recording_segments")
                t.tokenizer = .unicode61()
                t.column("search_text")
            }
        }
        // The thread with Doddy (ADR-585): typed messages kept on this iPhone until the user deletes them.
        // The table refuses what the rules never produce: a Doddy message that is not "sent", a user
        // message with a basis, a Doddy message without one. (v16 belongs to Capture, ADR-588, registered above.)
        migrator.registerMigration("v17_message_thread") { db in
            try db.execute(sql: """
                CREATE TABLE thread_messages (
                    id TEXT PRIMARY KEY NOT NULL,
                    sender TEXT NOT NULL CHECK (sender IN ('user', 'doddy')),
                    text TEXT NOT NULL CHECK (length(text) BETWEEN 1 AND 50000),
                    created_at_ms INTEGER NOT NULL,
                    delivery TEXT NOT NULL CHECK (delivery IN ('sending', 'sent', 'failed')),
                    basis TEXT CHECK (basis IS NULL OR basis IN ('savedNotes', 'general')),
                    note_ids TEXT NOT NULL DEFAULT '[]',
                    notes_sent INTEGER NOT NULL DEFAULT 0 CHECK (notes_sent >= 0),
                    notes_search_failed INTEGER NOT NULL DEFAULT 0 CHECK (notes_search_failed IN (0, 1)),
                    CHECK (sender = 'user' OR delivery = 'sent'),
                    CHECK ((sender = 'doddy') = (basis IS NOT NULL))
                );
                CREATE INDEX thread_messages_created ON thread_messages(created_at_ms);
                """)
        }
        // A file Doddy made from a message (ADR-606): its name, kind and link as JSON. Older rows have none.
        migrator.registerMigration("v18_thread_document") { db in
            try db.execute(sql: "ALTER TABLE thread_messages ADD COLUMN document_json TEXT")
        }
        // The training logbook (ADR-642): what the person did in a session, kept only with their yes.
        // The checks sit in the table as well as in `LoggedSession`, so a row that breaks a rule cannot
        // be written by any other path. Load is in grams so 2.5 kg compares exactly.
        migrator.registerMigration("v19_training_log") { db in
            try db.execute(sql: """
                CREATE TABLE training_log_consent (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    granted INTEGER NOT NULL CHECK (granted IN (0, 1)),
                    changed_at_ms INTEGER NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE training_sessions (
                    id TEXT PRIMARY KEY,
                    performed_at_ms INTEGER NOT NULL,
                    plan_week INTEGER CHECK (plan_week IS NULL OR plan_week BETWEEN 1 AND 52),
                    feeling TEXT NOT NULL CHECK (feeling IN ('easy', 'okay', 'hard', 'pain')),
                    run_minutes INTEGER CHECK (run_minutes IS NULL OR run_minutes BETWEEN 1 AND 600)
                )
                """)
            try db.execute(sql: "CREATE INDEX training_sessions_performed_at ON training_sessions(performed_at_ms)")
            try db.execute(sql: """
                CREATE TABLE training_sets (
                    session_id TEXT NOT NULL REFERENCES training_sessions(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL CHECK (position >= 0),
                    exercise_key TEXT NOT NULL CHECK (length(exercise_key) BETWEEN 1 AND 48),
                    reps INTEGER NOT NULL CHECK (reps BETWEEN 0 AND 200),
                    load_grams INTEGER CHECK (load_grams IS NULL OR load_grams BETWEEN 0 AND 500000),
                    reps_in_reserve INTEGER CHECK (reps_in_reserve IS NULL OR reps_in_reserve BETWEEN 0 AND 10),
                    PRIMARY KEY (session_id, position)
                )
                """)
        }
        // A message the person sent with a photo (Messages, 28 Oct 2026): only that it had one. The photo itself goes
        // with the question to Doddy's server and on to Anthropic, and is kept neither on this iPhone nor on the server.
        migrator.registerMigration("v20_thread_photo") { db in
            try db.execute(sql: "ALTER TABLE thread_messages ADD COLUMN has_photo INTEGER NOT NULL DEFAULT 0 CHECK (has_photo IN (0, 1))")
        }
        return migrator
    }

    /// Values are fixed enum raw values (letters only), so inlining them is safe.
    private static func sqlList(_ values: [String]) -> String {
        values.map { "'\($0)'" }.joined(separator: ", ")
    }

    static func milliseconds(_ date: Date) -> Int64 { EpochMilliseconds.truncated(date) }

    static func truncatedToMilliseconds(_ date: Date) -> Date { EpochMilliseconds.date(milliseconds(date)) }

    static func date(milliseconds: Int64) -> Date { EpochMilliseconds.date(milliseconds) }
}
