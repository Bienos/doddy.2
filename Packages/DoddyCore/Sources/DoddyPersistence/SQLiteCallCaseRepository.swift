import DoddyCore
import Foundation
import GRDB

/// Call cases on the iPhone (ADR-500): brief, preview, answer card with transcript, cost and the
/// server's deletion receipts. A save reads the row back and fails unless it matches.
public final class SQLiteCallCaseRepository: CallCaseRepository {
    private let dbQueue: DatabaseQueue

    public init(database: DoddyDatabase) {
        self.dbQueue = database.queue
    }

    public func save(_ record: StoredCallCase) async throws -> StoredCallCase {
        var record = record
        record.createdAt = DoddyDatabase.truncatedToMilliseconds(record.createdAt)
        record.updatedAt = DoddyDatabase.truncatedToMilliseconds(max(record.updatedAt, record.createdAt))
        let toStore = record
        return try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO call_cases (id, kind, state, outcome, created_at_ms, updated_at_ms, brief_json, preview_json,
                                        result_attempt_id, result_json, cost_json, deletions_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET state = excluded.state, outcome = excluded.outcome, updated_at_ms = excluded.updated_at_ms,
                  brief_json = excluded.brief_json, preview_json = excluded.preview_json, result_attempt_id = excluded.result_attempt_id,
                  result_json = excluded.result_json, cost_json = excluded.cost_json, deletions_json = excluded.deletions_json
                """,
                arguments: [
                    toStore.id.uuidString, toStore.kind.rawValue, toStore.state, toStore.result?.outcome.rawValue,
                    DoddyDatabase.milliseconds(toStore.createdAt), DoddyDatabase.milliseconds(toStore.updatedAt),
                    try LearningRows.json(toStore.brief), try toStore.preview.map(LearningRows.json),
                    toStore.resultAttemptId?.uuidString, try toStore.result.map(LearningRows.json), try toStore.cost.map(LearningRows.json),
                    try LearningRows.json(toStore.deletions),
                ])
            guard let stored = try Row.fetchOne(db, sql: "SELECT * FROM call_cases WHERE id = ?", arguments: [toStore.id.uuidString])
                .map(Self.record(from:)), stored == toStore else { throw LearningStoreError.verificationFailed }
            return stored
        }
    }

    public func list() async throws -> [StoredCallCase] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM call_cases ORDER BY created_at_ms DESC, rowid DESC").map(Self.record(from:))
        }
    }

    public func get(_ id: UUID) async throws -> StoredCallCase? {
        try await dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM call_cases WHERE id = ?", arguments: [id.uuidString]).map(Self.record(from:))
        }
    }

    public func delete(_ id: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM call_cases WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func deleteAll() async throws {
        try await dbQueue.write { db in try db.execute(sql: "DELETE FROM call_cases") }
    }

    /// Everything kept about calls, for the user's own export.
    public func export() async throws -> Data {
        let all = try await list()
        return try LearningJSON.encoder().encode(all)
    }

    private static func record(from row: Row) throws -> StoredCallCase {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString), CaseKind(rawValue: row["kind"]) == .call else {
            throw LearningStoreError.corruptRecord(idString)
        }
        do {
            var record = StoredCallCase(
                id: id, createdAt: DoddyDatabase.date(milliseconds: row["created_at_ms"]), state: row["state"],
                brief: try LearningRows.decode(CallBriefDraft.self, row["brief_json"]),
                preview: try (row["preview_json"] as String?).map { try LearningRows.decode(CallPreview.self, $0) },
                resultAttemptId: (row["result_attempt_id"] as String?).flatMap(UUID.init(uuidString:)),
                result: try (row["result_json"] as String?).map { try LearningRows.decode(CallResultCard.self, $0) },
                cost: try (row["cost_json"] as String?).map { try LearningRows.decode(CaseCost.self, $0) },
                deletions: try LearningRows.decode([DeletionReceipt].self, row["deletions_json"]))
            record.updatedAt = DoddyDatabase.date(milliseconds: row["updated_at_ms"])
            return record
        } catch {
            throw LearningStoreError.corruptRecord(idString)
        }
    }
}
