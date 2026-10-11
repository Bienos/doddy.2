import DoddyCore
import Foundation
import GRDB

/// Learned facts (ADR-440) in the one local SQLite file. Every write is one transaction and is
/// read back before success; the FTS5 index follows the table by triggers in that transaction.
public final class SQLiteLearnedFactRepository: LearnedFactRepository {
    private let dbQueue: DatabaseQueue
    private let now: @Sendable () -> Date

    public init(database: DoddyDatabase, now: @escaping @Sendable () -> Date = Date.init) {
        self.dbQueue = database.queue
        self.now = now
    }

    public func propose(_ proposal: ValidatedProposal) async throws -> LearnedFact {
        guard case .fact(let draft) = proposal.proposal else { throw LearningStoreError.wrongProposalKind }
        let date = DoddyDatabase.truncatedToMilliseconds(now())
        let fact = try LearnedFact(
            id: UUID(), kind: draft.kind, value: draft.value, scope: draft.scope, confidence: draft.confidence,
            provenance: draft.provenance, sourceEpisodeIDs: draft.sourceEpisodeIDs, status: .proposed,
            createdAt: date, updatedAt: date, expiresAt: nil, confirmedAt: nil)
        return try await dbQueue.write { db in
            let taken = try Int.fetchOne(
                db, sql: "SELECT count(*) FROM learned_facts WHERE evidence_digest = ?", arguments: [fact.evidenceDigest]) ?? 0
            guard taken == 0 else { throw LearningStoreError.duplicateEvidence }
            try db.execute(
                sql: """
                    INSERT INTO learned_facts (id, kind, value, search_text, scope, confidence, provenance_json,
                        source_episode_ids_json, evidence_digest, status, created_at_ms, updated_at_ms,
                        expires_at_ms, confirmed_at_ms, schema_version)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: try Self.arguments(fact))
            guard try Self.fetch(fact.id, db) == fact else { throw LearningStoreError.verificationFailed }
            return fact
        }
    }

    public func confirm(id: UUID, exactText: String) async throws -> LearnedFact {
        let date = DoddyDatabase.truncatedToMilliseconds(now())
        return try await dbQueue.write { db in
            let existing = try Self.require(id, db)
            guard existing.status == .proposed else { throw LearningStoreError.notProposed(id) }
            guard existing.value == exactText else { throw LearningStoreError.textMismatch }
            let confirmed = try existing.confirmed(at: date)
            try Self.update(confirmed, db)
            try Self.insertRevision(LearnedFactRevision(factID: id, number: 1, value: confirmed.value, confirmedAt: date), db)
            guard try Self.fetch(id, db) == confirmed, try Self.revisions(id, db).count == 1 else {
                throw LearningStoreError.verificationFailed
            }
            return confirmed
        }
    }

    public func reject(id: UUID) async throws -> LearnedFact {
        try await transition(id, from: .proposed, to: .rejected)
    }

    public func retire(id: UUID) async throws -> LearnedFact {
        try await transition(id, from: .confirmed, to: .retired)
    }

    public func reconfirm(id: UUID) async throws -> LearnedFact {
        let date = DoddyDatabase.truncatedToMilliseconds(now())
        return try await dbQueue.write { db in
            let existing = try Self.require(id, db)
            guard existing.status == .confirmed else { throw LearningStoreError.wrongStatus(id, existing.status) }
            let fresh = try existing.confirmed(at: date)
            try Self.update(fresh, db)
            guard try Self.fetch(id, db) == fresh else { throw LearningStoreError.verificationFailed }
            return fresh
        }
    }

    public func revise(id: UUID, value: String) async throws -> LearnedFact {
        let date = DoddyDatabase.truncatedToMilliseconds(now())
        return try await dbQueue.write { db in
            let existing = try Self.require(id, db)
            guard existing.status == .confirmed else { throw LearningStoreError.wrongStatus(id, existing.status) }
            let revised = try existing.changing(value: value, at: date).confirmed(at: date)
            let number = try Self.revisions(id, db).count + 1
            try Self.update(revised, db)
            try Self.insertRevision(LearnedFactRevision(factID: id, number: number, value: revised.value, confirmedAt: date), db)
            guard try Self.fetch(id, db) == revised, try Self.revisions(id, db).count == number else {
                throw LearningStoreError.verificationFailed
            }
            return revised
        }
    }

    public func revisions(of id: UUID) async throws -> [LearnedFactRevision] {
        try await dbQueue.read { db in try Self.revisions(id, db) }
    }

    public func fact(id: UUID) async throws -> LearnedFact? {
        try await dbQueue.read { db in try Self.fetch(id, db) }
    }

    public func list(status: LearningStatus?) async throws -> [LearnedFact] {
        try await dbQueue.read { db in
            if let status {
                return try Row.fetchAll(
                    db, sql: "SELECT * FROM learned_facts WHERE status = ? ORDER BY created_at_ms DESC, rowid DESC",
                    arguments: [status.rawValue]
                ).map(Self.record(from:))
            }
            return try Row.fetchAll(db, sql: "SELECT * FROM learned_facts ORDER BY created_at_ms DESC, rowid DESC")
                .map(Self.record(from:))
        }
    }

    public func query(_ query: String, limit: Int) async throws -> [LearnedFact] {
        let terms = RecallMatching.terms(query)
        guard let pattern = RecallMatching.ftsPattern(terms), limit > 0 else { return [] }
        let nowMs = DoddyDatabase.milliseconds(now())
        let hits = try await dbQueue.read { db -> [(LearnedFact, String)] in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT learned_facts.* FROM learned_facts
                    JOIN learned_facts_fts ON learned_facts_fts.rowid = learned_facts.rowid
                    WHERE learned_facts_fts MATCH ? AND learned_facts.status = ?
                      AND (learned_facts.expires_at_ms IS NULL OR learned_facts.expires_at_ms > ?)
                    ORDER BY bm25(learned_facts_fts) LIMIT ?
                    """,
                arguments: [pattern, LearningStatus.confirmed.rawValue, nowMs, limit]
            ).map { (try Self.record(from: $0), $0["search_text"]) }
        }
        // The index matches every prefix; the word rules are stricter ("car" vs "card").
        let matched = RecallMatching.Matcher(terms).matchedWords(inFolded: hits.map(\.1))
        return zip(hits, matched).compactMap { hit, words in words.isEmpty ? nil : hit.0 }
    }

    public func knownDigests() async throws -> Set<String> {
        try await dbQueue.read { db in Set(try String.fetchAll(db, sql: "SELECT evidence_digest FROM learned_facts")) }
    }

    public func pruneProposals(olderThan date: Date) async throws -> Int {
        try await dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM learned_facts WHERE status = ? AND created_at_ms < ?",
                arguments: [LearningStatus.proposed.rawValue, DoddyDatabase.milliseconds(date)])
            return db.changesCount
        }
    }

    public func delete(id: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM learned_facts WHERE id = ?", arguments: [id.uuidString])
            guard db.changesCount > 0 else { throw LearningStoreError.notFound(id) }
        }
    }

    public func deleteAll() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM learned_facts")
            try db.execute(sql: "INSERT INTO learned_facts_fts(learned_facts_fts) VALUES('rebuild')")
        }
    }

    public func export() async throws -> Data {
        let exportedAt = now()
        return try await dbQueue.read { db in
            let facts = try Row.fetchAll(db, sql: "SELECT * FROM learned_facts ORDER BY created_at_ms, rowid").map(Self.record(from:))
            let revisions = try Row.fetchAll(db, sql: "SELECT * FROM learned_fact_revisions ORDER BY fact_id, number").map(Self.revision(from:))
            return try LearningJSON.encoder().encode(LearnedFactExport(
                schemaVersion: LearnedFact.schemaVersion, exportedAt: exportedAt,
                facts: facts.map(LearnedFactExport.Fact.init), revisions: revisions.map(LearnedFactExport.Revision.init)))
        }
    }

    // MARK: Helpers

    private func transition(_ id: UUID, from: LearningStatus, to: LearningStatus) async throws -> LearnedFact {
        let date = DoddyDatabase.truncatedToMilliseconds(now())
        return try await dbQueue.write { db in
            let existing = try Self.require(id, db)
            guard existing.status == from else {
                throw from == .proposed ? LearningStoreError.notProposed(id) : LearningStoreError.wrongStatus(id, existing.status)
            }
            let changed = try existing.changing(status: to, confirmedAt: .some(nil), at: date)
            try Self.update(changed, db)
            guard try Self.fetch(id, db) == changed else { throw LearningStoreError.verificationFailed }
            return changed
        }
    }

    private static func require(_ id: UUID, _ db: Database) throws -> LearnedFact {
        guard let fact = try fetch(id, db) else { throw LearningStoreError.notFound(id) }
        return fact
    }

    private static func fetch(_ id: UUID, _ db: Database) throws -> LearnedFact? {
        try Row.fetchOne(db, sql: "SELECT * FROM learned_facts WHERE id = ?", arguments: [id.uuidString]).map(record(from:))
    }

    private static func update(_ fact: LearnedFact, _ db: Database) throws {
        try db.execute(
            sql: """
                UPDATE learned_facts SET value = ?, search_text = ?, status = ?, updated_at_ms = ?,
                    expires_at_ms = ?, confirmed_at_ms = ?
                WHERE id = ?
                """,
            arguments: [
                fact.value, SearchFolding.fold(fact.value), fact.status.rawValue, DoddyDatabase.milliseconds(fact.updatedAt),
                fact.expiresAt.map(DoddyDatabase.milliseconds), fact.confirmedAt.map(DoddyDatabase.milliseconds), fact.id.uuidString,
            ])
    }

    private static func arguments(_ fact: LearnedFact) throws -> StatementArguments {
        [
            fact.id.uuidString, fact.kind.rawValue, fact.value, SearchFolding.fold(fact.value), fact.scope.rawValue,
            fact.confidence, try LearningRows.json(fact.provenance), try LearningRows.json(fact.sourceEpisodeIDs),
            fact.evidenceDigest, fact.status.rawValue, DoddyDatabase.milliseconds(fact.createdAt),
            DoddyDatabase.milliseconds(fact.updatedAt), fact.expiresAt.map(DoddyDatabase.milliseconds),
            fact.confirmedAt.map(DoddyDatabase.milliseconds), LearnedFact.schemaVersion,
        ]
    }

    private static func record(from row: Row) throws -> LearnedFact {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString),
              let kind = LearnedFactKind(rawValue: row["kind"]),
              let scope = LearningScope(rawValue: row["scope"]),
              let status = LearningStatus(rawValue: row["status"])
        else { throw LearningStoreError.corruptRecord(idString) }
        let expires: Int64? = row["expires_at_ms"]
        let confirmed: Int64? = row["confirmed_at_ms"]
        do {
            // The domain rules are re-checked on read; a row that breaks them is reported, not shown.
            let fact = try LearnedFact(
                id: id, kind: kind, value: row["value"], scope: scope, confidence: row["confidence"],
                provenance: try LearningRows.decode(LearningProvenance.self, row["provenance_json"]),
                sourceEpisodeIDs: try LearningRows.decode([String].self, row["source_episode_ids_json"]),
                status: status, createdAt: DoddyDatabase.date(milliseconds: row["created_at_ms"]),
                updatedAt: DoddyDatabase.date(milliseconds: row["updated_at_ms"]),
                expiresAt: expires.map(DoddyDatabase.date(milliseconds:)),
                confirmedAt: confirmed.map(DoddyDatabase.date(milliseconds:)))
            guard fact.evidenceDigest == (row["evidence_digest"] as String) else { throw LearningStoreError.corruptRecord(idString) }
            return fact
        } catch {
            throw LearningStoreError.corruptRecord(idString)
        }
    }

    private static func revisions(_ id: UUID, _ db: Database) throws -> [LearnedFactRevision] {
        try Row.fetchAll(
            db, sql: "SELECT * FROM learned_fact_revisions WHERE fact_id = ? ORDER BY number", arguments: [id.uuidString]
        ).map(revision(from:))
    }

    private static func revision(from row: Row) throws -> LearnedFactRevision {
        let idString: String = row["fact_id"]
        guard let id = UUID(uuidString: idString) else { throw LearningStoreError.corruptRecord(idString) }
        return LearnedFactRevision(
            factID: id, number: row["number"], value: row["value"],
            confirmedAt: DoddyDatabase.date(milliseconds: row["confirmed_at_ms"]))
    }

    private static func insertRevision(_ revision: LearnedFactRevision, _ db: Database) throws {
        try db.execute(
            sql: "INSERT INTO learned_fact_revisions (fact_id, number, value, confirmed_at_ms) VALUES (?, ?, ?, ?)",
            arguments: [revision.factID.uuidString, revision.number, revision.value, DoddyDatabase.milliseconds(revision.confirmedAt)])
    }
}

enum LearningRows {
    static func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try LearningJSON.encoder().encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try LearningJSON.decoder().decode(type, from: Data(json.utf8))
    }
}

/// The export file: every fact with its provenance and every confirmed wording.
struct LearnedFactExport: Encodable {
    struct Fact: Encodable {
        let id: UUID
        let kind: LearnedFactKind
        let value: String
        let scope: LearningScope
        let confidence: Int
        let provenance: LearningProvenance
        let sourceEpisodeIDs: [String]
        let evidenceDigest: String
        let status: LearningStatus
        let createdAt: Date
        let updatedAt: Date
        let expiresAt: Date?
        let confirmedAt: Date?

        init(_ fact: LearnedFact) {
            id = fact.id; kind = fact.kind; value = fact.value; scope = fact.scope; confidence = fact.confidence
            provenance = fact.provenance; sourceEpisodeIDs = fact.sourceEpisodeIDs; evidenceDigest = fact.evidenceDigest
            status = fact.status; createdAt = fact.createdAt; updatedAt = fact.updatedAt
            expiresAt = fact.expiresAt; confirmedAt = fact.confirmedAt
        }
    }

    struct Revision: Encodable {
        let factID: UUID
        let number: Int
        let value: String
        let confirmedAt: Date

        init(_ revision: LearnedFactRevision) {
            factID = revision.factID; number = revision.number; value = revision.value; confirmedAt = revision.confirmedAt
        }
    }

    let schemaVersion: Int
    let exportedAt: Date
    let facts: [Fact]
    let revisions: [Revision]
}
