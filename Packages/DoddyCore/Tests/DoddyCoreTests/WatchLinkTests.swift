import DoddyCore
import XCTest

/// Apple Watch messages (ADR-232).
final class WatchLinkTests: XCTestCase {
    func testRequestsRoundTripAndOtherVersionsAreIgnored() throws {
        let tick = WatchRequest.tick(listID: UUID(), itemID: UUID(), shownDone: false)
        XCTAssertEqual(WatchRequest.decoded(try tick.encoded()), tick)
        let note = WatchRequest.saveNote(text: "Buy stamps")
        XCTAssertEqual(WatchRequest.decoded(try note.encoded()), note)
        XCTAssertNil(WatchRequest.decoded(Data(#"{"version":2,"request":{"saveNote":{"text":"x"}}}"#.utf8)))
        XCTAssertNil(WatchRequest.decoded(Data("nonsense".utf8)))
    }

    func testRepliesComeFromTheReadBackTick() throws {
        XCTAssertEqual(WatchReply(.ticked), .ticked)
        XCTAssertEqual(WatchReply(.notFound), .notFound)
        let reply = WatchReply.notSaved(reason: "A note can be up to 5000 characters.")
        XCTAssertEqual(WatchReply.decoded(try reply.encoded()), reply)
        XCTAssertEqual(WatchReply.saved.message, "Saved in Doddy on your iPhone.")
    }

    func testNotesAreCheckedBeforeSending() {
        XCTAssertNil(WatchNote.problem("Parking: level 2"))
        XCTAssertNotNil(WatchNote.problem("   "))
        XCTAssertNotNil(WatchNote.problem(String(repeating: "a", count: MemoryLimits.maxTextLength + 1)))
    }
}
