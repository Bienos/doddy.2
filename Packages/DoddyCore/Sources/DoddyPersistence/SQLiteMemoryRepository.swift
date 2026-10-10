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

    /// How many of the newest notes the word-rule scan reads when the index finds too few.
    /// A personal store stays far below this; past it, older notes rely on the index alone.
    static let scanLimit = 5_000

    public func query(_ query: String, limit: Int) async throws -> [MemoryCandidate] {
        let terms = RecallMatching.terms(query)
        guard let pattern = RecallMatching.ftsPattern(terms), limit > 0 else { return [] }
        let sample = MemorySource.sampleFixture.rawValue
        // Each row comes with its stored folded text, so matching doesn't fold every note again.
        let (indexed, scanned) = try await dbQueue.read { db -> ([Hit], [Hit]) in
            let indexed = try Row.fetchAll(
                db,
                sql: """
                    SELECT memories.* FROM memories
                    JOIN memories_fts ON memories_fts.rowid = memories.rowid
                    WHERE memories_fts MATCH ? AND memories.source != ?
                    ORDER BY bm25(memories_fts) LIMIT ?
                    """,
                arguments: [pattern, sample, limit]
            ).map(Self.hit)
            // Typos and spoken numbers can't be expressed as FTS terms, so when the index finds
            // fewer than asked, the newest notes are also checked with the same word rules.
            guard indexed.count < limit else { return (indexed, []) }
            let scanned = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM memories WHERE source != ?
                    ORDER BY captured_at_ms IS NULL, captured_at_ms DESC, rowid DESC LIMIT ?
                    """,
                arguments: [sample, Self.scanLimit]
            ).map(Self.hit)
            return (indexed, scanned)
        }
        var seen = Set<UUID>()
        let matcher = RecallMatching.Matcher(terms)
        // Index hits keep their rank order; scan hits follow, newest first.
        let candidates = (indexed + scanned).compactMap { hit -> MemoryCandidate? in
            guard seen.insert(hit.record.id).inserted else { return nil }
            let matched = matcher.matchedWords(inFolded: hit.folded)
            return matched.isEmpty ? nil : MemoryCandidate(record: hit.record, matchedTerms: matched)
        }
        // More matched words first; ties keep the order above (sort is stable on the index).
        return Array(candidates.enumerated()
            .sorted { ($0.element.matchedTerms.count, -$0.offset) > ($1.element.matchedTerms.count, -$1.offset) }
            .map(\.element)
            .prefix(limit))
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
            // The meaning-search vector of the old words goes too (ADR-210); the next search
            // embeds the corrected text.
            try db.execute(sql: "DELETE FROM memory_vectors WHERE memory_id = ?", arguments: [id.uuidString])
            guard try Self.fetch(id, db) == corrected else { throw MemoryStoreError.verificationFailed }
            return corrected
        }
    }

    public func setCategory(id: UUID, to category: MemoryCategory) async throws -> MemoryRecord {
        try await dbQueue.write { db in
            guard let existing = try Self.fetch(id, db) else { throw MemoryStoreError.notFound(id) }
            let changed = try existing.recategorized(to: category)
            try db.execute(sql: "UPDATE memories SET category = ? WHERE id = ?", arguments: [category.rawValue, id.uuidString])
            guard try Self.fetch(id, db) == changed else { throw MemoryStoreError.verificationFailed }
            return changed
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

    public func restore(_ records: [MemoryRecord]) async throws -> [MemoryRecord] {
        try await dbQueue.write { db in
            var added: [MemoryRecord] = []
            for record in records where record.source != .sampleFixture {
                try db.execute(
                    sql: """
                        INSERT INTO memories (id, raw_text, current_text, category, source, captured_at_ms,
                                              updated_at_ms, user_edited, search_text, schema_version)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO NOTHING
                        """,
                    arguments: [
                        record.id.uuidString, record.rawText, record.currentText, record.category.rawValue,
                        record.source.rawValue, record.capturedAt.map(Self.exportedMilliseconds),
                        record.updatedAt.map(Self.exportedMilliseconds), record.userEdited,
                        SearchFolding.fold(record.currentText), MemoryRecord.schemaVersion,
                    ])
                guard db.changesCount > 0 else { continue }
                // Throwing here rolls the whole transaction back: nothing from the file is kept.
                guard try Self.fetch(record.id, db) == record else { throw MemoryStoreError.verificationFailed }
                added.append(record)
            }
            return added
        }
    }

    // MARK: Helpers

    private typealias Hit = (record: MemoryRecord, folded: String)

    private static func hit(_ row: Row) throws -> Hit {
        (try record(from: row), row["search_text"])
    }

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

    /// Restored dates were read from whole milliseconds, which `MemoryExport` wrote by rounding;
    /// rounding again is the exact inverse.
    private static func exportedMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
