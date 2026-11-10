import XCTest
@testable import DoddyCore

final class VoiceTokenShelfTests: XCTestCase {
    private let server = URL(string: "https://voice.example.com/api/voice-token")!
    private let other = URL(string: "https://other.example.com/api/voice-token")!
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testFetchesAheadOnlyForASignedInAccount() {
        let shelf = VoiceTokenShelf()
        XCTAssertFalse(shelf.shouldWarm(endpoint: server, owner: nil, now: t0))
        XCTAssertFalse(shelf.shouldWarm(endpoint: server, owner: "", now: t0))
        XCTAssertTrue(shelf.shouldWarm(endpoint: server, owner: "acct-1", now: t0))
    }

    func testAYoungTokenIsTakenOnceByTheSameAccountAndServer() {
        var shelf = VoiceTokenShelf()
        shelf.warmStarted(now: t0)
        shelf.store("tok", endpoint: server, owner: "acct-1", fetchedAt: t0)
        XCTAssertFalse(shelf.shouldWarm(endpoint: server, owner: "acct-1", now: t0.addingTimeInterval(60)), "one is held")
        XCTAssertEqual(shelf.take(endpoint: server, owner: "acct-1", now: t0.addingTimeInterval(60)), "tok")
        XCTAssertNil(shelf.take(endpoint: server, owner: "acct-1", now: t0.addingTimeInterval(61)), "used once")
        XCTAssertFalse(shelf.isHolding)
    }

    func testAnotherAccountOrServerNeverGetsIt() {
        var shelf = VoiceTokenShelf()
        shelf.store("tok", endpoint: server, owner: "acct-1", fetchedAt: t0)
        XCTAssertNil(shelf.take(endpoint: server, owner: "acct-2", now: t0.addingTimeInterval(5)))
        XCTAssertFalse(shelf.isHolding, "thrown away, not kept for later")
        shelf.store("tok", endpoint: server, owner: "acct-1", fetchedAt: t0)
        XCTAssertNil(shelf.take(endpoint: other, owner: "acct-1", now: t0.addingTimeInterval(5)))
        shelf.store("tok", endpoint: server, owner: "acct-1", fetchedAt: t0)
        XCTAssertNil(shelf.take(endpoint: server, owner: nil, now: t0.addingTimeInterval(5)), "signed out")
    }

    func testAnOldTokenIsThrownAway() {
        var shelf = VoiceTokenShelf()
        shelf.store("tok", endpoint: server, owner: "acct-1", fetchedAt: t0)
        XCTAssertNil(shelf.take(endpoint: server, owner: "acct-1", now: t0.addingTimeInterval(VoiceTokenShelf.maxAge)))
        shelf.store("tok", endpoint: server, owner: "acct-1", fetchedAt: t0)
        XCTAssertNil(shelf.take(endpoint: server, owner: "acct-1", now: t0.addingTimeInterval(-1)), "a clock that went back")
    }

    func testAnUnusedFetchWaitsBeforeTheNextOne() {
        var shelf = VoiceTokenShelf()
        shelf.warmStarted(now: t0)
        shelf.store("tok", endpoint: server, owner: "acct-1", fetchedAt: t0)
        // Never used: once it is too old, the next fetch ahead waits for the cool-down.
        let stale = t0.addingTimeInterval(VoiceTokenShelf.maxAge + 1)
        XCTAssertFalse(shelf.shouldWarm(endpoint: server, owner: "acct-1", now: stale))
        XCTAssertTrue(shelf.shouldWarm(endpoint: server, owner: "acct-1", now: t0.addingTimeInterval(VoiceTokenShelf.idleCooldown)))
    }

    func testAUsedFetchAllowsTheNextOneAtOnce() {
        var shelf = VoiceTokenShelf()
        shelf.warmStarted(now: t0)
        shelf.store("tok", endpoint: server, owner: "acct-1", fetchedAt: t0)
        _ = shelf.take(endpoint: server, owner: "acct-1", now: t0.addingTimeInterval(10))
        XCTAssertTrue(shelf.shouldWarm(endpoint: server, owner: "acct-1", now: t0.addingTimeInterval(20)))
    }

    func testAFailedFetchStillCountsTowardTheCoolDown() {
        var shelf = VoiceTokenShelf()
        shelf.warmStarted(now: t0) // and nothing stored: the fetch failed
        XCTAssertFalse(shelf.shouldWarm(endpoint: server, owner: "acct-1", now: t0.addingTimeInterval(60)))
    }

    func testClearDropsWhatIsHeld() {
        var shelf = VoiceTokenShelf()
        shelf.store("tok", endpoint: server, owner: "acct-1", fetchedAt: t0)
        shelf.clear()
        XCTAssertNil(shelf.take(endpoint: server, owner: "acct-1", now: t0.addingTimeInterval(1)))
    }

    func testEmptyValuesAreNotKept() {
        var shelf = VoiceTokenShelf()
        shelf.store("", endpoint: server, owner: "acct-1", fetchedAt: t0)
        XCTAssertFalse(shelf.isHolding)
        shelf.store("tok", endpoint: server, owner: "", fetchedAt: t0)
        XCTAssertFalse(shelf.isHolding)
    }
}
