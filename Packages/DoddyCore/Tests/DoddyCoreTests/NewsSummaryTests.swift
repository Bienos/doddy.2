import XCTest
@testable import DoddyCore

// AI summaries on the radar (owner, 13 Nov 2026): what the iPhone shows of the server's answer, and what it never does.
final class NewsSummaryTests: XCTestCase {
    private func json(points: [String], headline: String = "Sejm uchwalił budżet") -> Data {
        let list = points.map { "\"\($0)\"" }.joined(separator: ",")
        return Data(#"{"summary":{"headline":"\#(headline)","points":[\#(list)],"whyItMatters":"Wpływa na podatki."},"model":"claude-haiku-5-5","source":{"url":"https://tvn24.pl/a","host":"tvn24.pl"},"generatedAt":"2026-11-13T10:00:00.000Z","cached":false}"#.utf8)
    }

    func testAWholeSummaryDecodes() throws {
        let summary = try XCTUnwrap(NewsSummary.decode(json(points: ["Pierwszy punkt.", "Drugi punkt.", "Trzeci punkt."])))
        XCTAssertEqual(summary.summary.points.count, 3)
        XCTAssertEqual(summary.summary.whyItMatters, "Wpływa na podatki.")
        XCTAssertEqual(summary.source.host, "tvn24.pl")
        XCTAssertEqual(summary.writerName, "Claude Haiku")
        XCTAssertFalse(summary.cached)
    }

    func testAPartialOrOddAnswerIsNeverShownAsASummary() {
        XCTAssertNil(NewsSummary.decode(json(points: ["Tylko jeden."])))
        XCTAssertNil(NewsSummary.decode(json(points: ["1", "2", "3", "4", "5", "6"])))
        XCTAssertNil(NewsSummary.decode(json(points: ["Jeden.", "  "])))
        XCTAssertNil(NewsSummary.decode(json(points: ["Jeden.", "Dwa."], headline: " ")))
        XCTAssertNil(NewsSummary.decode(Data("{}".utf8)))
    }

    func testEachServerErrorHasItsOwnWords() {
        let problem = { (status: Int, code: String) in NewsSummaryProblem(status: status, body: Data(#"{"error":"\#(code)"}"#.utf8)) }
        XCTAssertEqual(problem(503, "summary_off"), .off)
        XCTAssertEqual(problem(503, "not_configured"), .off)
        XCTAssertEqual(problem(404, ""), .off, "a server from before the feature")
        XCTAssertEqual(problem(422, "unreadable_article"), .unreadable)
        XCTAssertEqual(problem(429, "daily_limit"), .dailyLimit)
        XCTAssertEqual(problem(429, "rate_limited"), .dailyLimit)
        XCTAssertEqual(problem(400, "invalid_url"), .invalidLink)
        XCTAssertEqual(problem(502, "summary_failed"), .failed)
        for p in [NewsSummaryProblem.off, .unreadable, .dailyLimit, .invalidLink, .failed] {
            XCTAssertFalse(p.text(polish: true).isEmpty)
            XCTAssertFalse(p.text(polish: false).isEmpty)
        }
    }
}
