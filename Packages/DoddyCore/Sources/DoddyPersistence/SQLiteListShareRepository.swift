import DoddyCore
import Foundation
import GRDB

/// Links between local lists and their iCloud zones (ADR-258), in the same SQLite file. A link
/// goes when its list is deleted (foreign key, cascade). Every save is read back.
public final class SQLiteListShareRepository: ListShareRepository {
    private let dbQueue: DatabaseQueue

    public init(database: DoddyDatabase) {
        self.dbQueue = database.queue
    }

    public func shares() async throws -> [ListShare] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM list_shares ORDER BY list_id").map(Self.share(from:))
        }
    }

    public func save(_ share: ListShare) async throws {
        guard let base = String(data: try share.base.encoded(), encoding: .utf8) else { throw MemoryStoreError.verificationFailed }
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO list_shares (list_id, zone_name, zone_owner, role, base_json, synced_at_ms)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(list_id) DO UPDATE SET zone_name = excluded.zone_name, zone_owner = excluded.zone_owner,
                        role = excluded.role, base_json = excluded.base_json, synced_at_ms = excluded.synced_at_ms
                    """,
                arguments: [
                    share.listID.uuidString, share.zoneName, share.zoneOwner, share.role.rawValue, base,
                    DoddyDatabase.milliseconds(share.syncedAt),
                ])
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM list_shares WHERE list_id = ?", arguments: [share.listID.uuidString]),
                  try Self.share(from: row) == share
            else { throw MemoryStoreError.verificationFailed }
        }
    }

    public func remove(listID: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM list_shares WHERE list_id = ?", arguments: [listID.uuidString])
            guard try Row.fetchOne(db, sql: "SELECT 1 FROM list_shares WHERE list_id = ?", arguments: [listID.uuidString]) == nil
            else { throw MemoryStoreError.verificationFailed }
        }
    }

    private static func share(from row: Row) throws -> ListShare {
        let idString: String = row["list_id"]
        let baseText: String = row["base_json"]
        guard let id = UUID(uuidString: idString), let role = ListShareRole(rawValue: row["role"]),
              let base = SharedListState.decoded(Data(baseText.utf8))
        else { throw MemoryStoreError.corruptRecord(idString) }
        return ListShare(
            listID: id, zoneName: row["zone_name"], zoneOwner: row["zone_owner"], role: role, base: base,
            syncedAt: DoddyDatabase.date(milliseconds: row["synced_at_ms"]))
    }
}
