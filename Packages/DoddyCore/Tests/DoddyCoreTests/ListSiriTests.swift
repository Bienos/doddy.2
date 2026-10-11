import DoddyCore
import XCTest

/// Lists from Siri (ADR-226): how a spoken phrase becomes items, and what Siri says back.
final class ListSiriTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func list(_ name: String, open: [String], done: [String] = []) throws -> DoddyList {
        let record = try MemoryRecord(id: UUID(), rawText: name, source: .explicitVoice, category: .list, capturedAt: now)
        let items = open.enumerated().map { ListItem(id: UUID(), listID: record.id, text: $1, source: .voice, addedAt: now, doneAt: nil, position: $0) }
            + done.enumerated().map { ListItem(id: UUID(), listID: record.id, text: $1, source: .voice, addedAt: now, doneAt: now, position: 100 + $0) }
        return DoddyList(record: record, items: items)
    }

    func testItemsSplitOnCommasButNotOnAnd() {
        XCTAssertEqual(ListSiri.items(from: "milk, eggs; salt and pepper crisps\nbread"), ["milk", "eggs", "salt and pepper crisps", "bread"])
        XCTAssertEqual(ListSiri.items(from: " , ;  "), [])
    }

    func testRepliesSayOnlyWhatTheStoreReturned() throws {
        let shopping = try list("Shopping", open: ["oat milk"])
        let added = ListAddResult(added: [shopping.items[0]], alreadyThere: ["eggs"], tooLong: [], noRoom: [])
        XCTAssertEqual(ListSiri.added(added, list: "Shopping", .english), "Added to Shopping: oat milk. Already on it: eggs.")
        XCTAssertEqual(ListSiri.added(ListAddResult(added: [], alreadyThere: ["eggs"], tooLong: [], noRoom: []), list: "Zakupy", .polish),
                       "Nic nie dodałem do listy Zakupy. Już jest na liście: eggs.")
    }

    func testReadListsOpenItemsAndCountsTheRest() throws {
        let long = try list("Shopping", open: (1...14).map { "item \($0)" }, done: ["bread"])
        let text = ListSiri.read(long, .english)
        XCTAssertTrue(text.hasPrefix("Shopping has 14 left: item 1, item 2"))
        XCTAssertTrue(text.hasSuffix("and \(14 - ListLimits.readAloud) more."))
        XCTAssertFalse(text.contains("bread"), "ticked items are not read")
        XCTAssertEqual(ListSiri.read(try list("Zakupy", open: [], done: ["chleb"]), .polish), "Na liście Zakupy nic nie zostało.")
    }

    func testTickWordingNamesTheExactItem() throws {
        let shopping = try list("Shopping", open: ["oat milk", "milk chocolate"])
        XCTAssertEqual(ListSiri.ticked(shopping.items[0], list: "Shopping", .english), "Ticked on Shopping: oat milk.")
        XCTAssertTrue(ListSiri.several("milk", options: shopping.items, list: "Shopping", .english).contains("Nothing was ticked"))
    }
}
