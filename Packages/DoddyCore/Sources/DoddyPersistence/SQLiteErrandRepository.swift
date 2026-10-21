import DoddyCore
import Foundation
import GRDB

/// Tasks handed to Doddy, on the iPhone (ADR-566, `v15_errands`): the user's words, Doddy's brief,
/// the result card and the server's deletion report. A save reads the row back and fails unless it
/// matches, so the app acknowledges a result (and the server deletes its copy) only after this
/// returned.
public final class SQLiteErrandRepository: ErrandRepository {
    private let dbQueue: DatabaseQueue

    public init(database: DoddyDatabase) {
        self.dbQueue = database.queue
    }

    public func save(_ record: StoredErrand) async throws -> StoredErrand {
        var record = record
        record.createdAt = DoddyDatabase.truncatedToMilliseconds(record.createdAt)
        record.updatedAt = DoddyDatabase.truncatedToMilliseconds(max(record.updatedAt, record.createdAt))
        record.acknowledgedAt = record.acknowledgedAt.map(DoddyDatabase.truncatedToMilliseconds)
        let toStore = record
        return try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO errands (id, state, failure, created_at_ms, updated_at_ms, draft_json, result_json, result_digest,
                                     deletions_json, acknowledged_at_ms)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET state = excluded.state, failure = excluded.failure, updated_at_ms = excluded.updated_at_ms,
                  draft_json = excluded.draft_json, result_json = excluded.result_json, result_digest = excluded.result_digest,
                  deletions_json = excluded.deletions_json, acknowledged_at_ms = excluded.acknowledged_at_ms
                """,
                arguments: [
                    toStore.id.uuidString, toStore.state.rawValue, toStore.failure?.rawValue,
                    DoddyDatabase.milliseconds(toStore.createdAt), DoddyDatabase.milliseconds(toStore.updatedAt),
                    try LearningRows.json(toStore.draft), try toStore.result.map(LearningRows.json), toStore.resultDigest,
                    try LearningRows.json(toStore.deletions), toStore.acknowledgedAt.map(DoddyDatabase.milliseconds),
                ])
            guard let stored = try Row.fetchOne(db, sql: "SELECT * FROM errands WHERE id = ?", arguments: [toStore.id.uuidString])
                .map(Self.record(from:)), stored == toStore else { throw LearningStoreError.verificationFailed }
            return stored
        }
    }

    public func list() async throws -> [StoredErrand] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM errands ORDER BY created_at_ms DESC, rowid DESC").map(Self.record(from:))
        }
    }

    public func get(_ id: UUID) async throws -> StoredErrand? {
        try await dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM errands WHERE id = ?", arguments: [id.uuidString]).map(Self.record(from:))
        }
    }

    public func delete(_ id: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM errands WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func deleteAll() async throws {
        try await dbQueue.write { db in try db.execute(sql: "DELETE FROM errands") }
    }

    /// Everything kept about tasks handed over, for the user's own export.
    public func export() async throws -> Data {
        let all = try await list()
        return try LearningJSON.encoder().encode(all)
    }

    private static func record(from row: Row) throws -> StoredErrand {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString) else { throw LearningStoreError.corruptRecord(idString) }
        do {
            var record = StoredErrand(
                id: id, createdAt: DoddyDatabase.date(milliseconds: row["created_at_ms"]),
                state: ErrandState(rawValue: row["state"]) ?? .unknown,
                draft: try LearningRows.decode(ErrandDraft.self, row["draft_json"]),
                result: try (row["result_json"] as String?).map { try LearningRows.decode(ErrandResult.self, $0) },
                resultDigest: row["result_digest"],
                failure: (row["failure"] as String?).map { ErrandFailureCode(rawValue: $0) ?? .unknown },
                deletions: try LearningRows.decode([ErrandDeletion].self, row["deletions_json"]),
                acknowledgedAt: (row["acknowledged_at_ms"] as Int64?).map(DoddyDatabase.date(milliseconds:)))
            record.updatedAt = DoddyDatabase.date(milliseconds: row["updated_at_ms"])
            return record
        } catch {
            throw LearningStoreError.corruptRecord(idString)
        }
    }
}
