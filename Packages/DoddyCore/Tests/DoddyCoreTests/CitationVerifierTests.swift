import XCTest
@testable import DoddyCore

/// Acceptance A-14: approved memory citations only.
final class CitationVerifierTests: XCTestCase {
    private func request(with records: [MemoryRecord]) -> AssistantRequest {
        AssistantRequest(sessionID: UUID(), userText: "q", groundingMemories: records.map { candidate($0) })
    }

    func testCitingASentNoteResolvesToTheRealRecord() throws {
        let a = try makeRecord("A note"), b = try makeRecord("B note")
        let verified = try CitationVerifier.verify(
            AssistantReply(text: "From B", citedMemoryIDs: [b.id]), for: request(with: [a, b]))
        XCTAssertEqual(verified.sources, [b])
        XCTAssertEqual(verified.basis, .savedNotes)
    }

    func testAnIdThatWasNeverSentIsRejected() throws {
        let sent = try makeRecord()
        XCTAssertThrowsError(try CitationVerifier.verify(
            AssistantReply(text: "x", citedMemoryIDs: [UUID()]), for: request(with: [sent]))
        ) { XCTAssertEqual($0 as? AssistantError, .invalidCitations) }
    }

    func testCitationsAreRejectedWhenNothingWasSent() {
        XCTAssertThrowsError(try CitationVerifier.verify(
            AssistantReply(text: "x", citedMemoryIDs: [UUID()]), for: request(with: []))
        ) { XCTAssertEqual($0 as? AssistantError, .invalidCitations) }
    }

    func testOneBadIdSpoilsAnOtherwiseValidReply() throws {
        let sent = try makeRecord()
        XCTAssertThrowsError(try CitationVerifier.verify(
            AssistantReply(text: "x", citedMemoryIDs: [sent.id, UUID()]), for: request(with: [sent]))
        ) { XCTAssertEqual($0 as? AssistantError, .invalidCitations) }
    }

    func testDuplicateCitationIsRejected() throws {
        let sent = try makeRecord()
        XCTAssertThrowsError(try CitationVerifier.verify(
            AssistantReply(text: "x", citedMemoryIDs: [sent.id, sent.id]), for: request(with: [sent]))
        ) { XCTAssertEqual($0 as? AssistantError, .invalidCitations) }
    }

    func testNoCitationsMeansGeneralNotFromYourNotes() throws {
        let verified = try CitationVerifier.verify(AssistantReply(text: "Paris is in France."), for: request(with: []))
        XCTAssertEqual(verified.basis, .general)
        XCTAssertTrue(verified.sources.isEmpty)
    }

    func testBlankAnswerIsMalformedNotAnAnswer() {
        XCTAssertThrowsError(try CitationVerifier.verify(AssistantReply(text: " \n "), for: request(with: []))) {
            XCTAssertEqual($0 as? AssistantError, .malformedResponse)
        }
    }
}
