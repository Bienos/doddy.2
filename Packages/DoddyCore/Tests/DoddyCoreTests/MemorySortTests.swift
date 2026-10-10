import DoddyCore
import Foundation
import XCTest

final class MemorySortTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private func note(_ text: String, at offset: TimeInterval?) throws -> MemoryRecord {
        try MemoryRecord(
            id: UUID(), rawText: text,
            source: offset == nil ? .importedLegacyUnknown : .explicitText,
            capturedAt: offset.map { t0.addingTimeInterval($0) })
    }

    func testNewestAndOldestFirstPutUnknownDatesLastEitherWay() throws {
        let a = try note("a", at: 10), b = try note("b", at: 30), c = try note("c", at: 20), unknown = try note("old", at: nil)
        XCTAssertEqual(MemorySort.newestFirst.apply(to: [a, unknown, b, c]), [b, c, a, unknown])
        XCTAssertEqual(MemorySort.oldestFirst.apply(to: [a, unknown, b, c]), [a, c, b, unknown])
    }

    func testRecentlyChangedUsesTheCorrectionTimeAndFallsBackToTheSaveTime() throws {
        let early = try note("early", at: 10).correcting(to: "early, fixed", at: t0.addingTimeInterval(100))
        let late = try note("late", at: 50)
        let middle = try note("middle", at: 20)
        XCTAssertEqual(MemorySort.recentlyChanged.apply(to: [late, middle, early]), [early, late, middle])
    }

    func testEqualDatesKeepTheStoredOrderAndEmptyIsFine() throws {
        let a = try note("a", at: 5), b = try note("b", at: 5), c = try note("c", at: 5)
        XCTAssertEqual(MemorySort.newestFirst.apply(to: [c, a, b]), [c, a, b])
        XCTAssertEqual(MemorySort.oldestFirst.apply(to: [c, a, b]), [c, a, b])
        XCTAssertEqual(MemorySort.recentlyChanged.apply(to: []), [])
    }

    func testStoredValueFallsBackToNewestFirst() {
        XCTAssertEqual(MemorySort(stored: "oldestFirst"), .oldestFirst)
        XCTAssertEqual(MemorySort(stored: "sideways"), .newestFirst)
        XCTAssertEqual(MemorySort(stored: nil), .newestFirst)
    }
}
