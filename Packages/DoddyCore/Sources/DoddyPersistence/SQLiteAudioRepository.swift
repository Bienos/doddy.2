import DoddyCore
import Foundation
import GRDB

/// Which note carries which recording (ADR-230). The row is deleted with its note; the app
/// deletes the file. Every write is read back before success.
public final class SQLiteAudioRepository: AudioRepository {
    private let dbQueue: DatabaseQueue

    public init(database: DoddyDatabase) {
        self.dbQueue = database.queue
    }

    public func attach(_ audio: MemoryAudio) async throws -> MemoryAudio {
        guard MemoryAudio.isValidFileName(audio.fileName) else { throw AudioError.badFileName }
        guard MemoryAudio.isValidDuration(audio.durationMilliseconds) else { throw AudioError.badDuration }
        let stored = MemoryAudio(
            memoryID: audio.memoryID, fileName: audio.fileName, durationMilliseconds: audio.durationMilliseconds,
            addedAt: DoddyDatabase.truncatedToMilliseconds(audio.addedAt))
        return try await dbQueue.write { db in
            guard try Bool.fetchOne(db, sql: "SELECT 1 FROM memories WHERE id = ?", arguments: [audio.memoryID.uuidString]) == true else {
                throw AudioError.noteNotFound
            }
            try db.execute(
                sql: """
                    INSERT INTO memory_audio (memory_id, file_name, duration_ms, added_at_ms) VALUES (?, ?, ?, ?)
                    ON CONFLICT(memory_id) DO UPDATE SET file_name = excluded.file_name,
                        duration_ms = excluded.duration_ms, added_at_ms = excluded.added_at_ms
                    """,
                arguments: [stored.memoryID.uuidString, stored.fileName, stored.durationMilliseconds,
                            DoddyDatabase.milliseconds(stored.addedAt)])
            guard try Self.fetch(stored.memoryID, db) == stored else { throw MemoryStoreError.verificationFailed }
            return stored
        }
    }

    public func audio(forMemory memoryID: UUID) async throws -> MemoryAudio? {
        try await dbQueue.read { db in try Self.fetch(memoryID, db) }
    }

    public func allAudio() async throws -> [MemoryAudio] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM memory_audio ORDER BY added_at_ms").compactMap(Self.audio(from:))
        }
    }

    public func detach(memoryID: UUID) async throws -> MemoryAudio? {
        try await dbQueue.write { db in
            guard let existing = try Self.fetch(memoryID, db) else { return nil }
            try db.execute(sql: "DELETE FROM memory_audio WHERE memory_id = ?", arguments: [memoryID.uuidString])
            guard try Self.fetch(memoryID, db) == nil else { throw MemoryStoreError.verificationFailed }
            return existing
        }
    }

    private static func fetch(_ memoryID: UUID, _ db: Database) throws -> MemoryAudio? {
        try Row.fetchOne(db, sql: "SELECT * FROM memory_audio WHERE memory_id = ?", arguments: [memoryID.uuidString])
            .flatMap(audio(from:))
    }

    private static func audio(from row: Row) -> MemoryAudio? {
        guard let id = UUID(uuidString: row["memory_id"]) else { return nil }
        return MemoryAudio(
            memoryID: id, fileName: row["file_name"], durationMilliseconds: row["duration_ms"],
            addedAt: DoddyDatabase.date(milliseconds: row["added_at_ms"]))
    }
}
