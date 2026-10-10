import DoddyCore
import Foundation
import GRDB

/// Reminder actions in the app's SQLite file. Every write is read back before returning.
public final class SQLiteReminderActionStore: ReminderActionStore {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func get(_ operationID: UUID) async throws -> ReminderAction? {
        try await dbQueue.read { db in try Self.fetch(operationID, db) }
    }

    public func put(_ action: ReminderAction) async throws {
        let payload = try action.payload.canonicalJSON()
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO outbox_actions (operation_id, type, state, payload_json, external_id, error_code,
                                                source_memory_id, created_at_ms, updated_at_ms, verified_at_ms)
                    VALUES (?, 'create_apple_reminder', ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(operation_id) DO UPDATE SET state = excluded.state, payload_json = excluded.payload_json,
                      external_id = excluded.external_id, error_code = excluded.error_code,
                      updated_at_ms = excluded.updated_at_ms, verified_at_ms = excluded.verified_at_ms
                    """,
                arguments: [
                    action.operationID.uuidString, action.state.rawValue, payload, action.externalID, action.errorCode,
                    action.sourceMemoryID?.uuidString, Self.ms(action.createdAt), Self.ms(action.updatedAt),
                    action.verifiedAt.map(Self.ms),
                ])
            guard let back = try Self.fetch(action.operationID, db), back.state == action.state,
                  back.externalID == action.externalID, back.payload == action.payload
            else { throw MemoryStoreError.verificationFailed }
        }
    }

    public func recent(limit: Int) async throws -> [ReminderAction] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM outbox_actions ORDER BY created_at_ms DESC LIMIT ?", arguments: [max(0, limit)])
                .map(Self.action(from:))
        }
    }

    public func inStates(_ states: [ActionState]) async throws -> [ReminderAction] {
        guard !states.isEmpty else { return [] }
        let marks = Array(repeating: "?", count: states.count).joined(separator: ",")
        return try await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM outbox_actions WHERE state IN (\(marks)) ORDER BY created_at_ms",
                             arguments: StatementArguments(states.map(\.rawValue)))
                .map(Self.action(from:))
        }
    }

    private static func fetch(_ id: UUID, _ db: Database) throws -> ReminderAction? {
        try Row.fetchOne(db, sql: "SELECT * FROM outbox_actions WHERE operation_id = ?", arguments: [id.uuidString])
            .map(action(from:))
    }

    private static func action(from row: Row) throws -> ReminderAction {
        let idString: String = row["operation_id"]
        let payloadJSON: String = row["payload_json"]
        guard let id = UUID(uuidString: idString),
              let state = ActionState(rawValue: row["state"]),
              let payload = try? JSONDecoder().decode(ReminderPayload.self, from: Data(payloadJSON.utf8))
        else { throw MemoryStoreError.corruptRecord(idString) }
        func date(_ column: String) -> Date? {
            (row[column] as Int64?).map { Date(timeIntervalSince1970: Double($0) / 1000) }
        }
        return ReminderAction(
            operationID: id, state: state, payload: payload, externalID: row["external_id"], errorCode: row["error_code"],
            sourceMemoryID: (row["source_memory_id"] as String?).flatMap(UUID.init(uuidString:)),
            createdAt: date("created_at_ms") ?? Date(timeIntervalSince1970: 0),
            updatedAt: date("updated_at_ms") ?? Date(timeIntervalSince1970: 0), verifiedAt: date("verified_at_ms"))
    }

    private static func ms(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded(.down)) }
}
