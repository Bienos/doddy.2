import DoddyCore
import Foundation
import XCTest

final class MemoryFilterTests: XCTestCase {
    private func note(_ text: String, _ category: MemoryCategory) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: .explicitText, category: category, capturedAt: Date())
    }

    func testOnlyUsedTypesAreOfferedInFixedOrderWithCounts() throws {
        let records = [try note("Dentist Tue", .commitment), try note("Keys in tin", .place),
                       try note("Call mum", .commitment), try note("Read Lalka", .recommendation)]
        let choices = MemoryFilter.choices(records)
        XCTAssertEqual(choices.map(\.category), [.commitment, .recommendation, .place])
        XCTAssertEqual(choices.map(\.count), [2, 1, 1])
    }

    func testNoFilterWhenOnlyOneTypeIsUsed() throws {
        XCTAssertTrue(MemoryFilter.choices([try note("a", .other), try note("b", .other)]).isEmpty)
        XCTAssertTrue(MemoryFilter.choices([]).isEmpty)
    }

    func testApplyKeepsOrderAndNilShowsEverything() throws {
        let a = try note("a", .place), b = try note("b", .fact), c = try note("c", .place)
        XCTAssertEqual(MemoryFilter.apply(.place, to: [a, b, c]), [a, c])
        XCTAssertEqual(MemoryFilter.apply(nil, to: [a, b, c]), [a, b, c])
        XCTAssertEqual(MemoryFilter.apply(.decision, to: [a, b, c]), [])
    }
}
