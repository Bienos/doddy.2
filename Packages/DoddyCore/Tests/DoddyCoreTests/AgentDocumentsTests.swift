import Foundation
import XCTest
@testable import DoddyCore

final class AgentDocumentsTests: XCTestCase {
    func testCallReportRoundTripsAndExportsSourceEvidenceInPolishAndEnglish() throws {
        let json = #"{"format":1,"objective":"Dentist availability","domain":"appointment","outcome":"answered","facts":[{"kind":"time","value":"Friday 14:30","certainty":"uncertain","evidence":{"line":2,"atSecs":8,"quote":"Maybe Friday 14:30"}}],"verification":{"method":"verbatim_callee_evidence","accepted":1,"rejected":1}}"#
        let report = try JSONDecoder().decode(CallReport.self, from: Data(json.utf8))
        XCTAssertEqual(try JSONDecoder().decode(CallReport.self, from: JSONEncoder().encode(report)), report)
        let english = report.markdown(polish: false)
        XCTAssertTrue(english.contains("Uncertain"))
        XCTAssertTrue(english.contains("Maybe Friday 14:30"))
        XCTAssertTrue(english.contains("Line 3 · 8 s"))
        XCTAssertTrue(report.markdown(polish: true).contains("Niepewne"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("call-report.md")
        try Data(english.utf8).write(to: file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), english)
    }

    func testUntrustedReportTextCannotBecomeActiveMarkdownOrHTML() throws {
        let report = CallReport(format: 1, objective: "<script>![track](https://example.test/x)</script>", domain: "general",
          outcome: "answered", facts: [], verification: .init(method: "verbatim_callee_evidence", accepted: 0, rejected: 0))
        let markdown = report.markdown(polish: false)
        XCTAssertFalse(markdown.contains("<script>"))
        XCTAssertFalse(markdown.contains("![track]("))
        XCTAssertTrue(markdown.contains("No details could be verified"))
    }

    func testDurableProgressRoundTripAndTerminalStatusOverride() throws {
        let json = #"{"stage":"writing_report","requests":2,"searches":3,"fetches":4,"updatedAt":"2026-11-18T16:00:00Z","events":[{"stage":"researching","requests":1,"searches":2,"fetches":3,"at":"2026-11-18T15:59:00Z"}]}"#
        let progress = try JSONDecoder().decode(ErrandProgress.self, from: Data(json.utf8))
        let draft = ErrandDraft(words: "Compare headphones", brief: "Compare headphones", title: "Headphones")
        var record = StoredErrand(id: UUID(), createdAt: Date(), state: .running, draft: draft)
        record.progress = progress
        let restored = try JSONDecoder().decode(StoredErrand.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(restored.progress, progress)
        XCTAssertEqual(progress.message(for: .running, polish: false), "Preparing the report.")
        XCTAssertEqual(progress.message(for: .done, polish: true), "Wynik jest gotowy.")
        XCTAssertFalse(progress.message(for: .unknown, polish: false).contains("ready"))
    }
}
