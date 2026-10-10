import DoddyCore
import Foundation
import GRDB

/// Which note carries which photo file (ADR-218). The row is deleted with its note; the app
/// deletes the file. Every write is read back before success.
public final class SQLitePhotoRepository: PhotoRepository {
    private let dbQueue: DatabaseQueue

    public init(database: DoddyDatabase) {
        self.dbQueue = database.queue
    }

    public func attach(_ photo: MemoryPhoto) async throws -> MemoryPhoto {
        guard MemoryPhoto.isValidFileName(photo.fileName) else { throw PhotoError.badFileName }
        guard photo.width > 0, photo.height > 0, max(photo.width, photo.height) <= PhotoLimits.maxPixels else {
            throw PhotoError.badSize
        }
        let stored = MemoryPhoto(
            memoryID: photo.memoryID, fileName: photo.fileName, width: photo.width, height: photo.height,
            addedAt: DoddyDatabase.truncatedToMilliseconds(photo.addedAt))
        return try await dbQueue.write { db in
            guard try Bool.fetchOne(db, sql: "SELECT 1 FROM memories WHERE id = ?", arguments: [photo.memoryID.uuidString]) == true else {
                throw PhotoError.noteNotFound
            }
            try db.execute(
                sql: """
                    INSERT INTO memory_photos (memory_id, file_name, width, height, added_at_ms) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(memory_id) DO UPDATE SET file_name = excluded.file_name, width = excluded.width,
                        height = excluded.height, added_at_ms = excluded.added_at_ms
                    """,
                arguments: [stored.memoryID.uuidString, stored.fileName, stored.width, stored.height,
                            DoddyDatabase.milliseconds(stored.addedAt)])
            guard try Self.fetch(stored.memoryID, db) == stored else { throw MemoryStoreError.verificationFailed }
            return stored
        }
    }

    public func photo(forMemory memoryID: UUID) async throws -> MemoryPhoto? {
        try await dbQueue.read { db in try Self.fetch(memoryID, db) }
    }

    public func allPhotos() async throws -> [MemoryPhoto] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM memory_photos ORDER BY added_at_ms").compactMap(Self.photo(from:))
        }
    }

    public func detach(memoryID: UUID) async throws -> MemoryPhoto? {
        try await dbQueue.write { db in
            guard let existing = try Self.fetch(memoryID, db) else { return nil }
            try db.execute(sql: "DELETE FROM memory_photos WHERE memory_id = ?", arguments: [memoryID.uuidString])
            guard try Self.fetch(memoryID, db) == nil else { throw MemoryStoreError.verificationFailed }
            return existing
        }
    }

    private static func fetch(_ memoryID: UUID, _ db: Database) throws -> MemoryPhoto? {
        try Row.fetchOne(db, sql: "SELECT * FROM memory_photos WHERE memory_id = ?", arguments: [memoryID.uuidString])
            .flatMap(photo(from:))
    }

    private static func photo(from row: Row) -> MemoryPhoto? {
        guard let id = UUID(uuidString: row["memory_id"]) else { return nil }
        return MemoryPhoto(
            memoryID: id, fileName: row["file_name"], width: row["width"], height: row["height"],
            addedAt: DoddyDatabase.date(milliseconds: row["added_at_ms"]))
    }
}
