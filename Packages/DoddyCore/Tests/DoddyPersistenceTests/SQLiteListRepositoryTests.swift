import DoddyCore
import DoddyPersistence
import Foundation
import XCTest

/// Lists on real SQLite (ADR-210): every change read back, duplicates and limits, undo, cascade.
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
