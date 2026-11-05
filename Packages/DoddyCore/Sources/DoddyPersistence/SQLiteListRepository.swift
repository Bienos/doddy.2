import DoddyCore
import Foundation
import GRDB

/// Lists in the same SQLite file as the notes (ADR-216). A list is a `memories` row with category
/// `list`; deleting that row deletes its items (foreign key, cascade). Every change is one
/// transaction and is read back before it is returned.
public final class SQLiteListRepository: ListRepository {
    fileprivate let dbQueue: DatabaseQueue
    fileprivate let now: @Sendable () -> Date

    public init(database: DoddyDatabase, now: @escaping @Sendable () -> Date = Date.init) {
        self.dbQueue = database.queue
        self.now = now
    }

    public func lists() async throws -> [DoddyList] {
        try await dbQueue.read { db in
            let records = try Row.fetchAll(
                db, sql: "SELECT * FROM memories WHERE category = ? ORDER BY captured_at_ms, rowid",
                arguments: [MemoryCategory.list.rawValue]
            ).map(Self.record(from:))
            let items = Dictionary(grouping: try Self.allItems(db), by: \.listID)
            return records.map { DoddyList(record: $0, items: items[$0.id] ?? []) }
        }
    }

    public func list(id: UUID) async throws -> DoddyList? {
        try await dbQueue.read { db in try Self.list(id, db) }
    }

    public func create(name: String, items: [String], source: ListItemSource) async throws -> DoddyList {
        try await create(name: name, items: items, done: [], source: source)
    }

    public func create(name: String, items: [String], done: Set<String>, source: ListItemSource) async throws -> DoddyList {
        let name = try ListText.checkedName(name)
        let date = DoddyDatabase.truncatedToMilliseconds(now())
        return try await dbQueue.write { db in
            let existing = try Row.fetchAll(
                db, sql: "SELECT * FROM memories WHERE category = ?", arguments: [MemoryCategory.list.rawValue]
            ).map(Self.record(from:))
            guard existing.count < ListLimits.lists else { throw ListError.tooManyLists(maximum: ListLimits.lists) }
            if existing.contains(where: { ListMatch.key($0.currentText) == ListMatch.key(name) }) {
                throw ListError.nameTaken(name)
            }
            let record = try MemoryRecord(
                id: UUID(), rawText: name, source: source == .voice ? .explicitVoice : .explicitText,
                category: .list, capturedAt: date)
            try db.execute(
                sql: """
                    INSERT INTO memories (id, raw_text, current_text, category, source, captured_at_ms,
                                          updated_at_ms, user_edited, search_text, schema_version)
                    VALUES (?, ?, ?, ?, ?, ?, NULL, 0, ?, ?)
                    """,
                arguments: [
                    record.id.uuidString, record.rawText, record.currentText, record.category.rawValue,
                    record.source.rawValue, DoddyDatabase.milliseconds(date), SearchFolding.fold(record.currentText),
                    MemoryRecord.schemaVersion,
                ])
            let result = try Self.insert(items, into: record.id, source: source, at: date, db)
            let expected = result.added.map { item in
                done.contains(item.text)
                    ? ListItem(id: item.id, listID: item.listID, text: item.text, source: item.source,
                               addedAt: item.addedAt, doneAt: date, position: item.position)
                    : item
            }
            for item in expected where item.isDone {
                try db.execute(
                    sql: "UPDATE list_items SET done_at_ms = ? WHERE id = ?",
                    arguments: [DoddyDatabase.milliseconds(date), item.id.uuidString])
            }
            guard let stored = try Self.list(record.id, db), stored.record == record,
                  Set(stored.items) == Set(expected)
            else { throw MemoryStoreError.verificationFailed }
            return stored
        }
    }

    public func add(_ texts: [String], to listID: UUID, source: ListItemSource) async throws -> ListAddResult {
        let date = DoddyDatabase.truncatedToMilliseconds(now())
        return try await dbQueue.write { db in
            guard try Self.list(listID, db) != nil else { throw ListError.notFound }
            let result = try Self.insert(texts, into: listID, source: source, at: date, db)
            let stored = Set(try Self.items(listID, db))
            guard Set(result.added).isSubset(of: stored) else { throw MemoryStoreError.verificationFailed }
            return result
        }
    }

    public func rename(listID: UUID, to name: String) async throws -> DoddyList {
        let name = try ListText.checkedName(name)
        let date = DoddyDatabase.truncatedToMilliseconds(now())
        return try await dbQueue.write { db in
            guard let list = try Self.list(listID, db) else { throw ListError.notFound }
            let others = try Row.fetchAll(
                db, sql: "SELECT * FROM memories WHERE category = ? AND id != ?",
                arguments: [MemoryCategory.list.rawValue, listID.uuidString]
            ).map(Self.record(from:))
            if others.contains(where: { ListMatch.key($0.currentText) == ListMatch.key(name) }) {
                throw ListError.nameTaken(name)
            }
            let renamed = try list.record.correcting(to: name, at: date)
            try db.execute(
                sql: "UPDATE memories SET current_text = ?, updated_at_ms = ?, user_edited = 1, search_text = ? WHERE id = ?",
                arguments: [name, DoddyDatabase.milliseconds(date), SearchFolding.fold(name), listID.uuidString])
            // The list's name is indexed with the notes (ADR-584).
            try DoddyDatabase.compactSearchIndex("memories_fts", in: db)
            guard let stored = try Self.list(listID, db), stored.record == renamed else { throw MemoryStoreError.verificationFailed }
            return stored
        }
    }

    public func setDone(_ itemIDs: [UUID], done: Bool) async throws -> [ListItem] {
        let date = DoddyDatabase.truncatedToMilliseconds(now())
        return try await dbQueue.write { db in
            var changed: [ListItem] = []
            for id in itemIDs {
                guard let item = try Self.item(id, db), item.isDone != done else { continue }
                try db.execute(
                    sql: "UPDATE list_items SET done_at_ms = ? WHERE id = ?",
                    arguments: [done ? DoddyDatabase.milliseconds(date) : nil, id.uuidString])
                guard let stored = try Self.item(id, db), stored.isDone == done else { throw MemoryStoreError.verificationFailed }
                changed.append(stored)
            }
            return changed
        }
    }

    public func remove(_ itemIDs: [UUID]) async throws -> [ListItem] {
        try await dbQueue.write { db in
            var removed: [ListItem] = []
            for id in itemIDs {
                guard let item = try Self.item(id, db) else { continue }
                try db.execute(sql: "DELETE FROM list_items WHERE id = ?", arguments: [id.uuidString])
                guard try Self.item(id, db) == nil else { throw MemoryStoreError.verificationFailed }
                removed.append(item)
            }
            return removed
        }
    }

    public func clearDone(listID: UUID) async throws -> [ListItem] {
        let done = try await dbQueue.read { db in try Self.items(listID, db).filter(\.isDone) }
        return try await remove(done.map(\.id))
    }

    public func untickAll(listID: UUID) async throws -> [ListItem] {
        let done = try await dbQueue.read { db in try Self.items(listID, db).filter(\.isDone) }
        return try await setDone(done.map(\.id), done: false)
    }

    public func restore(_ items: [ListItem]) async throws -> [ListItem] {
        try await dbQueue.write { db in try Self.restore(items, db) }
    }

    /// Puts items back as they were, into lists that exist; an item whose id is stored is
    /// skipped. A list never goes past `ListLimits.itemsPerList` (the rest are skipped), and an
    /// item whose place was taken meanwhile goes after the last one. Each is read back.
    static func restore(_ items: [ListItem], _ db: Database) throws -> [ListItem] {
        var restored: [ListItem] = []
        for item in items {
            guard let list = try list(item.listID, db), try self.item(item.id, db) == nil,
                  list.items.count < ListLimits.itemsPerList
            else { continue }
            let placed = !list.items.contains(where: { $0.position == item.position }) ? item : ListItem(
                id: item.id, listID: item.listID, text: item.text, source: item.source, addedAt: item.addedAt,
                doneAt: item.doneAt, position: (list.items.map(\.position).max() ?? -1) + 1)
            try write(placed, db)
            guard try self.item(item.id, db) == placed else { throw MemoryStoreError.verificationFailed }
            restored.append(placed)
        }
        return restored
    }

    public func allItems() async throws -> [ListItem] {
        try await dbQueue.read { db in try Self.allItems(db) }
    }

    // MARK: Helpers

    /// Adds what is new, in order, after the last item. Duplicates of open items (or of each
    /// other), items that are too long and items past the limit are reported, not added.
    private static func insert(
        _ texts: [String], into listID: UUID, source: ListItemSource, at date: Date, _ db: Database
    ) throws -> ListAddResult {
        let existing = try items(listID, db)
        var openTexts = existing.filter { !$0.isDone }.map(\.text)
        var count = existing.count
        var position = (existing.map(\.position).max() ?? -1) + 1
        var added: [ListItem] = [], alreadyThere: [String] = [], tooLong: [String] = [], noRoom: [String] = []
        for raw in texts {
            guard let text = ListText.cleaned(raw) else { continue }
            if !ListText.fitsItemLength(text) { tooLong.append(text); continue }
            if ListMatch.isDuplicate(text, of: openTexts) { alreadyThere.append(text); continue }
            if count >= ListLimits.itemsPerList { noRoom.append(text); continue }
            let item = ListItem(id: UUID(), listID: listID, text: text, source: source, addedAt: date, doneAt: nil, position: position)
            try write(item, db)
            added.append(item)
            openTexts.append(text)
            count += 1
            position += 1
        }
        return ListAddResult(added: added, alreadyThere: alreadyThere, tooLong: tooLong, noRoom: noRoom)
    }

    private static func write(_ item: ListItem, _ db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO list_items (id, list_id, text, source, added_at_ms, done_at_ms, position)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                item.id.uuidString, item.listID.uuidString, item.text, item.source.rawValue,
                DoddyDatabase.milliseconds(item.addedAt), item.doneAt.map(DoddyDatabase.milliseconds), item.position,
            ])
    }

    private static func list(_ id: UUID, _ db: Database) throws -> DoddyList? {
        guard let row = try Row.fetchOne(
            db, sql: "SELECT * FROM memories WHERE id = ? AND category = ?",
            arguments: [id.uuidString, MemoryCategory.list.rawValue])
        else { return nil }
        return DoddyList(record: try record(from: row), items: try items(id, db))
    }

    private static func items(_ listID: UUID, _ db: Database) throws -> [ListItem] {
        try Row.fetchAll(
            db, sql: "SELECT * FROM list_items WHERE list_id = ? ORDER BY position", arguments: [listID.uuidString]
        ).map(item(from:))
    }

    static func allItems(_ db: Database) throws -> [ListItem] {
        try Row.fetchAll(db, sql: "SELECT * FROM list_items ORDER BY list_id, position").map(item(from:))
    }

    private static func item(_ id: UUID, _ db: Database) throws -> ListItem? {
        try Row.fetchOne(db, sql: "SELECT * FROM list_items WHERE id = ?", arguments: [id.uuidString]).map(item(from:))
    }

    fileprivate static func item(from row: Row) throws -> ListItem {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString), let listID = UUID(uuidString: row["list_id"]),
              let source = ListItemSource(rawValue: row["source"])
        else { throw MemoryStoreError.corruptRecord(idString) }
        return ListItem(
            id: id, listID: listID, text: row["text"], source: source,
            addedAt: DoddyDatabase.date(milliseconds: row["added_at_ms"]),
            doneAt: (row["done_at_ms"] as Int64?).map(DoddyDatabase.date(milliseconds:)),
            position: row["position"])
    }

    fileprivate static func record(from row: Row) throws -> MemoryRecord {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString), let source = MemorySource(rawValue: row["source"]) else {
            throw MemoryStoreError.corruptRecord(idString)
        }
        func date(_ column: String) -> Date? {
            (row[column] as Int64?).map(DoddyDatabase.date(milliseconds:))
        }
        do {
            return try MemoryRecord(
                id: id, rawText: row["raw_text"], currentText: row["current_text"], source: source, category: .list,
                capturedAt: date("captured_at_ms"), updatedAt: date("updated_at_ms"), userEdited: row["user_edited"])
        } catch {
            throw MemoryStoreError.corruptRecord(idString)
        }
    }
}

// MARK: Shared lists (ADR-263)

extension SQLiteListRepository {
    public func replaceShared(listID: UUID, with state: SharedListState) async throws -> DoddyList {
        let name = try ListText.checkedName(state.name)
        let date = DoddyDatabase.truncatedToMilliseconds(now())
        return try await dbQueue.write { db in
            guard let list = try Self.listForShare(listID, db) else { throw ListError.notFound }
            if list.name != name {
                let others = try Row.fetchAll(
                    db, sql: "SELECT current_text FROM memories WHERE category = ? AND id != ?",
                    arguments: [MemoryCategory.list.rawValue, listID.uuidString]
                ).map { $0["current_text"] as String }
                if others.contains(where: { ListMatch.key($0) == ListMatch.key(name) }) { throw ListError.nameTaken(name) }
                try db.execute(
                    sql: "UPDATE memories SET current_text = ?, updated_at_ms = ?, user_edited = 1, search_text = ? WHERE id = ?",
                    arguments: [name, DoddyDatabase.milliseconds(date), SearchFolding.fold(name), listID.uuidString])
                try DoddyDatabase.compactSearchIndex("memories_fts", in: db)
            }
            let existing = Dictionary(list.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let wanted = Set(state.items.map(\.id))
            for item in list.items where !wanted.contains(item.id) {
                try db.execute(sql: "DELETE FROM list_items WHERE id = ?", arguments: [item.id.uuidString])
            }
            for item in state.items {
                if existing[item.id] != nil {
                    try db.execute(
                        sql: "UPDATE list_items SET text = ?, done_at_ms = ?, position = ? WHERE id = ? AND list_id = ?",
                        arguments: [item.text, item.doneAt.map(DoddyDatabase.milliseconds), item.position,
                                    item.id.uuidString, listID.uuidString])
                } else {
                    try db.execute(
                        sql: """
                            INSERT INTO list_items (id, list_id, text, source, added_at_ms, done_at_ms, position)
                            VALUES (?, ?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            item.id.uuidString, listID.uuidString, item.text, ListItemSource.typed.rawValue,
                            DoddyDatabase.milliseconds(item.addedAt), item.doneAt.map(DoddyDatabase.milliseconds), item.position,
                        ])
                }
            }
            guard let stored = try Self.listForShare(listID, db),
                  SharedListState(stored) == SharedListState(name: name, items: state.items)
            else { throw MemoryStoreError.verificationFailed }
            return stored
        }
    }

    private static func listForShare(_ id: UUID, _ db: Database) throws -> DoddyList? {
        guard let row = try Row.fetchOne(
            db, sql: "SELECT * FROM memories WHERE id = ? AND category = ?",
            arguments: [id.uuidString, MemoryCategory.list.rawValue])
        else { return nil }
        let items = try Row.fetchAll(
            db, sql: "SELECT * FROM list_items WHERE list_id = ? ORDER BY position", arguments: [id.uuidString]
        ).map(item(from:))
        return DoddyList(record: try record(from: row), items: items)
    }
}
