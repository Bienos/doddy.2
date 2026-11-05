import DoddyCore
import Foundation
import GRDB

/// Procedures (ADR-440): saved plan templates. The steps are JSON validated on every read by
/// `ProcedureStep`; a tool outside the plan allowlist makes the row corrupt, not runnable, and
/// no column holds an approval.
public final class SQLiteProcedureRepository: ProcedureRepository {
    private let dbQueue: DatabaseQueue
    private let now: @Sendable () -> Date

    public init(database: DoddyDatabase, now: @escaping @Sendable () -> Date = Date.init) {
        self.dbQueue = database.queue
        self.now = now
    }

    public func propose(_ proposal: ValidatedProposal) async throws -> Procedure {
        guard case .procedure(let draft) = proposal.proposal else { throw LearningStoreError.wrongProposalKind }
        let date = DoddyDatabase.truncatedToMilliseconds(now())
        let procedure = try Procedure(
            id: UUID(), triggerText: draft.triggerText, steps: draft.steps, version: 1, scope: draft.scope,
            status: .proposed, provenance: draft.provenance, sourceEpisodeIDs: draft.sourceEpisodeIDs,
            createdAt: date, updatedAt: date, confirmedAt: nil, lastUsedAt: nil, useCount: 0)
        return try await dbQueue.write { db in
            let taken = try Int.fetchOne(
                db, sql: "SELECT count(*) FROM procedures WHERE evidence_digest = ?", arguments: [procedure.evidenceDigest]) ?? 0
            guard taken == 0 else { throw LearningStoreError.duplicateEvidence }
            try db.execute(
                sql: """
                    INSERT INTO procedures (id, trigger_text, search_text, steps_json, version, scope, status,
                        provenance_json, source_episode_ids_json, evidence_digest, created_at_ms, updated_at_ms,
                        confirmed_at_ms, last_used_at_ms, use_count, schema_version)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    procedure.id.uuidString, procedure.triggerText, SearchFolding.fold(procedure.triggerText),
                    try LearningRows.json(procedure.steps), procedure.version, procedure.scope.rawValue,
                    procedure.status.rawValue, try LearningRows.json(procedure.provenance),
                    try LearningRows.json(procedure.sourceEpisodeIDs), procedure.evidenceDigest,
                    DoddyDatabase.milliseconds(procedure.createdAt), DoddyDatabase.milliseconds(procedure.updatedAt),
                    nil, nil, 0, Procedure.schemaVersion,
                ])
            guard try Self.fetch(procedure.id, db) == procedure else { throw LearningStoreError.verificationFailed }
            return procedure
        }
    }

    public func confirm(id: UUID, exactTrigger: String) async throws -> Procedure {
        let date = DoddyDatabase.truncatedToMilliseconds(now())
        return try await dbQueue.write { db in
            let existing = try Self.require(id, db)
            guard existing.status == .proposed else { throw LearningStoreError.notProposed(id) }
            guard existing.triggerText == exactTrigger else { throw LearningStoreError.textMismatch }
            return try Self.store(existing.changing(status: .confirmed, confirmedAt: .some(date), at: date), db)
        }
    }

    public func reject(id: UUID) async throws -> Procedure {
        try await transition(id) { existing, date in
            guard existing.status == .proposed else { throw LearningStoreError.notProposed(id) }
            return try existing.changing(status: .rejected, at: date)
        }
    }

    public func retire(id: UUID) async throws -> Procedure {
        try await transition(id) { existing, date in
            guard existing.status == .confirmed else { throw LearningStoreError.wrongStatus(id, existing.status) }
            return try existing.changing(status: .retired, confirmedAt: .some(nil), at: date)
        }
    }

    public func revive(id: UUID) async throws -> Procedure {
        try await transition(id) { existing, date in
            guard existing.status == .retired else { throw LearningStoreError.wrongStatus(id, existing.status) }
            return try existing.changing(status: .confirmed, confirmedAt: .some(date), lastUsedAt: .some(date), at: date)
        }
    }

    public func update(id: UUID, triggerText: String, steps: [ProcedureStep]) async throws -> Procedure {
        try await transition(id, rewritesText: true) { existing, date in
            guard existing.status == .confirmed else { throw LearningStoreError.wrongStatus(id, existing.status) }
            return try existing.changing(triggerText: triggerText, steps: steps, version: existing.version + 1, at: date)
        }
    }

    public func markUsed(id: UUID) async throws -> Procedure {
        try await transition(id) { existing, date in
            guard existing.status == .confirmed else { throw LearningStoreError.wrongStatus(id, existing.status) }
            return try existing.changing(lastUsedAt: .some(date), useCount: existing.useCount + 1, at: date)
        }
    }

    public func procedure(id: UUID) async throws -> Procedure? {
        try await dbQueue.read { db in try Self.fetch(id, db) }
    }

    public func list(status: LearningStatus?) async throws -> [Procedure] {
        try await dbQueue.read { db in
            if let status {
                return try Row.fetchAll(
                    db, sql: "SELECT * FROM procedures WHERE status = ? ORDER BY created_at_ms DESC, rowid DESC",
                    arguments: [status.rawValue]
                ).map(Self.record(from:))
            }
            return try Row.fetchAll(db, sql: "SELECT * FROM procedures ORDER BY created_at_ms DESC, rowid DESC").map(Self.record(from:))
        }
    }

    public func query(_ query: String, limit: Int) async throws -> [Procedure] {
        let terms = RecallMatching.terms(query)
        guard let pattern = RecallMatching.ftsPattern(terms), limit > 0 else { return [] }
        let hits = try await dbQueue.read { db -> [(Procedure, String)] in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT procedures.* FROM procedures
                    JOIN procedures_fts ON procedures_fts.rowid = procedures.rowid
                    WHERE procedures_fts MATCH ? AND procedures.status = ?
                    ORDER BY bm25(procedures_fts) LIMIT ?
                    """,
                arguments: [pattern, LearningStatus.confirmed.rawValue, limit]
            ).map { (try Self.record(from: $0), $0["search_text"]) }
        }
        let matched = RecallMatching.Matcher(terms).matchedWords(inFolded: hits.map(\.1))
        return zip(hits, matched).compactMap { hit, words in words.isEmpty ? nil : hit.0 }
    }

    public func retireUnused(since before: Date) async throws -> [Procedure] {
        let date = DoddyDatabase.truncatedToMilliseconds(now())
        return try await dbQueue.write { db in
            let stale = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM procedures WHERE status = ?
                      AND COALESCE(last_used_at_ms, confirmed_at_ms) < ?
                    ORDER BY created_at_ms, rowid
                    """,
                arguments: [LearningStatus.confirmed.rawValue, DoddyDatabase.milliseconds(before)]
            ).map(Self.record(from:))
            var retired: [Procedure] = []
            for procedure in stale {
                retired.append(try Self.store(procedure.changing(status: .retired, confirmedAt: .some(nil), at: date), db))
            }
            return retired
        }
    }

    public func knownDigests() async throws -> Set<String> {
        try await dbQueue.read { db in Set(try String.fetchAll(db, sql: "SELECT evidence_digest FROM procedures")) }
    }

    public func pruneProposals(olderThan date: Date) async throws -> Int {
        try await dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM procedures WHERE status = ? AND created_at_ms < ?",
                arguments: [LearningStatus.proposed.rawValue, DoddyDatabase.milliseconds(date)])
            let removed = db.changesCount  // before the index statement below replaces it
            try DoddyDatabase.compactSearchIndex("procedures_fts", in: db)
            return removed
        }
    }

    public func delete(id: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM procedures WHERE id = ?", arguments: [id.uuidString])
            guard db.changesCount > 0 else { throw LearningStoreError.notFound(id) }
            try DoddyDatabase.compactSearchIndex("procedures_fts", in: db)
        }
    }

    public func deleteAll() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM procedures")
            try db.execute(sql: "INSERT INTO procedures_fts(procedures_fts) VALUES('rebuild')")
            try DoddyDatabase.compactSearchIndex("procedures_fts", in: db)
        }
    }

    public func export() async throws -> Data {
        let exportedAt = now()
        return try await dbQueue.read { db in
            let procedures = try Row.fetchAll(db, sql: "SELECT * FROM procedures ORDER BY created_at_ms, rowid").map(Self.record(from:))
            return try LearningJSON.encoder().encode(ProcedureExport(
                schemaVersion: Procedure.schemaVersion, exportedAt: exportedAt, procedures: procedures.map(ProcedureExport.Item.init)))
        }
    }

    // MARK: Helpers

    /// `rewritesText`: the change replaces the trigger text, so the index is merged (ADR-584).
    private func transition(
        _ id: UUID, rewritesText: Bool = false, _ change: @escaping @Sendable (Procedure, Date) throws -> Procedure
    ) async throws -> Procedure {
        let date = DoddyDatabase.truncatedToMilliseconds(now())
        return try await dbQueue.write { db in
            try Self.store(change(try Self.require(id, db), date), rewritesText: rewritesText, db)
        }
    }

    /// Writes every changeable column, then reads the row back; returns what was read.
    private static func store(_ procedure: Procedure, rewritesText: Bool = false, _ db: Database) throws -> Procedure {
        try db.execute(
            sql: """
                UPDATE procedures SET trigger_text = ?, search_text = ?, steps_json = ?, version = ?, status = ?,
                    updated_at_ms = ?, confirmed_at_ms = ?, last_used_at_ms = ?, use_count = ?
                WHERE id = ?
                """,
            arguments: [
                procedure.triggerText, SearchFolding.fold(procedure.triggerText), try LearningRows.json(procedure.steps),
                procedure.version, procedure.status.rawValue, DoddyDatabase.milliseconds(procedure.updatedAt),
                procedure.confirmedAt.map(DoddyDatabase.milliseconds), procedure.lastUsedAt.map(DoddyDatabase.milliseconds),
                procedure.useCount, procedure.id.uuidString,
            ])
        if rewritesText { try DoddyDatabase.compactSearchIndex("procedures_fts", in: db) }
        guard try fetch(procedure.id, db) == procedure else { throw LearningStoreError.verificationFailed }
        return procedure
    }

    private static func require(_ id: UUID, _ db: Database) throws -> Procedure {
        guard let procedure = try fetch(id, db) else { throw LearningStoreError.notFound(id) }
        return procedure
    }

    private static func fetch(_ id: UUID, _ db: Database) throws -> Procedure? {
        try Row.fetchOne(db, sql: "SELECT * FROM procedures WHERE id = ?", arguments: [id.uuidString]).map(record(from:))
    }

    private static func record(from row: Row) throws -> Procedure {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString),
              let scope = LearningScope(rawValue: row["scope"]),
              let status = LearningStatus(rawValue: row["status"])
        else { throw LearningStoreError.corruptRecord(idString) }
        let confirmed: Int64? = row["confirmed_at_ms"]
        let lastUsed: Int64? = row["last_used_at_ms"]
        do {
            let procedure = try Procedure(
                id: id, triggerText: row["trigger_text"],
                steps: try LearningRows.decode([ProcedureStep].self, row["steps_json"]),
                version: row["version"], scope: scope, status: status,
                provenance: try LearningRows.decode(LearningProvenance.self, row["provenance_json"]),
                sourceEpisodeIDs: try LearningRows.decode([String].self, row["source_episode_ids_json"]),
                createdAt: DoddyDatabase.date(milliseconds: row["created_at_ms"]),
                updatedAt: DoddyDatabase.date(milliseconds: row["updated_at_ms"]),
                confirmedAt: confirmed.map(DoddyDatabase.date(milliseconds:)),
                lastUsedAt: lastUsed.map(DoddyDatabase.date(milliseconds:)), useCount: row["use_count"])
            guard procedure.evidenceDigest == (row["evidence_digest"] as String) else { throw LearningStoreError.corruptRecord(idString) }
            return procedure
        } catch {
            throw LearningStoreError.corruptRecord(idString)
        }
    }
}

struct ProcedureExport: Encodable {
    struct Item: Encodable {
        let id: UUID
        let triggerText: String
        let steps: [ProcedureStep]
        let version: Int
        let scope: LearningScope
        let status: LearningStatus
        let provenance: LearningProvenance
        let sourceEpisodeIDs: [String]
        let evidenceDigest: String
        let createdAt: Date
        let updatedAt: Date
        let confirmedAt: Date?
        let lastUsedAt: Date?
        let useCount: Int

        init(_ p: Procedure) {
            id = p.id; triggerText = p.triggerText; steps = p.steps; version = p.version; scope = p.scope; status = p.status
            provenance = p.provenance; sourceEpisodeIDs = p.sourceEpisodeIDs; evidenceDigest = p.evidenceDigest
            createdAt = p.createdAt; updatedAt = p.updatedAt; confirmedAt = p.confirmedAt; lastUsedAt = p.lastUsedAt
            useCount = p.useCount
        }
    }

    let schemaVersion: Int
    let exportedAt: Date
    let procedures: [Item]
}
