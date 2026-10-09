import XCTest
@testable import DoddyCore

final class QuickAccessTests: XCTestCase {
    func testAskReplyOnlyStatesStoredText() throws {
        XCTAssertEqual(ShortcutReply.ask(.noMatch), RecallCopy.noMatch)
        let records = try (1...5).map {
            try MemoryRecord(id: UUID(), rawText: "Note \($0)", source: .explicitText, capturedAt: Date(timeIntervalSince1970: 0))
        }
        let reply = ShortcutReply.ask(.matches(records.map { MemoryCandidate(record: $0, matchedTerms: ["note"]) }))
        XCTAssertEqual(reply, "I found 5 saved notes:\n“Note 1”\n“Note 2”\n“Note 3”\n…and 2 more. Open Doddy to see them all.")
    }

    func testTapTestNeedsAShortcutBeforeTheUserCanConfirm() {
        var test = ShortcutTest()
        XCTAssertFalse(test.receiveShortcut(at: Date(timeIntervalSince1970: 1)), "not armed: the shortcut should start a conversation")
        test.confirmBackTap()
        XCTAssertEqual(test.phase, .idle, "no confirmation without a received shortcut")

        test.start()
        XCTAssertTrue(test.receiveShortcut(at: Date(timeIntervalSince1970: 2)))
        XCTAssertFalse(test.receiveShortcut(at: Date(timeIntervalSince1970: 3)), "only the first arrival counts")
        test.confirmBackTap()
        XCTAssertEqual(test.phase, .confirmedBackTap(at: Date(timeIntervalSince1970: 2)))
    }

    func testBackTapStatusNeverClaimsSystemVerification() {
        XCTAssertEqual(QuickAccessStatus.backTap(testedAt: nil), "Not tested")
        XCTAssertTrue(QuickAccessStatus.backTap(testedAt: Date(timeIntervalSince1970: 0)).hasPrefix("Tested by you · "))
    }
}
