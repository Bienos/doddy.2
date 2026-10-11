import DoddyCore
import DoddyPersistence
import Foundation
import XCTest

/// Shared lists on real SQLite (ADR-258): replacing a list with the merged state, and the link.
final class SQLiteListShareTests: XCTestCase {
    private let clock = Date(timeIntervalSince1970: 1_800_000_000)

    func testReplaceSharedWritesExactlyTheMergedStateAndReadsItBack() async throws {
        let database = try DoddyDatabase.inMemory()
        let time = clock
        let lists = SQLiteListRepository(database: database, now: { time })
        let list = try await lists.create(name: "Shopping", items: ["milk", "eggs"], source: .typed)
        let milk = list.items[0], eggs = list.items[1]
        let tea = SharedListItem(id: UUID(), text: "tea", doneAt: nil, position: 1, addedAt: clock)
        let state = SharedListState(name: "Groceries", items: [
            SharedListItem(id: milk.id, text: "oat milk", doneAt: clock, position: 0, addedAt: milk.addedAt), tea,
        ])
        let stored = try await lists.replaceShared(listID: list.id, with: state)
        XCTAssertEqual(stored.name, "Groceries")
        XCTAssertEqual(SharedListState(stored), state)
        XCTAssertNil(stored.items.first { $0.id == eggs.id }, "removed in the merge")

        _ = try await lists.create(name: "Hardware", items: [], source: .typed)
        do {
            _ = try await lists.replaceShared(listID: list.id, with: SharedListState(name: "hardware", items: state.items))
            XCTFail("a name another list uses is refused")
        } catch ListError.nameTaken {}
    }

    func testTheLinkIsSavedReadBackAndGoesWithItsList() async throws {
        let database = try DoddyDatabase.inMemory()
        let lists = SQLiteListRepository(database: database)
        let memories = SQLiteMemoryRepository(database: database)
        let shares = SQLiteListShareRepository(database: database)
        let list = try await lists.create(name: "Shopping", items: ["milk"], source: .typed)
        let link = ListShare(
            listID: list.id, zoneName: ListShare.zoneName(for: list.id), zoneOwner: "__defaultOwner__",
            role: .owner, base: SharedListState(list), syncedAt: clock)
        try await shares.save(link)
        let saved = try await shares.shares()
        XCTAssertEqual(saved, [link])

        try await memories.delete(id: list.id)
        let afterDelete = try await shares.shares()
        XCTAssertEqual(afterDelete, [], "deleting the list deletes its link")
    }
}
