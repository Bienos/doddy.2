import XCTest
@testable import DoddyCore

/// Acceptance A-16: only the notes a question needs, within a hard budget, ever leave the device.
final class GroundingSelectorTests: XCTestCase {
    func testSampleFixturesAndUnmatchedNotesAreNeverSelected() throws {
        let real = try makeRecord("real")
        let fixture = try makeRecord("fixture", source: .sampleFixture)
        let unmatched = try makeRecord("unmatched")
        let chosen = GroundingSelector.select(from: [
            candidate(fixture), candidate(unmatched, terms: []), candidate(real),
        ])
        XCTAssertEqual(chosen.map(\.memoryID), [real.id])
    }

    func testCountBudgetKeepsTheBestRankedFirst() throws {
        let records = try (0..<8).map { try makeRecord("note \($0)") }
        let chosen = GroundingSelector.select(from: records.map { candidate($0) }, budget: .init(maxMemories: 3))
        XCTAssertEqual(chosen.map(\.memoryID), records.prefix(3).map(\.id))
    }

    func testSizeBudgetSkipsABigNoteInsteadOfTruncatingIt() throws {
        let big = try makeRecord(String(repeating: "x", count: 100))
        let small = try makeRecord("tiny")
        let chosen = GroundingSelector.select(
            from: [candidate(big), candidate(small)], budget: .init(maxMemories: 5, maxTotalScalars: 50))
        XCTAssertEqual(chosen.map(\.memoryID), [small.id])
        XCTAssertEqual(chosen.first?.record.currentText, "tiny", "text is never shortened")
    }

    func testDuplicatesAreSentOnce() throws {
        let record = try makeRecord()
        XCTAssertEqual(GroundingSelector.select(from: [candidate(record), candidate(record)]).count, 1)
    }

    func testBudgetMatchesTheGatewayLimits() {
        XCTAssertEqual(GroundingBudget.standard, GroundingBudget(maxMemories: 5, maxTotalScalars: 12_000))
    }
}
