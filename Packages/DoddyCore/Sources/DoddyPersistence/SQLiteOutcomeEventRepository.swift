import DoddyCore
import Foundation
import GRDB

/// Outcome events (ADR-324): kinds and identifiers only, never user text, kept 90 days.
public final class SQLiteOutcomeEventRepository: OutcomeEventRepository {
    private let dbQueue: DatabaseQueue

    public init(database: DoddyDatabase) {
        self.dbQueue = database.queue
    }

    public func record(_ event: OutcomeEvent) async throws -> OutcomeEvent {
        try await dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO outcome_events (id, request_id, kind, detail_json, created_at_ms) VALUES (?, ?, ?, ?, ?)",
                arguments: [
                    event.id.uuidString, event.requestID, event.kind.rawValue, try LearningRows.json(event.detail),
                    DoddyDatabase.milliseconds(event.createdAt),
                ])
            let stored = try Row.fetchOne(db, sql: "SELECT * FROM outcome_events WHERE id = ?", arguments: [event.id.uuidString])
                .map(Self.record(from:))
            guard stored == event else { throw LearningStoreError.verificationFailed }
            return event
        }
    }

    public func list(since: Date, limit: Int) async throws -> [OutcomeEvent] {
        try await dbQueue.read { db in
            try Row.fetchAll(
                db, sql: "SELECT * FROM outcome_events WHERE created_at_ms >= ? ORDER BY created_at_ms, rowid LIMIT ?",
                arguments: [DoddyDatabase.milliseconds(since), max(0, limit)]
            ).map(Self.record(from:))
        }
    }

    public func count(kinds: Set<OutcomeKind>, since: Date) async throws -> Int {
        guard !kinds.isEmpty else { return 0 }
        let placeholders = Array(repeating: "?", count: kinds.count).joined(separator: ", ")
        let arguments = StatementArguments(kinds.map(\.rawValue).sorted() + [String(DoddyDatabase.milliseconds(since))])
        return try await dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT count(*) FROM outcome_events WHERE kind IN (\(placeholders)) AND created_at_ms >= ?",
                arguments: arguments) ?? 0
        }
    }

    public func prune(olderThan before: Date) async throws -> Int {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM outcome_events WHERE created_at_ms < ?", arguments: [DoddyDatabase.milliseconds(before)])
            return db.changesCount
        }
    }

    public func deleteAll() async throws {
        try await dbQueue.write { db in try db.execute(sql: "DELETE FROM outcome_events") }
    }

    public func export() async throws -> Data {
        try await dbQueue.read { db in
            let events = try Row.fetchAll(db, sql: "SELECT * FROM outcome_events ORDER BY created_at_ms, rowid").map(Self.record(from:))
            return try LearningJSON.encoder().encode(events.map(OutcomeEventExport.init))
        }
    }

    private static func record(from row: Row) throws -> OutcomeEvent {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString), let kind = OutcomeKind(rawValue: row["kind"]) else {
            throw LearningStoreError.corruptRecord(idString)
        }
        do {
            return try OutcomeEvent(
                id: id, requestID: row["request_id"], kind: kind,
                detail: try LearningRows.decode(OutcomeDetail.self, row["detail_json"]),
                createdAt: DoddyDatabase.date(milliseconds: row["created_at_ms"]))
        } catch {
            throw LearningStoreError.corruptRecord(idString)
        }
    }
}

struct OutcomeEventExport: Encodable {
    let id: UUID
    let requestID: String
    let kind: OutcomeKind
    let detail: OutcomeDetail
    let createdAt: Date

    init(_ event: OutcomeEvent) {
        id = event.id; requestID = event.requestID; kind = event.kind; detail = event.detail; createdAt = event.createdAt
    }
}
