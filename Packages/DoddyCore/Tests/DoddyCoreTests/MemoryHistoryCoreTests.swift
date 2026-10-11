@testable import DoddyCore
import XCTest

/// ADR-252: the history model and every export carry each wording a note has had.
final class MemoryHistoryCoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_630_120)
    private let id = UUID()

    private func note(current: String = "C", edited: Bool = true) throws -> MemoryRecord {
        try MemoryRecord(id: id, rawText: "A", currentText: edited ? current : nil, source: .explicitText,
                         capturedAt: t0, updatedAt: edited ? t0.addingTimeInterval(120) : nil, userEdited: edited)
    }

    private func corrections(_ texts: String...) throws -> [MemoryCorrection] {
        try texts.enumerated().map {
            try MemoryCorrection(memoryID: id, number: $0.offset + 1, text: $0.element, correctedAt: t0.addingTimeInterval(Double($0.offset + 1) * 60))
        }
    }

    func testHistoryOnlyTrustsCorrectionsThatEndAtTheCurrentWording() throws {
        XCTAssertTrue(MemoryHistory.consistent(try note(), try corrections("B", "C")))
        XCTAssertFalse(MemoryHistory.consistent(try note(), try corrections("B")), "doesn't end at the current wording")
        XCTAssertFalse(MemoryHistory.consistent(try note(), []))
        let other = try MemoryCorrection(memoryID: UUID(), number: 1, text: "C", correctedAt: t0)
        XCTAssertFalse(MemoryHistory.consistent(try note(), [other]), "another note's correction")

        let unedited = MemoryHistory(record: try note(edited: false), corrections: [])
        XCTAssertEqual(unedited.versions.map(\.text), ["A"])
        XCTAssertEqual(unedited.versions.first?.isCurrent, true)
        XCTAssertTrue(unedited.isComplete)
        XCTAssertEqual(unedited.earlier, [])
    }

    func testACorrectionNeedsTextAndANumberFromOne() {
        XCTAssertThrowsError(try MemoryCorrection(memoryID: id, number: 0, text: "x", correctedAt: t0))
        XCTAssertThrowsError(try MemoryCorrection(memoryID: id, number: 1, text: "   ", correctedAt: t0))
    }

    func testTextAndMarkdownExportsListEveryEarlierWording() throws {
        let record = try note()
        let history = try corrections("B", "C")
        let text = MemoryExport.plainText([record], corrections: history, exportedAt: t0)
        XCTAssertTrue(text.contains("Earlier (2026-10-10T11:03:00Z): B\nOriginal: A"), text)
        let markdown = MarkdownExport.markdown([record], corrections: history, exportedAt: t0)
        XCTAssertTrue(markdown.contains("Earlier wording (2026-10-10T11:03:00Z):\n\n> B\n\nOriginal wording:\n\n> A"), markdown)
        // One correction: the same as before history was kept.
        let single = try note(current: "B")
        XCTAssertEqual(MemoryExport.plainText([single], corrections: try corrections("B"), exportedAt: t0),
                       MemoryExport.plainText([single], exportedAt: t0))
    }

    func testJSONExportCarriesTheCorrectionsAndReadsThemBack() throws {
        let record = try note()
        let history = try corrections("B", "C")
        let stray = try MemoryCorrection(memoryID: UUID(), number: 1, text: "Not exported", correctedAt: t0)
        let data = try MemoryExport.json([record], corrections: history.reversed() + [stray], exportedAt: t0)
        let file = try MemoryRestore.read(data)
        XCTAssertEqual(file.records, [record])
        XCTAssertEqual(file.corrections, history, "only the exported notes' corrections, in order")
        // An export from before ADR-252 has no corrections key and still reads.
        let old = Data(#"{"formatVersion":1,"memories":[]}"#.utf8)
        XCTAssertEqual(try MemoryRestore.read(old).corrections, [])
    }

    func testADamagedCorrectionRefusesTheWholeFile() throws {
        let json = #"{"formatVersion":1,"memories":[],"corrections":[{"memoryId":"\#(id.uuidString)","number":0,"text":"x","correctedAtMs":1}]}"#
        XCTAssertThrowsError(try MemoryRestore.read(Data(json.utf8))) { error in
            XCTAssertEqual(error as? MemoryRestoreError, .unreadableCorrection(position: 1))
        }
    }
}
