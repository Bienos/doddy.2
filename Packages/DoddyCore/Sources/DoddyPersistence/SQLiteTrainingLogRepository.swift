import DoddyCore
import Foundation
import GRDB

/// The training logbook on this iPhone (ADR-642), on whatever `DoddyDatabase` it is given. The app gives it
/// its own file, left out of backups (`TrainingLogDatabase`), not the notes' file. Three rules
/// hold in every method:
///   - nothing is written without the person's yes, checked in the same transaction as the write
///     (so a withdrawn yes cannot be raced);
///   - a write is read back inside its own transaction and a difference rolls everything back
///     (`verificationFailed`), as for notes;
///   - a delete leaves no row, no set and, because `secure_delete` is on, no readable bytes of them.
/// Nothing in this class talks to a network. Training notes are health data: they stay here.
public final class SQLiteTrainingLogRepository: TrainingLogRepository {
    fileprivate let dbQueue: DatabaseQueue
    fileprivate let now: @Sendable () -> Date

    public init(database: DoddyDatabase, now: @escaping @Sendable () -> Date = Date.init) {
        self.dbQueue = database.queue
        self.now = now
    }

    // MARK: Consent

    public func consent() async throws -> TrainingLogConsent {
        try await dbQueue.read { db in try Self.consent(db) }
    }

    public func grantConsent() async throws -> TrainingLogConsent { try await setConsent(true) }

    public func withdrawConsent() async throws -> TrainingLogConsent { try await setConsent(false) }

    private func setConsent(_ granted: Bool) async throws -> TrainingLogConsent {
        let date = DoddyDatabase.truncatedToMilliseconds(now())
        return try await dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO training_log_consent (id, granted, changed_at_ms) VALUES (1, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET granted = excluded.granted, changed_at_ms = excluded.changed_at_ms
                    """,
                arguments: [granted ? 1 : 0, DoddyDatabase.milliseconds(date)])
            let stored = try Self.consent(db)
            guard stored == TrainingLogConsent(granted: granted, changedAt: date) else {
                throw TrainingLogError.verificationFailed
            }
            return stored
        }
    }

    private static func consent(_ db: Database) throws -> TrainingLogConsent {
        guard let row = try Row.fetchOne(db, sql: "SELECT granted, changed_at_ms FROM training_log_consent WHERE id = 1") else {
            return .neverAsked
        }
        let granted: Int = row["granted"], changed: Int64 = row["changed_at_ms"]
        return TrainingLogConsent(granted: granted == 1, changedAt: DoddyDatabase.date(milliseconds: changed))
    }

    // MARK: Sessions

    public func record(_ session: LoggedSession) async throws -> LoggedSession {
        let latest = now().addingTimeInterval(86_400)
        guard session.performedAt <= latest else { throw TrainingLogError.invalid(.inTheFuture) }
        return try await dbQueue.write { db in
            guard try Self.consent(db).granted else { throw TrainingLogError.consentMissing }
            // A correction replaces the old entry whole; the old sets go with it.
            try db.execute(sql: "DELETE FROM training_sessions WHERE id = ?", arguments: [session.id.uuidString])
            try db.execute(
                sql: """
                    INSERT INTO training_sessions (id, performed_at_ms, plan_week, feeling, run_minutes)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    session.id.uuidString, DoddyDatabase.milliseconds(session.performedAt), session.planWeek,
                    session.feeling.rawValue, session.runMinutes,
                ])
            for (position, set) in session.sets.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO training_sets (session_id, position, exercise_key, reps, load_grams, reps_in_reserve)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [session.id.uuidString, position, set.exerciseKey, set.reps, set.loadGrams, set.repsInReserve])
            }
            guard try Self.session(session.id, db) == session else { throw TrainingLogError.verificationFailed }
            return session
        }
    }

    public func sessions(from: Date? = nil) async throws -> [LoggedSession] {
        try await dbQueue.read { db in try Self.sessions(from: from, db) }
    }

    public func session(id: UUID) async throws -> LoggedSession? {
        try await dbQueue.read { db in try Self.session(id, db) }
    }

    public func delete(id: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM training_sessions WHERE id = ?", arguments: [id.uuidString])
            guard db.changesCount == 1 else { throw TrainingLogError.notFound(id) }
            let left = try Int.fetchOne(
                db, sql: "SELECT (SELECT count(*) FROM training_sessions WHERE id = ?1) + (SELECT count(*) FROM training_sets WHERE session_id = ?1)",
                arguments: [id.uuidString]) ?? 0
            guard left == 0 else { throw TrainingLogError.verificationFailed }
        }
    }

    public func deleteAll() async throws -> Int {
        try await dbQueue.write { db in
            let before = try Int.fetchOne(db, sql: "SELECT count(*) FROM training_sessions") ?? 0
            try db.execute(sql: "DELETE FROM training_sets")
            try db.execute(sql: "DELETE FROM training_sessions")
            let left = try Int.fetchOne(
                db, sql: "SELECT (SELECT count(*) FROM training_sessions) + (SELECT count(*) FROM training_sets)") ?? 0
            guard left == 0 else { throw TrainingLogError.verificationFailed }
            return before
        }
    }

    public func export() async throws -> TrainingLogExport {
        let date = now()
        return try await dbQueue.read { db in
            TrainingLogExport(
                exportedAt: date, consentGranted: try Self.consent(db).granted, sessions: try Self.sessions(from: nil, db))
        }
    }

    // MARK: Reading

    private static func session(_ id: UUID, _ db: Database) throws -> LoggedSession? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM training_sessions WHERE id = ?", arguments: [id.uuidString]) else {
            return nil
        }
        return try session(from: row, sets: try sets(of: id.uuidString, db))
    }

    private static func sessions(from: Date?, _ db: Database) throws -> [LoggedSession] {
        let rows = try Row.fetchAll(
            db, sql: "SELECT * FROM training_sessions WHERE performed_at_ms >= ? ORDER BY performed_at_ms DESC, id",
            arguments: [from.map { DoddyDatabase.milliseconds($0) } ?? Int64.min])
        let allSets = Dictionary(grouping: try Row.fetchAll(
            db, sql: "SELECT * FROM training_sets ORDER BY session_id, position"), by: { (row: Row) -> String in row["session_id"] })
        return try rows.map { row in
            let id: String = row["id"]
            return try session(from: row, sets: try (allSets[id] ?? []).map(set(from:)))
        }
    }

    private static func sets(of id: String, _ db: Database) throws -> [LoggedSet] {
        try Row.fetchAll(db, sql: "SELECT * FROM training_sets WHERE session_id = ? ORDER BY position", arguments: [id])
            .map(set(from:))
    }

    private static func set(from row: Row) throws -> LoggedSet {
        do {
            return try LoggedSet(
                exerciseKey: row["exercise_key"], reps: row["reps"], loadGrams: row["load_grams"],
                repsInReserve: row["reps_in_reserve"])
        } catch {
            throw TrainingLogError.corruptRecord("a stored set breaks the rules of a set")
        }
    }

    private static func session(from row: Row, sets: [LoggedSet]) throws -> LoggedSession {
        let id: String = row["id"], feeling: String = row["feeling"], performed: Int64 = row["performed_at_ms"]
        guard let uuid = UUID(uuidString: id), let parsed = TrainingFeeling(rawValue: feeling) else {
            throw TrainingLogError.corruptRecord("a stored session has an id or a feeling that cannot be read")
        }
        do {
            return try LoggedSession(
                id: uuid, performedAt: DoddyDatabase.date(milliseconds: performed), planWeek: row["plan_week"],
                feeling: parsed, runMinutes: row["run_minutes"], sets: sets)
        } catch {
            throw TrainingLogError.corruptRecord("a stored session breaks the rules of a session")
        }
    }
}
