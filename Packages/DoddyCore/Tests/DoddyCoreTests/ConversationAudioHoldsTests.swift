@testable import DoddyCore
import XCTest

/// Decision 2026-11-12-action-button-audio-and-island: a start without opening Doddy keeps LiveKit off the
/// audio session until that conversation is over; every other start leaves it to LiveKit.
final class ConversationAudioHoldsTests: XCTestCase {
    func testAStartInTheAppLeavesTheSessionToLiveKit() {
        var holds = ConversationAudioHolds()
        XCTAssertTrue(holds.liveKitSetsUpSession(for: nil))
        XCTAssertNil(holds.current)
        // Nothing was held, so its end switches nothing off.
        XCTAssertFalse(holds.release(nil))
    }

    func testAStartWithoutOpeningKeepsLiveKitOffUntilItsConversationEnds() {
        var holds = ConversationAudioHolds()
        let hold = holds.take()
        XCTAssertFalse(holds.liveKitSetsUpSession(for: hold))
        XCTAssertEqual(holds.current, hold)
        XCTAssertTrue(holds.release(hold))
        XCTAssertNil(holds.current)
        // A second release (stop after a failure) does nothing more.
        XCTAssertFalse(holds.release(hold))
    }

    func testALateReleaseOfAnEarlierConversationLeavesTheNewerOneAlone() {
        var holds = ConversationAudioHolds()
        let first = holds.take()
        // The next press takes the session again before the first one's end has been handled.
        let second = holds.take()
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(holds.release(first))
        XCTAssertEqual(holds.current, second)
        XCTAssertFalse(holds.liveKitSetsUpSession(for: second))
    }

    func testAStartInTheAppDropsAHoldLeftOverFromAnEarlierConversation() {
        var holds = ConversationAudioHolds()
        let stale = holds.take()
        XCTAssertTrue(holds.liveKitSetsUpSession(for: nil))
        XCTAssertNil(holds.current)
        // The earlier conversation's end then mustn't switch off the session the new one uses.
        XCTAssertFalse(holds.release(stale))
    }

    func testAHoldThatIsNoLongerInForceDoesNotKeepLiveKitOff() {
        var holds = ConversationAudioHolds()
        let first = holds.take()
        _ = holds.take()
        XCTAssertTrue(holds.liveKitSetsUpSession(for: first))
        XCTAssertNil(holds.current)
    }
}
