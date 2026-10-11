import DoddyCore
import XCTest

/// Shopping mode (ADR-257): what the Lock Screen shows.
final class ShoppingModeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func list(open: [String], done: [String]) throws -> DoddyList {
        let record = try MemoryRecord(id: UUID(), rawText: "Shopping", source: .explicitText, category: .list, capturedAt: now)
        var position = 0
        var items: [ListItem] = []
        for text in open {
            items.append(ListItem(id: UUID(), listID: record.id, text: text, source: .typed, addedAt: now, doneAt: nil, position: position))
            position += 1
        }
        for (offset, text) in done.enumerated() {
            items.append(ListItem(id: UUID(), listID: record.id, text: text, source: .typed, addedAt: now,
                                  doneAt: now.addingTimeInterval(Double(offset)), position: position))
            position += 1
        }
        return DoddyList(record: record, items: items)
    }

    func testOpenItemsFirstThenRecentTicksWhileThereIsRoom() throws {
        let state = ShoppingModeState.make(try list(open: ["milk", "eggs"], done: ["bread", "butter"]))
        XCTAssertEqual(state.items.map(\.text), ["milk", "eggs", "butter", "bread"], "the latest tick first, so a mis-tap is easy to undo")
        XCTAssertEqual(state.openCount, 2)
        XCTAssertFalse(state.isFinished)
        XCTAssertEqual(state.moreOpen, 0)
    }

    func testALongListShowsSixAndCountsTheRest() throws {
        let state = ShoppingModeState.make(try list(open: (1...9).map { "item \($0)" }, done: ["x"]))
        XCTAssertEqual(state.items.count, ShoppingMode.maxItems)
        XCTAssertTrue(state.items.allSatisfy { !$0.isDone })
        XCTAssertEqual(state.moreOpen, 3)
    }

    func testFinishedOnlyWhenEverythingIsTicked() throws {
        XCTAssertTrue(ShoppingModeState.make(try list(open: [], done: ["milk"])).isFinished)
        XCTAssertFalse(ShoppingModeState.make(try list(open: [], done: [])).isFinished, "an empty list isn't finished")
        let long = String(repeating: "a", count: 80)
        XCTAssertEqual(ShoppingModeState.make(try list(open: [long], done: [])).items.first?.text.count, ShoppingMode.maxTextLength)
    }
}
