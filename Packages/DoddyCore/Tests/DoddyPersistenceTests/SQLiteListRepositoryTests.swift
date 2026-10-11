import DoddyCore
import DoddyPersistence
import Foundation
import XCTest

/// Lists on real SQLite (ADR-216): every change read back, duplicates and limits, undo, cascade.
final class SQLiteListRepositoryTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func make() throws -> (DoddyDatabase, SQLiteListRepository, SQLiteMemoryRepository) {
        let database = try DoddyDatabase.inMemory()
        let time = clock
        return (database, SQLiteListRepository(database: database, now: { time }), SQLiteMemoryRepository(database: database, now: { time }))
    }

    func testCreateAddDuplicatesAndReopen() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("doddy-lists-\(UUID()).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        var lists = SQLiteListRepository(database: try DoddyDatabase(path: path))

        let shopping = try await lists.create(name: " Shopping ", items: ["milk", "eggs", "Milk"], source: .voice)
        XCTAssertEqual(shopping.name, "Shopping")
        XCTAssertEqual(shopping.record.category, .list)
        XCTAssertEqual(shopping.record.source, .explicitVoice)
        XCTAssertEqual(shopping.items.map(\.text), ["milk", "eggs"], "the second 'Milk' is a duplicate")

        let result = try await lists.add(["the milk", "2 packs of bananas", "  ", String(repeating: "x", count: 201)], to: shopping.id, source: .voice)
        XCTAssertEqual(result.added.map(\.text), ["2 packs of bananas"])
        XCTAssertEqual(result.alreadyThere, ["the milk"])
        XCTAssertEqual(result.tooLong.count, 1)
        XCTAssertEqual(result.added[0].position, 2)

        // Survives reopening the file.
        lists = SQLiteListRepository(database: try DoddyDatabase(path: path))
        let reopened = try await lists.list(id: shopping.id)
        XCTAssertEqual(reopened?.open.map(\.text), ["milk", "eggs", "2 packs of bananas"])
    }

    func testNamesAreUniqueAndListsAreNotNotes() async throws {
        let (_, lists, memories) = try make()
        let shopping = try await lists.create(name: "Shopping", items: [], source: .typed)
        do {
            _ = try await lists.create(name: "shopping", items: [], source: .typed)
            XCTFail("expected nameTaken")
        } catch ListError.nameTaken {}
        let note = try await memories.save(NewMemory(text: "Spare keys in the blue tin", capturedAt: clock))
        do {
            _ = try await memories.setCategory(id: note.id, to: .list)
            XCTFail("a note can't become a list")
        } catch ListError.notANote {}
        do {
            _ = try await memories.setCategory(id: shopping.id, to: .fact)
            XCTFail("a list can't become a note type")
        } catch ListError.notANote {}
        // Recall never returns a list.
        let recall = RepositoryRecallService(repository: memories)
        let outcome = try await recall.recall("shopping", limit: 5)
        XCTAssertEqual(outcome, .noMatch)
        let renamed = try await lists.rename(listID: shopping.id, to: "Zakupy")
        XCTAssertEqual(renamed.name, "Zakupy")
        XCTAssertEqual(renamed.record.rawText, "Shopping", "the first name stays as the original")
    }

    func testTickUntickClearRemoveAndUndo() async throws {
        let (_, lists, _) = try make()
        let list = try await lists.create(name: "Packing", items: ["charger", "passport", "jacket"], source: .typed)
        let ticked = try await lists.setDone([list.items[0].id, list.items[1].id], done: true)
        XCTAssertEqual(ticked.count, 2)
        XCTAssertTrue(ticked.allSatisfy(\.isDone))
        // Ticking again changes nothing and reports nothing.
        let again = try await lists.setDone([list.items[0].id], done: true)
        XCTAssertEqual(again, [])

        let cleared = try await lists.clearDone(listID: list.id)
        XCTAssertEqual(Set(cleared.map(\.text)), ["charger", "passport"])
        var stored = try await lists.list(id: list.id)
        XCTAssertEqual(stored?.items.map(\.text), ["jacket"])

        // Undo puts them back exactly, ticked and in place.
        let restored = try await lists.restore(cleared)
        XCTAssertEqual(Set(restored), Set(cleared))
        stored = try await lists.list(id: list.id)
        XCTAssertEqual(stored?.items.map(\.text), ["charger", "passport", "jacket"])

        let unticked = try await lists.untickAll(listID: list.id)
        XCTAssertEqual(unticked.count, 2)
        stored = try await lists.list(id: list.id)
        XCTAssertEqual(stored?.open.count, 3)

        let removed = try await lists.remove([list.items[2].id])
        XCTAssertEqual(removed.map(\.text), ["jacket"])
    }

    func testDeletingTheListDeletesItsItemsAndExportCarriesThem() async throws {
        let (_, lists, memories) = try make()
        let list = try await lists.create(name: "Shopping", items: ["milk"], source: .voice)
        let export = try await memories.export()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: export) as? [String: Any])
        XCTAssertEqual((json["listItems"] as? [[String: Any]])?.count, 1)

        try await memories.delete(id: list.id)
        let left = try await lists.allItems()
        XCTAssertEqual(left, [])
        // An item whose list is gone is not restored.
        let restored = try await lists.restore(list.items)
        XCTAssertEqual(restored, [])
    }

    func testListLimitAndItemLimit() async throws {
        let (_, lists, _) = try make()
        let many = (0..<(ListLimits.itemsPerList + 3)).map { "item \($0)" }
        let list = try await lists.create(name: "Big", items: [], source: .typed)
        let result = try await lists.add(many, to: list.id, source: .typed)
        XCTAssertEqual(result.added.count, ListLimits.itemsPerList)
        XCTAssertEqual(result.noRoom.count, 3)
        do {
            _ = try await lists.add(["x"], to: UUID(), source: .typed)
            XCTFail("expected notFound")
        } catch ListError.notFound {}
    }

    /// Review B5: the database counts code points, so 50 family emoji (250 code points) are too
    /// long; they are reported, and the rest of the voice add is still saved.
    func testEmojiItemTooLongForTheDatabaseIsReportedNotRolledBack() async throws {
        let (_, lists, _) = try make()
        let list = try await lists.create(name: "Shopping", items: [], source: .voice)
        let emoji = String(repeating: "👨‍👩‍👧", count: 50)
        let result = try await lists.add(["milk", emoji, "eggs"], to: list.id, source: .voice)
        XCTAssertEqual(result.added.map(\.text), ["milk", "eggs"])
        XCTAssertEqual(result.tooLong, [emoji])
        let stored = try await lists.list(id: list.id)
        XCTAssertEqual(stored?.items.map(\.text), ["milk", "eggs"])

        // An export with such an item (e.g. edited by hand) restores the rest of the list.
        let item = ListItem(id: UUID(), listID: list.id, text: emoji, source: .typed, addedAt: clock, doneAt: nil, position: 9)
        let data = try MemoryExport.json([list.record], listItems: (stored?.items ?? []) + [item], exportedAt: clock)
        XCTAssertEqual(try MemoryRestore.listItems(data).map(\.text), ["milk", "eggs"])
    }

    func testReminderTextForAListShowsOpenItems() async throws {
        let (database, lists, _) = try make()
        let list = try await lists.create(name: "Shopping", items: ["milk", "eggs"], source: .voice)
        let reminders = SQLiteNoteReminderRepository(database: database)
        var text = try await reminders.currentText(ofMemory: list.id)
        XCTAssertEqual(text, "Shopping: milk, eggs")
        _ = try await lists.setDone(list.items.map(\.id), done: true)
        text = try await reminders.currentText(ofMemory: list.id)
        XCTAssertEqual(text, "Shopping: nothing left")
    }
}

extension SQLiteListRepositoryTests {
    /// Export, wipe, restore: the list comes back with its items, ticks and order.
    func testExportThenRestoreBringsListItemsBack() async throws {
        let (_, lists, memories) = try make()
        let list = try await lists.create(name: "Packing", items: ["charger", "passport"], source: .typed)
        _ = try await lists.setDone([list.items[1].id], done: true)
        let data = try await memories.export()
        try await memories.deleteAll()
        let lists0 = try await lists.lists()
        XCTAssertEqual(lists0, [])

        let file = try MemoryRestore.read(data)
        let items = try MemoryRestore.listItems(data)
        XCTAssertEqual(items.count, 2)
        _ = try await memories.restore(file.records)
        let restored = try await lists.restore(items)
        XCTAssertEqual(restored.count, 2)
        let back = try await lists.list(id: list.id)
        XCTAssertEqual(back?.open.map(\.text), ["charger"])
        XCTAssertEqual(back?.done.map(\.text), ["passport"])
    }

    /// Review B1: a restore never puts items back into a list that is already here, so an item
    /// the user deleted after the export stays deleted.
    func testRestoreAddsItemsOnlyIntoListsItAdds() async throws {
        let (_, lists, memories) = try make()
        let packing = try await lists.create(name: "Packing", items: ["charger", "passport"], source: .typed)
        let shopping = try await lists.create(name: "Shopping", items: ["milk"], source: .typed)
        let data = try await memories.export()
        _ = try await lists.remove([packing.items[0].id])
        try await memories.delete(id: shopping.id)

        let file = try MemoryRestore.read(data)
        let restored = try await memories.restore(file.records, corrections: file.corrections, listItems: try MemoryRestore.listItems(data))
        XCTAssertEqual(restored.records.map(\.id), [shopping.id])
        XCTAssertEqual(restored.listItems.map(\.text), ["milk"])
        let packingNow = try await lists.list(id: packing.id)
        XCTAssertEqual(packingNow?.items.map(\.text), ["passport"], "the deleted item stays deleted")
        let shoppingNow = try await lists.list(id: shopping.id)
        XCTAssertEqual(shoppingNow?.items.map(\.text), ["milk"])
    }

    /// Review B1: Undo keeps the item limit and never gives two items the same place.
    func testRestoreKeepsItemLimitAndPlaces() async throws {
        let (_, lists, _) = try make()
        let list = try await lists.create(name: "Packing", items: ["charger", "passport", "jacket"], source: .typed)
        let removed = try await lists.remove([list.items[2].id])
        _ = try await lists.add(["socks"], to: list.id, source: .typed)
        let back = try await lists.restore(removed)
        XCTAssertEqual(back.map(\.position), [3], "socks took place 2, so the jacket goes after it")
        let stored = try await lists.list(id: list.id)
        XCTAssertEqual(stored?.items.map(\.text), ["charger", "passport", "socks", "jacket"])
        XCTAssertEqual(Set(stored?.items.map(\.position) ?? []).count, 4)

        let full = try await lists.create(name: "Full", items: [], source: .typed)
        let filled = try await lists.add((0..<ListLimits.itemsPerList).map { "item \($0)" }, to: full.id, source: .typed)
        let first = try await lists.remove([filled.added[0].id])
        _ = try await lists.add(["one more"], to: full.id, source: .typed)
        let none = try await lists.restore(first)
        XCTAssertEqual(none, [], "the list is full again")
        let fullNow = try await lists.list(id: full.id)
        XCTAssertEqual(fullNow?.items.count, ListLimits.itemsPerList)
    }

    /// Review B4: notes and list items are one transaction; an item that can't be stored keeps
    /// every note from the file out too, so "nothing was added" is true.
    func testRestoreOfNotesAndItemsIsOneTransaction() async throws {
        let (_, lists, memories) = try make()
        let list = try await lists.create(name: "Packing", items: ["charger"], source: .typed)
        let note = try await memories.save(NewMemory(text: "Keys in the tin", capturedAt: Date(timeIntervalSince1970: 0)))
        let data = try await memories.export()
        try await memories.deleteAll()

        let file = try MemoryRestore.read(data)
        let item = list.items[0]
        let bad = ListItem(id: UUID(), listID: list.id, text: String(repeating: "x", count: ListLimits.itemLength + 1),
                           source: .typed, addedAt: item.addedAt, doneAt: nil, position: 1)
        do {
            _ = try await memories.restore(file.records, corrections: [], listItems: [item, bad])
            XCTFail("the over-long item breaks the database rule")
        } catch {}
        let notes = try await memories.list(limit: nil)
        XCTAssertEqual(notes, [])
        let left = try await lists.lists()
        XCTAssertEqual(left, [])

        let good = try await memories.restore(file.records, corrections: [], listItems: [item])
        XCTAssertEqual(Set(good.records.map(\.id)), [list.id, note.id])
        XCTAssertEqual(good.listItems, [item])
    }

    func testListReminderIsKnownAsAList() async throws {
        let (database, lists, memories) = try make()
        let list = try await lists.create(name: "Shopping", items: [], source: .typed)
        let note = try await memories.save(NewMemory(text: "Keys in the tin", capturedAt: Date(timeIntervalSince1970: 0)))
        let reminders = SQLiteNoteReminderRepository(database: database)
        let listIs = await reminders.isList(memoryID: list.id)
        let noteIs = await reminders.isList(memoryID: note.id)
        XCTAssertTrue(listIs)
        XCTAssertFalse(noteIs)
        XCTAssertEqual(NoteReminderCopy.body(noteText: "x", showNoteText: false, isList: true), "A list you asked to see again.")
        XCTAssertEqual(NoteReminderCopy.body(noteText: "x", showNoteText: false, language: .polish, isList: true), "Lista, którą chcesz zobaczyć ponownie.")
        XCTAssertEqual(NoteReminderCopy.body(noteText: "x", showNoteText: false), NoteReminderCopy.privateBody)
    }
}
