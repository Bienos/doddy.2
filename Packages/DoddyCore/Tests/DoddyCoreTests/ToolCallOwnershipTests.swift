import XCTest
@testable import DoddyCore

/// ADR-443: a tool call from an ended conversation never shows a card, runs a change or answers in
/// the next one. These model the controller's numbering (`startAttempt` goes up on every start and
/// every stop); the controller's own wiring needs Xcode (Mac checklist).
final class ToolCallOwnershipTests: XCTestCase {
    func testACallBelongsOnlyToTheConversationItArrivedIn() {
        var calls = ToolCallOwnership()
        calls.arrived("call-1", attempt: 1)
        XCTAssertTrue(calls.belongs("call-1", to: 1))
        XCTAssertFalse(calls.belongs("call-1", to: 2))
    }

    func testEndingMakesAnInFlightCallStaleAndANewStartDoesNotRevive() {
        var attempt = 1                       // start A
        var calls = ToolCallOwnership()
        calls.starting(attempt)
        calls.arrived("gmail-draft", attempt: attempt)   // A asks; the server prepare is awaited
        attempt += 1                           // End
        XCTAssertFalse(calls.belongs("gmail-draft", to: attempt))
        attempt += 1                           // start B
        calls.starting(attempt)
        calls.arrived("b-1", attempt: attempt)
        // A's prepare returns now: no card, no change, no result in B.
        XCTAssertFalse(calls.belongs("gmail-draft", to: attempt))
        XCTAssertTrue(calls.belongs("b-1", to: attempt))
    }

    func testUnknownIdsFailClosed() {
        let calls = ToolCallOwnership()
        XCTAssertFalse(calls.belongs("never-seen", to: 0))
    }

    func testTheFirstRecordWins() {
        var calls = ToolCallOwnership()
        calls.arrived("dup", attempt: 1)
        calls.arrived("dup", attempt: 3)
        XCTAssertTrue(calls.belongs("dup", to: 1))
        XCTAssertFalse(calls.belongs("dup", to: 3))
    }

    func testStartingForgetsEarlierConversations() {
        var calls = ToolCallOwnership()
        for i in 0..<50 { calls.arrived("a-\(i)", attempt: 1) }
        calls.arrived("b", attempt: 3)
        calls.starting(3)
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(calls.belongs("b", to: 3))
        // A late call of A recorded after B started still never belongs to B.
        calls.arrived("a-late", attempt: 1)
        XCTAssertFalse(calls.belongs("a-late", to: 3))
    }
}
