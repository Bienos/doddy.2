import DoddyCore
import Foundation
import GRDB

/// Recaps of calls with Doddy, on the iPhone (ADR-693, `v21_call_recaps`). A save reads the row back and
/// fails unless it matches, so the app acknowledges a recap (and the server deletes its copy) only after
/// this returned.
public final class SQLiteCallRecapRepository: CallRecapRepository {
    private let dbQueue: DatabaseQueue

    public init(database: DoddyDatabase) {
        self.dbQueue = database.queue
    }

    public func save(_ record: StoredCallRecap) async throws -> StoredCallRecap {
        var record = record
        record.savedAt = DoddyDatabase.truncatedToMilliseconds(record.savedAt)
        record.acknowledgedAt = record.acknowledgedAt.map { max(DoddyDatabase.truncatedToMilliseconds($0), record.savedAt) }
        let toStore = record
        return try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO call_recaps (call_id, recap_json, digest, saved_at_ms, acknowledged_at_ms, deletions_json)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(call_id) DO UPDATE SET recap_json = excluded.recap_json, digest = excluded.digest,
                  acknowledged_at_ms = excluded.acknowledged_at_ms, deletions_json = excluded.deletions_json
                """,
                arguments: [
                    toStore.callId.uuidString, try LearningRows.json(toStore.recap), toStore.digest,
                    DoddyDatabase.milliseconds(toStore.savedAt), toStore.acknowledgedAt.map(DoddyDatabase.milliseconds),
                    try LearningRows.json(toStore.deletions),
                ])
            guard let stored = try Row.fetchOne(db, sql: "SELECT * FROM call_recaps WHERE call_id = ?", arguments: [toStore.callId.uuidString])
                .map(Self.record(from:)), stored == toStore else { throw LearningStoreError.verificationFailed }
            return stored
        }
    }

    public func get(_ callId: UUID) async throws -> StoredCallRecap? {
        try await dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM call_recaps WHERE call_id = ?", arguments: [callId.uuidString]).map(Self.record(from:))
        }
    }

    public func list() async throws -> [StoredCallRecap] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM call_recaps ORDER BY saved_at_ms DESC, rowid DESC").map(Self.record(from:))
        }
    }

    public func delete(_ callId: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM call_recaps WHERE call_id = ?", arguments: [callId.uuidString])
        }
    }

    public func deleteAll() async throws {
        try await dbQueue.write { db in try db.execute(sql: "DELETE FROM call_recaps") }
    }

    private static func record(from row: Row) throws -> StoredCallRecap {
        let idString: String = row["call_id"]
        guard let id = UUID(uuidString: idString) else { throw LearningStoreError.corruptRecord(idString) }
        do {
            return StoredCallRecap(
                callId: id,
                recap: try LearningRows.decode(CallRecap.self, row["recap_json"]),
                digest: row["digest"],
                savedAt: DoddyDatabase.date(milliseconds: row["saved_at_ms"]),
                acknowledgedAt: (row["acknowledged_at_ms"] as Int64?).map(DoddyDatabase.date(milliseconds:)),
                deletions: try LearningRows.decode([CallRecapDeletion].self, row["deletions_json"]))
        } catch {
            throw LearningStoreError.corruptRecord(idString)
        }
    }
}
