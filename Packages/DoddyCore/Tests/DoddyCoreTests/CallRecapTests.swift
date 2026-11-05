@testable import DoddyCore
import XCTest

/// The recap file of a call (a plain text built from the brief and the answer card kept on the iPhone).
/// Written without a Swift toolchain at hand: run `make test-core` before relying on it.
final class CallRecapTests: XCTestCase {
    private let labels = CallRecap.Labels(
        title: "Call recap", to: "To", goal: "Goal", question: "Question", outcome: "Outcome", summary: "Summary",
        quote: "Quote", nextStep: "Next step", warnings: "Warnings", transcript: "Transcript", duration: "Duration",
        doddy: "Doddy", callee: "Other side")

    private func card(summary: String = "Laptop jest gotowy.", quote: String? = "Jest gotowy do odbioru", step: String = "Odbierz laptop") throws -> CallResultCard {
        let quoteJSON = quote.map { "{\"text\":\"\($0)\",\"line\":1}" } ?? "null"
        return try JSONDecoder().decode(CallResultCard.self, from: Data("""
        {"outcome":"answered","source":"elevenlabs","confidence":"high","confidenceReasons":[],"summary":"\(summary)","summaryBy":"rules",
         "quote":\(quoteJSON),"transcript":[{"speaker":"doddy","text":"Czy laptop jest gotowy?","atSecs":2},{"speaker":"callee","text":"Tak, jest gotowy.","atSecs":6}],
         "nextStep":{"kind":"other","text":"\(step)"},"warnings":[],"callbackPromised":false,"durationSecs":41}
        """.utf8))
    }

    private func record(result: CallResultCard?, name: String = "Anna Kowalska") -> StoredCallCase {
        var brief = CallBriefDraft()
        brief.calleeName = name
        brief.goal = "Sprawdzić, czy laptop jest gotowy."
        brief.question = "Czy laptop z serwisu jest gotowy?"
        return StoredCallCase(id: UUID(), createdAt: Date(timeIntervalSince1970: 1_793_000_000), state: "finished", brief: brief, result: result)
    }

    func testRecapHasTheBriefTheAnswerAndTheTranscript() throws {
        let text = try XCTUnwrap(CallRecap.text(for: record(result: card()), labels: labels, outcomeText: "Answered"))
        XCTAssertTrue(text.hasPrefix("Call recap\n"))
        XCTAssertTrue(text.contains("To: Anna Kowalska"))
        XCTAssertTrue(text.contains("Question: Czy laptop z serwisu jest gotowy?"))
        XCTAssertTrue(text.contains("Outcome: Answered"))
        XCTAssertTrue(text.contains("Duration: 41 s"))
        XCTAssertTrue(text.contains("Summary: Laptop jest gotowy."))
        XCTAssertTrue(text.contains("Next step: Odbierz laptop"))
        XCTAssertTrue(text.contains("Doddy: Czy laptop jest gotowy?"))
        XCTAssertTrue(text.contains("Other side: Tak, jest gotowy."))
    }

    func testNoAnswerCardMeansNoRecap() {
        XCTAssertNil(CallRecap.text(for: record(result: nil), labels: labels, outcomeText: "x"))
    }

    func testEmptyNextStepAndQuoteAreLeftOut() throws {
        let text = try XCTUnwrap(CallRecap.text(for: record(result: card(quote: nil, step: "")), labels: labels, outcomeText: "x"))
        XCTAssertFalse(text.contains("Next step:"))
        XCTAssertFalse(text.contains("Quote:"))
    }

    func testFileNameIsSafeAndKeepsPolishLetters() {
        let name = CallRecap.fileName(for: record(result: nil, name: "Łukasz / ../Żółć: 12"))
        XCTAssertTrue(name.hasPrefix("Doddy-call-Łukasz-Żółć-12-2026-"), name)
        XCTAssertTrue(name.hasSuffix(".txt"))
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(".."))
        XCTAssertEqual(CallRecap.fileName(for: record(result: nil, name: "///")).hasPrefix("Doddy-call-recap-"), true)
    }
}
