import XCTest
@testable import DoddyCore

/// "The usual" (ADR-343): items ticked at least twice on lists with the same name.
final class UsualItemsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func list(_ name: String, open: [String], done: [String] = [], at offset: TimeInterval = 0) throws -> DoddyList {
        let record = try MemoryRecord(id: UUID(), rawText: name, source: .explicitText, category: .list, capturedAt: now)
        var items: [ListItem] = []
        for (position, text) in (open + done).enumerated() {
            items.append(ListItem(id: UUID(), listID: record.id, text: text, source: .typed, addedAt: now,
                                  doneAt: position >= open.count ? now.addingTimeInterval(offset) : nil, position: position))
        }
        return DoddyList(record: record, items: items)
    }

    func testTwoTicksOnListsWithTheSameNameMakeItUsual() throws {
        var usual = UsualItems()
        let week1 = try list("Shopping", open: [], done: ["Milk", "Bread", "Tulips"], at: 0)
        let week2 = try list("shopping ", open: [], done: ["milk", "Bread"], at: 100)
        XCTAssertTrue(usual.record([week1, week2]))
        let now = try list("Shopping", open: ["Eggs", "bread"])
        // Bread is already open; Tulips only once.
        XCTAssertEqual(usual.suggestions(for: now).map(\.text), ["milk"])
        // Another list name learns nothing from shopping.
        XCTAssertTrue(usual.suggestions(for: try list("Packing", open: [])).isEmpty)
    }

    func testATickIsCountedOnceHoweverOftenListsReload() throws {
        var usual = UsualItems()
        let week = try list("Shopping", open: [], done: ["Milk"])
        usual.record([week])
        XCTAssertFalse(usual.record([week]))
        XCTAssertTrue(usual.suggestions(for: try list("Shopping", open: [])).isEmpty)
    }

    func testOpenItemsAreNotCounted() throws {
        var usual = UsualItems()
        XCTAssertFalse(usual.record([try list("Shopping", open: ["Milk"]), try list("Shopping", open: ["Milk"])]))
    }

    func testMostOftenFirstAndForget() throws {
        var usual = UsualItems()
        usual.record([
            try list("Shopping", open: [], done: ["Milk", "Eggs"], at: 0),
            try list("Shopping", open: [], done: ["Milk", "Eggs"], at: 10),
            try list("Shopping", open: [], done: ["Milk"], at: 20),
        ])
        let fresh = try list("Shopping", open: [])
        XCTAssertEqual(usual.suggestions(for: fresh).map(\.count), [3, 2])
        let reloaded = UsualItems(stored: usual.stored)
        XCTAssertEqual(reloaded.suggestions(for: fresh).map(\.text), ["Milk", "Eggs"])
        usual.forget(listNamed: "SHOPPING")
        XCTAssertTrue(usual.suggestions(for: fresh).isEmpty)
    }
}
