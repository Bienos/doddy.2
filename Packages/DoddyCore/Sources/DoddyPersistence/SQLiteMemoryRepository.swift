import DoddyCore
import Foundation
import GRDB

/// Local SQLite memory store (ADR-003). Every write runs in one transaction and is read back
/// before success is returned, so a returned record is a committed record.
/// The FTS5 index is kept in sync by triggers; deleted rows are overwritten (`secure_delete`).
public final class SQLiteMemoryRepository: MemoryRepository {
    private let dbQueue: DatabaseQueue
    private let now: @Sendable () -> Date

    public init(database: DoddyDatabase, now: @escaping @Sendable () -> Date = Date.init) {
        self.dbQueue = database.queue
        self.now = now
    }

    /// Opens (or creates) the store at `path` and runs migrations. Never deletes or resets an
    /// existing file: a failure is thrown to the caller untouched.
    public convenience init(path: String, now: @escaping @Sendable () -> Date = Date.init) throws {
        self.init(database: try DoddyDatabase(path: path), now: now)
    }

    /// In-memory store for tests and UI-test launches. Nothing is written to disk.
    public static func inMemory(now: @escaping @Sendable () -> Date = Date.init) throws -> SQLiteMemoryRepository {
        SQLiteMemoryRepository(database: try DoddyDatabase.inMemory(), now: now)
    }

    // MARK: MemoryRepository

    public func save(_ draft: NewMemory) async throws -> MemoryRecord {
        let record = try MemoryRecord(
            id: UUID(), rawText: draft.text, source: draft.source, category: draft.category,
            capturedAt: Self.truncatedToMilliseconds(draft.capturedAt))
        return try await dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO memories (id, raw_text, current_text, category, source, captured_at_ms,
                                          updated_at_ms, user_edited, search_text, schema_version)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    record.id.uuidString, record.rawText, record.currentText, record.category.rawValue,
                    record.source.rawValue, record.capturedAt.map(Self.milliseconds), nil, false,
                    SearchFolding.fold(record.currentText), MemoryRecord.schemaVersion,
                ])
            guard try Self.fetch(record.id, db) == record else { throw MemoryStoreError.verificationFailed }
            return record
        }
    }

    public func list(limit: Int?) async throws -> [MemoryRecord] {
        try await dbQueue.read { db in
            var sql = "SELECT * FROM memories ORDER BY captured_at_ms IS NULL, captured_at_ms DESC, rowid DESC"
            if let limit { sql += " LIMIT \(max(0, limit))" }
            return try Row.fetchAll(db, sql: sql).map(Self.record(from:))
        }
    }

    public func query(_ query: String, limit: Int) async throws -> [MemoryCandidate] {
        let terms = SearchFolding.queryTerms(query)
        guard !terms.isEmpty, limit > 0 else { return [] }
        // Terms contain only letters/digits after folding, so quoting is safe.
        let pattern = terms.map { "\"\($0)\"*" }.joined(separator: " OR ")
        let records = try await dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT memories.* FROM memories
                    JOIN memories_fts ON memories_fts.rowid = memories.rowid
                    WHERE memories_fts MATCH ? AND memories.source != ?
                    ORDER BY bm25(memories_fts) LIMIT ?
                    """,
                arguments: [pattern, MemorySource.sampleFixture.rawValue, limit]
            ).map(Self.record(from:))
        }
        let candidates = records.map {
            MemoryCandidate(record: $0, matchedTerms: SearchFolding.matchedTerms(terms, in: $0.currentText))
        }
        // More matched terms first; ties keep FTS rank order (sort is stable on enumerated index).
        return candidates.enumerated()
            .sorted { ($0.element.matchedTerms.count, -$0.offset) > ($1.element.matchedTerms.count, -$1.offset) }
            .map(\.element)
    }

    public func update(id: UUID, currentText: String) async throws -> MemoryRecord {
        let date = Self.truncatedToMilliseconds(now())
        return try await dbQueue.write { db in
            guard let existing = try Self.fetch(id, db) else { throw MemoryStoreError.notFound(id) }
            let corrected = try existing.correcting(to: currentText, at: date)
            try db.execute(
                sql: """
                    UPDATE memories SET current_text = ?, updated_at_ms = ?, user_edited = 1, search_text = ?
                    WHERE id = ?
                    """,
                arguments: [
                    corrected.currentText, Self.milliseconds(date), SearchFolding.fold(corrected.currentText),
                    id.uuidString,
                ])
            guard try Self.fetch(id, db) == corrected else { throw MemoryStoreError.verificationFailed }
            return corrected
        }
    }

    public func delete(id: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM memories WHERE id = ?", arguments: [id.uuidString])
            guard db.changesCount > 0 else { throw MemoryStoreError.notFound(id) }
        }
    }

    public func deleteAll() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM memories")
            try db.execute(sql: "INSERT INTO memories_fts(memories_fts) VALUES('rebuild')")
        }
    }

    public func export() async throws -> Data {
        try MemoryExport.json(try await list(limit: nil), exportedAt: now())
    }

    // MARK: Helpers

    private static func fetch(_ id: UUID, _ db: Database) throws -> MemoryRecord? {
        try Row.fetchOne(db, sql: "SELECT * FROM memories WHERE id = ?", arguments: [id.uuidString])
            .map(record(from:))
    }

    private static func record(from row: Row) throws -> MemoryRecord {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString),
              let source = MemorySource(rawValue: row["source"]),
              let category = MemoryCategory(rawValue: row["category"])
        else { throw MemoryStoreError.corruptRecord(idString) }
        func date(_ column: String) -> Date? {
            (row[column] as Int64?).map { Date(timeIntervalSince1970: Double($0) / 1000) }
        }
        do {
            return try MemoryRecord(
                id: id, rawText: row["raw_text"], currentText: row["current_text"], source: source,
                category: category, capturedAt: date("captured_at_ms"), updatedAt: date("updated_at_ms"),
                userEdited: row["user_edited"])
        } catch {
            throw MemoryStoreError.corruptRecord(idString)
        }
    }

    private static func milliseconds(_ date: Date) -> Int64 { DoddyDatabase.milliseconds(date) }

    private static func truncatedToMilliseconds(_ date: Date) -> Date { DoddyDatabase.truncatedToMilliseconds(date) }
}
