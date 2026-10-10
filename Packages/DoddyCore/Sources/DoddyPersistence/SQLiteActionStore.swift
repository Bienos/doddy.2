import DoddyCore
import Foundation
import GRDB

/// Local SQLite store for action records (ADR-045). Separate file from memories, so deleting
/// memories never loses the key needed to check an unresolved send, and vice versa.
///
/// Each save is one transaction (upsert + read-back). The schema repeats the lifecycle rules as
/// CHECK constraints, so a bug elsewhere cannot store `confirmed` without a provider reference
/// or a sent action without its idempotency key. Approvals are never stored.
public final class SQLiteActionStore: ActionStore {
    let dbQueue: DatabaseQueue

    /// Opens (or creates) the store at `path` and runs migrations. Never deletes or resets an
    /// existing file: a failure is thrown to the caller untouched.
    public convenience init(path: String) throws {
        try self.init(queue: DatabaseQueue(path: path, configuration: Self.configuration()))
    }

    /// In-memory store for tests and UI-test launches. Nothing is written to disk.
    public static func inMemory() throws -> SQLiteActionStore {
        try SQLiteActionStore(queue: DatabaseQueue(configuration: configuration()))
    }

    private init(queue: DatabaseQueue) throws {
        self.dbQueue = queue
        try Self.migrator.migrate(queue)
    }

    private static func configuration() -> Configuration {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA secure_delete = ON")
        }
        return config
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_actions") { db in
            let statuses = ActionStatus.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", ")
            let types = ActionType.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", ")
            try db.execute(sql: """
                CREATE TABLE actions (
                    id TEXT PRIMARY KEY NOT NULL,
                    type TEXT NOT NULL CHECK (type IN (\(types))),
                    status TEXT NOT NULL CHECK (status IN (\(statuses))),
                    payload_json TEXT NOT NULL,
                    idempotency_key TEXT,
                    provider_reference TEXT,
                    failure_reason TEXT,
                    connector_id TEXT NOT NULL,
                    is_simulation INTEGER NOT NULL CHECK (is_simulation IN (0, 1)),
                    history_json TEXT NOT NULL,
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    CHECK (status != 'confirmed' OR (provider_reference IS NOT NULL AND trim(provider_reference) != '')),
                    CHECK (status = 'confirmed' OR provider_reference IS NULL),
                    CHECK (status NOT IN ('executing', 'confirmed', 'failed', 'unknown') OR idempotency_key IS NOT NULL)
                )
                """)
            try db.create(index: "actions_updated_at", on: "actions", columns: ["updated_at_ms"])
        }
        return migrator
    }

    // MARK: ActionStore

    public func loadAll() throws -> [ActionRecord] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM actions").map(Self.record(from:))
        }
    }

    public func save(_ record: ActionRecord) throws {
        let stored = record.storable
        let payload = try Self.json(stored.payload)
        let history = try Self.json(stored.history)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO actions (id, type, status, payload_json, idempotency_key, provider_reference,
                                         failure_reason, connector_id, is_simulation, history_json,
                                         created_at_ms, updated_at_ms)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        type = excluded.type, status = excluded.status, payload_json = excluded.payload_json,
                        idempotency_key = excluded.idempotency_key, provider_reference = excluded.provider_reference,
                        failure_reason = excluded.failure_reason, connector_id = excluded.connector_id,
                        is_simulation = excluded.is_simulation, history_json = excluded.history_json,
                        updated_at_ms = excluded.updated_at_ms
                    """,
                arguments: [
                    stored.id.uuidString, stored.type.rawValue, stored.status.rawValue, payload,
                    stored.idempotencyKey?.uuidString, stored.providerReference, stored.failureReason,
                    stored.connectorID, stored.isSimulation, history,
                    Self.milliseconds(stored.createdAt), Self.milliseconds(stored.updatedAt),
                ])
            let readBack = try Row.fetchOne(db, sql: "SELECT * FROM actions WHERE id = ?", arguments: [stored.id.uuidString])
            guard try readBack.map(Self.record(from:)) == stored else { throw ActionStoreError.verificationFailed }
        }
    }

    public func delete(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        try dbQueue.write { db in
            for id in ids {
                try db.execute(sql: "DELETE FROM actions WHERE id = ?", arguments: [id.uuidString])
            }
        }
    }

    // MARK: Helpers

    private static func record(from row: Row) throws -> ActionRecord {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString),
              let status = ActionStatus(rawValue: row["status"])
        else { throw ActionStoreError.corruptRecord(idString) }
        let key: String? = row["idempotency_key"]
        let idempotencyKey = try key.map { value -> UUID in
            guard let uuid = UUID(uuidString: value) else { throw ActionStoreError.corruptRecord(idString) }
            return uuid
        }
        do {
            let payload = try JSONDecoder().decode(ActionPayload.self, from: Data((row["payload_json"] as String).utf8))
            let history = try JSONDecoder().decode([ActionEvent].self, from: Data((row["history_json"] as String).utf8))
            guard payload.type.rawValue == (row["type"] as String) else { throw ActionStoreError.corruptRecord(idString) }
            return try ActionRecord.restore(
                id: id, payload: payload, status: status, idempotencyKey: idempotencyKey,
                providerReference: row["provider_reference"], failureReason: row["failure_reason"],
                connectorID: row["connector_id"], isSimulation: row["is_simulation"], history: history)
        } catch {
            throw ActionStoreError.corruptRecord(idString)
        }
    }

    private static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }
}
