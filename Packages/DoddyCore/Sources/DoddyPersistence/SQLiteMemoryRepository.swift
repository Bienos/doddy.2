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
        try await dbQueue.read { db in try Self.allRecords(db, limit: limit) }
    }

    private static func allRecords(_ db: Database, limit: Int? = nil) throws -> [MemoryRecord] {
        var sql = "SELECT * FROM memories ORDER BY captured_at_ms IS NULL, captured_at_ms DESC, rowid DESC"
        if let limit { sql += " LIMIT \(max(0, limit))" }
        return try Row.fetchAll(db, sql: sql).map(record(from:))
    }

    /// How many of the newest notes the word-rule scan reads when the index finds too few.
    /// A personal store stays far below this; past it, older notes rely on the index alone.
    static let scanLimit = 5_000

    public func query(_ query: String, limit: Int) async throws -> [MemoryCandidate] {
        let terms = RecallMatching.terms(query)
        guard let pattern = RecallMatching.ftsPattern(terms), limit > 0 else { return [] }
        let sample = MemorySource.sampleFixture.rawValue
        // Each row comes with its stored folded text, so matching doesn't fold every note again.
        let hits = try await dbQueue.read { db -> [Hit] in
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
            // The index matches every prefix and the rules are stricter ("car" vs "card"), so
            // only index hits the rules accept count.
            let accepted = RecallMatching.Matcher(terms).matchedWords(inFolded: indexed.map(\.folded))
            guard accepted.filter({ !$0.isEmpty }).count < limit else { return indexed }
            let scanned = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM memories WHERE source != ?
                    ORDER BY captured_at_ms IS NULL, captured_at_ms DESC, rowid DESC LIMIT ?
                    """,
                arguments: [sample, Self.scanLimit]
            ).map(Self.hit)
            return indexed + scanned
        }
        // Index hits keep their rank order; scan hits follow, newest first. All notes read are
        // judged together, so a two-letter typo only counts when no note has the word as typed.
        var seen = Set<UUID>()
        let unique = hits.filter { seen.insert($0.record.id).inserted }
        let matched = RecallMatching.Matcher(terms).matchedWords(inFolded: unique.map(\.folded))
        let candidates = zip(unique, matched).compactMap { hit, words -> MemoryCandidate? in
            words.isEmpty ? nil : MemoryCandidate(record: hit.record, matchedTerms: words)
        }
        // More matched words first; ties keep the order above (sort is stable on the index).
        return Array(candidates.enumerated()
            .sorted { ($0.element.matchedTerms.count, -$0.offset) > ($1.element.matchedTerms.count, -$1.offset) }
            .map(\.element)
            .prefix(limit))
    }

    /// Changes the wording and keeps it as the note's next correction (ADR-252), in one
    /// transaction: both are read back before success, or neither is kept.
    public func update(id: UUID, currentText: String) async throws -> MemoryRecord {
        let date = Self.truncatedToMilliseconds(now())
        return try await dbQueue.write { db in
            guard let existing = try Self.fetch(id, db) else { throw MemoryStoreError.notFound(id) }
            let corrected = try existing.correcting(to: currentText, at: date)
            var earlier = try Self.corrections(id, db)
            if !existing.userEdited, !earlier.isEmpty {
                // Never corrected, so these rows can't be its history.
                try db.execute(sql: "DELETE FROM memory_corrections WHERE memory_id = ?", arguments: [id.uuidString])
                earlier = []
            } else if existing.userEdited, !MemoryHistory.consistent(existing, earlier) {
                // Corrected before history was kept, or restored from an export without it: keep
                // the wording it has now as its first correction, so no wording is lost. Rows that
                // don't end at the current wording are not its history and are replaced.
                try db.execute(sql: "DELETE FROM memory_corrections WHERE memory_id = ?", arguments: [id.uuidString])
                let seed = try MemoryCorrection(
                    memoryID: id, number: 1, text: existing.currentText, correctedAt: existing.updatedAt ?? date)
                try Self.insert(seed, db)
                earlier = [seed]
            }
            let correction = try MemoryCorrection(
                memoryID: id, number: earlier.count + 1, text: currentText, correctedAt: date)
            try Self.insert(correction, db)
            try db.execute(
                sql: """
                    UPDATE memories SET current_text = ?, updated_at_ms = ?, user_edited = 1, search_text = ?
                    WHERE id = ?
                    """,
                arguments: [
                    corrected.currentText, Self.milliseconds(date), SearchFolding.fold(corrected.currentText),
                    id.uuidString,
                ])
            guard try Self.fetch(id, db) == corrected, try Self.corrections(id, db).last == correction else {
                throw MemoryStoreError.verificationFailed
            }
            return corrected
        }
    }

    public func corrections(of id: UUID) async throws -> [MemoryCorrection] {
        try await dbQueue.read { db in
            guard try Self.fetch(id, db) != nil else { throw MemoryStoreError.notFound(id) }
            return try Self.corrections(id, db)
        }
    }

    public func allCorrections() async throws -> [MemoryCorrection] {
        try await dbQueue.read { db in try Self.allCorrections(db) }
    }

    private static func allCorrections(_ db: Database) throws -> [MemoryCorrection] {
        try Row.fetchAll(db, sql: "SELECT * FROM memory_corrections ORDER BY memory_id, number").map(correction(from:))
    }

    public func setCategory(id: UUID, to category: MemoryCategory) async throws -> MemoryRecord {
        try await dbQueue.write { db in
            guard let existing = try Self.fetch(id, db) else { throw MemoryStoreError.notFound(id) }
            // Lists have their own screens and items (ADR-216); the type picker never crosses over.
            guard category != .list, existing.category != .list else { throw ListError.notANote }
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
            // Read back before "deleted" is reported (DOD-06): no note, list item or correction left.
            for table in ["memories", "list_items", "memory_corrections"] {
                guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") == 0 else {
                    throw MemoryStoreError.verificationFailed
                }
            }
        }
    }

    /// Notes, list items and corrections from one read, so the file is one consistent snapshot.
    public func export() async throws -> Data {
        let (records, items, corrections) = try await dbQueue.read { db in
            (try Self.allRecords(db), try SQLiteListRepository.allItems(db), try Self.allCorrections(db))
        }
        return try MemoryExport.json(records, listItems: items, corrections: corrections, exportedAt: now())
    }

    public func restore(_ records: [MemoryRecord]) async throws -> [MemoryRecord] {
        try await restore(records, corrections: [])
    }

    /// Also adds each added note's corrections, when they form its whole history
    /// (`MemoryHistory.consistent`); otherwise the note is added without them. Notes already
    /// here keep their own history.
    public func restore(_ records: [MemoryRecord], corrections: [MemoryCorrection]) async throws -> [MemoryRecord] {
        try await dbQueue.write { db in try Self.restore(records, corrections: corrections, db) }
    }

    /// Notes, their corrections and the items of the lists among them in one transaction, so a
    /// failure anywhere keeps nothing from the file. Items of a list already here are not added.
    public func restore(
        _ records: [MemoryRecord], corrections: [MemoryCorrection], listItems: [ListItem]
    ) async throws -> (records: [MemoryRecord], listItems: [ListItem]) {
        try await dbQueue.write { db in
            let added = try Self.restore(records, corrections: corrections, db)
            let newLists = Set(added.filter { $0.category == .list }.map(\.id))
            let items = try SQLiteListRepository.restore(listItems.filter { newLists.contains($0.listID) }, db)
            return (added, items)
        }
    }

    private static func restore(_ records: [MemoryRecord], corrections: [MemoryCorrection], _ db: Database) throws -> [MemoryRecord] {
        let byNote = Dictionary(grouping: corrections, by: \.memoryID)
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
            let history = byNote[record.id] ?? []
            if MemoryHistory.consistent(record, history) {
                for correction in history { try Self.insert(correction, db) }
                guard try Self.corrections(record.id, db) == history.sorted(by: { $0.number < $1.number }) else {
                    throw MemoryStoreError.verificationFailed
                }
            }
            added.append(record)
        }
        return added
    }

    // MARK: Helpers

    private typealias Hit = (record: MemoryRecord, folded: String)

    private static func hit(_ row: Row) throws -> Hit {
        (try record(from: row), row["search_text"])
    }

    private static func corrections(_ id: UUID, _ db: Database) throws -> [MemoryCorrection] {
        try Row.fetchAll(
            db, sql: "SELECT * FROM memory_corrections WHERE memory_id = ? ORDER BY number", arguments: [id.uuidString]
        ).map(correction(from:))
    }

    private static func insert(_ correction: MemoryCorrection, _ db: Database) throws {
        try db.execute(
            sql: "INSERT INTO memory_corrections (memory_id, number, text, corrected_at_ms) VALUES (?, ?, ?, ?)",
            arguments: [correction.memoryID.uuidString, correction.number, correction.text,
                        exportedMilliseconds(correction.correctedAt)])
    }

    private static func correction(from row: Row) throws -> MemoryCorrection {
        let idString: String = row["memory_id"]
        guard let id = UUID(uuidString: idString) else { throw MemoryStoreError.corruptRecord(idString) }
        do {
            return try MemoryCorrection(
                memoryID: id, number: row["number"], text: row["text"],
                correctedAt: DoddyDatabase.date(milliseconds: row["corrected_at_ms"]))
        } catch {
            throw MemoryStoreError.corruptRecord(idString)
        }
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
