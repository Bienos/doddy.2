import Foundation
import XCTest
@testable import DoddyCore

final class FocusFilterTests: XCTestCase {
    private struct Row: Identifiable, Equatable { let id: UUID }

    func testDefaultsChangeNothing() {
        XCTAssertTrue(FocusFilterSettings().changesNothing)
        XCTAssertEqual(FocusFilterSettings(stored: nil), .none)
        XCTAssertEqual(FocusFilterSettings(stored: "not json"), .none)
        let set = FocusFilterSettings(pausesHeyDoddy: true, listFirstID: UUID())
        XCTAssertFalse(set.changesNothing)
        XCTAssertEqual(FocusFilterSettings(stored: set.stored), set)
    }

    func testFocusListComesFirstWithoutReorderingTheRest() {
        let rows = (0..<4).map { _ in Row(id: UUID()) }
        let focus = FocusFilterSettings(listFirstID: rows[2].id)
        XCTAssertEqual(focus.ordered(rows), [rows[2], rows[0], rows[1], rows[3]])
        // A deleted list, or none chosen, keeps the usual order.
        XCTAssertEqual(FocusFilterSettings(listFirstID: UUID()).ordered(rows), rows)
        XCTAssertEqual(FocusFilterSettings.none.ordered(rows), rows)
    }
}
