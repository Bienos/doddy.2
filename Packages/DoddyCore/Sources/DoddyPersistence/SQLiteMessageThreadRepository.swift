import DoddyCore
import Foundation
import GRDB

/// The thread with Doddy, on the iPhone (ADR-585, `v17_message_thread`; tapbacks `v18_message_reactions`). A save reads the row back and
/// throws unless it matches, so a message is called saved only after that read. Deleting reads back too,
/// and `secure_delete` (set in `DoddyDatabase`) overwrites the freed pages.
public final class SQLiteMessageThreadRepository: MessageThreadRepository {
    private let dbQueue: DatabaseQueue

    public init(database: DoddyDatabase) {
        self.dbQueue = database.queue
    }

    public func recent(limit: Int) async throws -> [ThreadMessage] {
        let limit = max(0, limit)
        return try await dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM (SELECT rowid AS rid, * FROM thread_messages ORDER BY created_at_ms DESC, rowid DESC LIMIT ?)
                ORDER BY created_at_ms ASC, rid ASC
                """,
                arguments: [limit]
            ).map(Self.message(from:))
        }
    }

    public func append(_ message: ThreadMessage) async throws {
        let toStore = ThreadMessage(
            id: message.id, sender: message.sender, text: message.text,
            createdAt: DoddyDatabase.truncatedToMilliseconds(message.createdAt), delivery: message.delivery,
            basis: message.basis, noteIDs: message.noteIDs, notesSent: message.notesSent,
            notesSearchFailed: message.notesSearchFailed, reaction: message.reaction)
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO thread_messages (id, sender, text, created_at_ms, delivery, basis, note_ids, notes_sent, notes_search_failed, reaction)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    toStore.id.uuidString, toStore.sender.rawValue, toStore.text, DoddyDatabase.milliseconds(toStore.createdAt),
                    toStore.delivery.rawValue, toStore.basis?.rawValue, try LearningRows.json(toStore.noteIDs.map(\.uuidString)),
                    toStore.notesSent, toStore.notesSearchFailed ? 1 : 0, toStore.reaction?.rawValue,
                ])
            guard let stored = try Row.fetchOne(db, sql: "SELECT * FROM thread_messages WHERE id = ?", arguments: [toStore.id.uuidString])
                .map(Self.message(from:)), stored == toStore else { throw MessageThreadError.verificationFailed }
        }
    }

    public func setDelivery(id: UUID, _ delivery: ThreadMessage.Delivery) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE thread_messages SET delivery = ? WHERE id = ? AND sender = 'user'",
                arguments: [delivery.rawValue, id.uuidString])
            guard db.changesCount == 1 else { throw MessageThreadError.notFound }
            let stored: String? = try String.fetchOne(db, sql: "SELECT delivery FROM thread_messages WHERE id = ?", arguments: [id.uuidString])
            guard stored == delivery.rawValue else { throw MessageThreadError.verificationFailed }
        }
    }

    public func setReaction(id: UUID, _ reaction: ThreadMessage.Reaction?) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE thread_messages SET reaction = ? WHERE id = ? AND sender = 'doddy'",
                arguments: [reaction?.rawValue, id.uuidString])
            guard db.changesCount == 1 else { throw MessageThreadError.notFound }
            let stored: String? = try String.fetchOne(db, sql: "SELECT reaction FROM thread_messages WHERE id = ?", arguments: [id.uuidString])
            guard stored == reaction?.rawValue else { throw MessageThreadError.verificationFailed }
        }
    }

    public func failUnfinished() async throws -> Int {
        try await dbQueue.write { db in
            try db.execute(sql: "UPDATE thread_messages SET delivery = 'failed' WHERE delivery = 'sending'")
            let changed = db.changesCount
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM thread_messages WHERE delivery = 'sending'") == 0 else {
                throw MessageThreadError.verificationFailed
            }
            return changed
        }
    }

    public func delete(id: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM thread_messages WHERE id = ?", arguments: [id.uuidString])
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM thread_messages WHERE id = ?", arguments: [id.uuidString]) == 0 else {
                throw MessageThreadError.verificationFailed
            }
        }
    }

    public func deleteAll() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM thread_messages")
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM thread_messages") == 0 else {
                throw MessageThreadError.verificationFailed
            }
        }
    }

    /// Everything kept in the thread, for the user's own export.
    public func export() async throws -> Data {
        let all = try await recent(limit: Int.max)
        return try LearningJSON.encoder().encode(all)
    }

    private static func message(from row: Row) throws -> ThreadMessage {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString),
              let sender = ThreadMessage.Sender(rawValue: row["sender"]),
              let delivery = ThreadMessage.Delivery(rawValue: row["delivery"]),
              let noteStrings = try? LearningRows.decode([String].self, row["note_ids"])
        else { throw LearningStoreError.corruptRecord(idString) }
        let noteIDs = noteStrings.compactMap(UUID.init(uuidString:))
        guard noteIDs.count == noteStrings.count else { throw LearningStoreError.corruptRecord(idString) }
        let basisRaw: String? = row["basis"]
        let basis = basisRaw.flatMap(ThreadMessage.Basis.init(rawValue:))
        guard (basisRaw == nil) == (basis == nil) else { throw LearningStoreError.corruptRecord(idString) }
        let reactionRaw: String? = row["reaction"]
        let reaction = reactionRaw.flatMap(ThreadMessage.Reaction.init(rawValue:))
        guard (reactionRaw == nil) == (reaction == nil) else { throw LearningStoreError.corruptRecord(idString) }
        return ThreadMessage(
            id: id, sender: sender, text: row["text"], createdAt: DoddyDatabase.date(milliseconds: row["created_at_ms"]),
            delivery: delivery, basis: basis, noteIDs: noteIDs, notesSent: row["notes_sent"],
            notesSearchFailed: (row["notes_search_failed"] as Int) == 1, reaction: reaction)
    }
}
