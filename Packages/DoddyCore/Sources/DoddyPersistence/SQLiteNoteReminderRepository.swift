import DoddyCore
import Foundation
import GRDB

/// Note reminders live in the one Doddy database, so deleting a memory deletes its reminder in the
/// same transaction (`ON DELETE CASCADE`). Writes are read back before success, like memories.
public final class SQLiteNoteReminderRepository: NoteReminderRepository {
    private let dbQueue: DatabaseQueue

    public init(database: DoddyDatabase) {
        self.dbQueue = database.queue
    }

    public func allReminders() async throws -> [MemoryReminder] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM note_reminders ORDER BY fire_at_ms, rowid")
                .map(Self.reminder(from:))
        }
    }

    public func reminder(id: UUID) async throws -> MemoryReminder? {
        try await dbQueue.read { db in try Self.fetchReminder(id: id, db) }
    }

    public func reminder(forMemory memoryID: UUID) async throws -> MemoryReminder? {
        try await dbQueue.read { db in
            try Row.fetchOne(
                db, sql: "SELECT * FROM note_reminders WHERE memory_id = ?", arguments: [memoryID.uuidString]
            ).map(Self.reminder(from:))
        }
    }

    public func reminderCount() async throws -> Int {
        try await dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_reminders") ?? 0 }
    }

    public func currentText(ofMemory memoryID: UUID) async throws -> String? {
        try await dbQueue.read { db in
            try String.fetchOne(
                db, sql: "SELECT current_text FROM memories WHERE id = ?", arguments: [memoryID.uuidString])
        }
    }

    public func upsertReminder(_ reminder: MemoryReminder) async throws -> MemoryReminder {
        try await dbQueue.write { db in
            guard try Bool.fetchOne(
                db, sql: "SELECT EXISTS(SELECT 1 FROM memories WHERE id = ?)",
                arguments: [reminder.memoryID.uuidString]) == true
            else { throw NoteReminderError.memoryNotFound }
            try db.execute(
                sql: "DELETE FROM note_reminders WHERE memory_id = ?", arguments: [reminder.memoryID.uuidString])
            var arguments: StatementArguments = [reminder.id.uuidString, reminder.memoryID.uuidString]
            switch reminder.trigger {
            case .time(let fireAt, let zone):
                arguments += ["time", DoddyDatabase.milliseconds(fireAt), zone, nil, nil, nil, nil, nil]
            case .place(let place):
                arguments += [
                    "place", nil, nil, place.name, place.latitude, place.longitude, place.radiusMeters, place.onArrival,
                ]
            }
            arguments += [DoddyDatabase.milliseconds(reminder.createdAt)]
            try db.execute(
                sql: """
                    INSERT INTO note_reminders (id, memory_id, kind, fire_at_ms, time_zone_id, place_name,
                                                latitude, longitude, radius_m, on_arrival, created_at_ms)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: arguments)
            guard try Self.fetchReminder(id: reminder.id, db) == reminder else {
                throw MemoryStoreError.verificationFailed
            }
            return reminder
        }
    }

    @discardableResult
    public func deleteReminder(id: UUID) async throws -> Bool {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM note_reminders WHERE id = ?", arguments: [id.uuidString])
            return db.changesCount > 0
        }
    }

    private static func fetchReminder(id: UUID, _ db: Database) throws -> MemoryReminder? {
        try Row.fetchOne(db, sql: "SELECT * FROM note_reminders WHERE id = ?", arguments: [id.uuidString])
            .map(reminder(from:))
    }

    private static func reminder(from row: Row) throws -> MemoryReminder {
        let idString: String = row["id"]
        let memoryString: String = row["memory_id"]
        guard let id = UUID(uuidString: idString), let memoryID = UUID(uuidString: memoryString) else {
            throw MemoryStoreError.corruptRecord(idString)
        }
        let trigger: ReminderTrigger
        switch row["kind"] as String {
        case "time":
            guard let fireAt = row["fire_at_ms"] as Int64?, let zone = row["time_zone_id"] as String? else {
                throw MemoryStoreError.corruptRecord(idString)
            }
            trigger = .time(fireAt: DoddyDatabase.date(milliseconds: fireAt), timeZoneID: zone)
        case "place":
            do {
                trigger = .place(try ReminderPlace(
                    name: row["place_name"], latitude: row["latitude"], longitude: row["longitude"],
                    radiusMeters: row["radius_m"], onArrival: row["on_arrival"]))
            } catch {
                throw MemoryStoreError.corruptRecord(idString)
            }
        default:
            throw MemoryStoreError.corruptRecord(idString)
        }
        return MemoryReminder(
            id: id, memoryID: memoryID, trigger: trigger, createdAt: DoddyDatabase.date(milliseconds: row["created_at_ms"]))
    }
}
