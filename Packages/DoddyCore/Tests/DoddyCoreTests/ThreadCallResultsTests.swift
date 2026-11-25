@testable import DoddyCore
import XCTest

/// Written without a Swift toolchain at hand: run `make test-core` before relying on it.
final class ThreadCallResultsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)

    private func card(_ outcome: String = "answered") throws -> CallResultCard {
        try JSONDecoder().decode(CallResultCard.self, from: Data("""
        {"outcome":"\(outcome)","source":"elevenlabs","confidence":"high","confidenceReasons":[],"summary":"s","summaryBy":"rules",
         "quote":null,"transcript":[],"nextStep":{"kind":"none","text":""},"warnings":[],"callbackPromised":false}
        """.utf8))
    }

    private func record(_ name: String, daysAgo: Double, answered: Bool = true) throws -> StoredCallCase {
        var brief = CallBriefDraft()
        brief.calleeName = name
        var r = StoredCallCase(id: UUID(), createdAt: now.addingTimeInterval(-daysAgo * 86_400), state: "finished", brief: brief,
                               result: answered ? try card() : nil)
        r.updatedAt = now.addingTimeInterval(-daysAgo * 86_400)
        return r
    }

    func testOnlyAnsweredRecentCallsAreOfferedNewestFewOldestFirst() throws {
        let list = [try record("a", daysAgo: 1), try record("b", daysAgo: 0.5), try record("old", daysAgo: 9),
                    try record("going", daysAgo: 0.1, answered: false), try record("c", daysAgo: 2), try record("d", daysAgo: 3)]
        XCTAssertEqual(ThreadCallResults.shown(list, now: now).map(\.brief.calleeName), ["c", "a", "b"])
    }

    func testNothingToShowWhenNoCallHasAnAnswer() throws {
        XCTAssertTrue(ThreadCallResults.shown([try record("x", daysAgo: 1, answered: false)], now: now).isEmpty)
        XCTAssertTrue(ThreadCallResults.shown([], now: now).isEmpty)
    }

    func testACallNobodyAnsweredSaysSoInsteadOfARecap() throws {
        // Owner, 25 Nov 2026: a missed call looked like a finished one ("Doddy called Anna. See the recap.").
        var talked = try record("Anna", daysAgo: 0.2)
        XCTAssertEqual(ThreadCallResults.reach(of: talked), .talked)
        for outcome in ["no_answer", "busy", "voicemail", "failed", "not_placed", "wrong_number", "ivr", "stopped", "unknown", "something_new"] {
            talked.result = try card(outcome)
            XCTAssertEqual(ThreadCallResults.reach(of: talked), .notReached, outcome)
        }
        talked.result = try card("taken_over")
        XCTAssertEqual(ThreadCallResults.reach(of: talked), .talked, "the person took the call over and talked")
        XCTAssertEqual(ThreadCallResults.reach(of: try record("x", daysAgo: 0, answered: false)), .notReached)
    }
}
