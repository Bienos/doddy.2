import Foundation
import XCTest
@testable import DoddyCore

/// Security audit 2026-11-09, finding 1: signing out must end this iPhone's authority on the messaging server
/// too, and when the server can't be reached that must stay owed (and visible) instead of being forgotten.

private final class MemoryOwed: PendingRevocationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [String] = []
    var refuses = false
    var tokens: [String] { lock.withLock { kept } }
    func load() -> [String] { lock.withLock { kept } }
    func save(_ tokens: [String]) -> Bool { lock.withLock { if refuses { return false }; kept = tokens; return true } }
}

/// Answers each request with the next status in `statuses` (or throws `offline`), and records what was asked.
private final class ServerStub: HTTPTransport, @unchecked Sendable {
    struct Offline: Error {}
    private let lock = NSLock()
    private var queue: [Int?]
    private var recorded: [HTTPRequest] = []
    /// Runs while a request is "on its way", to change things in between.
    var duringRequest: (@Sendable () -> Void)?
    init(_ statuses: [Int?]) { queue = statuses }
    var requests: [HTTPRequest] { lock.withLock { recorded } }
    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        let next = lock.withLock { () -> Int? in
            recorded.append(request)
            return queue.isEmpty ? nil : queue.removeFirst()
        }
        duringRequest?()
        guard let status = next else { throw Offline() }
        return (status, Data())
    }
}

private let server = URL(string: "https://messaging.example.com")!
private let tokenA = String(repeating: "A", count: 43)
private let tokenB = String(repeating: "B", count: 43)
private let tokenC = String(repeating: "C", count: 43)

final class MessagingDeviceRevocationTests: XCTestCase {
    // MARK: The request

    func testItAsksTheServerToEndThisIPhonesOwnTokenWithThatTokenAsTheBearerAndNothingElse() async {
        let transport = ServerStub([204])
        let outcome = await DoddyAccountLink.revokeMessagingDevice(server: server, deviceToken: tokenA, transport: transport)
        XCTAssertEqual(outcome, .revoked)
        let request = try! XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "DELETE")
        XCTAssertEqual(request.url.absoluteString, "https://messaging.example.com/v1/device")
        XCTAssertEqual(request.headers["authorization"], "Bearer \(tokenA)")
        XCTAssertNil(request.body, "no account token, no id: the token is the only thing sent")
    }

    func testEachAnswerIsReadForWhatItProves() async {
        let cases: [(Int?, DeviceRevocation)] = [
            (204, .revoked),
            (401, .revoked),         // the server no longer knows it: an earlier try got through, or it was removed
            (409, .notNeeded),       // not a Doddy account's iPhone: nothing to protect, a retry says the same
            (429, .retryLater), (500, .retryLater), (503, .retryLater),
            (404, .retryLater),      // a server that doesn't have the route yet: not confirmed
            (200, .retryLater),      // anything unexpected is not a confirmation
            (nil, .retryLater),      // no answer at all
        ]
        for (status, expected) in cases {
            let outcome = await DoddyAccountLink.revokeMessagingDevice(server: server, deviceToken: tokenA, transport: ServerStub([status]))
            XCTAssertEqual(outcome, expected, "status \(String(describing: status))")
        }
    }

    func testSomethingThatCouldNeverBeATokenIsNotSent() async {
        let transport = ServerStub([204])
        for bad in ["", "short", String(repeating: "A", count: 44), String(repeating: "é", count: 43), String(repeating: "A", count: 42) + " "] {
            let outcome = await DoddyAccountLink.revokeMessagingDevice(server: server, deviceToken: bad, transport: transport)
            XCTAssertEqual(outcome, .notNeeded)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    // MARK: Owed until answered

    @MainActor
    func testAnAnsweredRevocationIsNoLongerOwed() async {
        let owed = MemoryOwed()
        let pending = PendingDeviceRevocations(store: owed, transport: ServerStub([204]))
        await pending.revoke(tokenA, server: server)
        XCTAssertEqual(owed.tokens, [])
        XCTAssertEqual(pending.count, 0)
    }

    @MainActor
    func testOfflineKeepsTheTokenOwedAndALaterTryFinishesIt() async {
        let owed = MemoryOwed()
        let transport = ServerStub([nil, 503, 204])
        let pending = PendingDeviceRevocations(store: owed, transport: transport)

        await pending.revoke(tokenA, server: server)
        XCTAssertEqual(owed.tokens, [tokenA], "signed out here, but not revoked there: still owed, never forgotten")

        let left = await pending.retry(server: server)
        XCTAssertEqual(left, 1, "a busy server is not an answer")

        // The next launch builds a new object over the same Keychain slot: the obligation survives a restart.
        let afterRestart = PendingDeviceRevocations(store: owed, transport: transport)
        XCTAssertEqual(afterRestart.count, 1)
        let none = await afterRestart.retry(server: server)
        XCTAssertEqual(none, 0)
        XCTAssertEqual(owed.tokens, [])
        XCTAssertEqual(transport.requests.count, 3)
    }

    @MainActor
    func testRetryingAnythingAlreadyGoneIsHarmlessAndCountsAsDone() async {
        // Offline logout, then the same token is sent twice (two launches): the second gets 401, which is "gone".
        let owed = MemoryOwed()
        let pending = PendingDeviceRevocations(store: owed, transport: ServerStub([401]))
        pending.add(tokenA)
        let left = await pending.retry(server: server)
        XCTAssertEqual(left, 0)
    }

    @MainActor
    func testANotNeededAnswerEndsTheObligationToo() async {
        let owed = MemoryOwed()
        let pending = PendingDeviceRevocations(store: owed, transport: ServerStub([409]))
        pending.add(tokenA)
        let left = await pending.retry(server: server)
        XCTAssertEqual(left, 0, "retrying a 409 would never change it")
    }

    @MainActor
    func testEachOwedTokenIsAnsweredOnItsOwnAndOnlyTheAnsweredOnesLeave() async {
        let owed = MemoryOwed()
        let pending = PendingDeviceRevocations(store: owed, transport: ServerStub([204, nil, 204]))
        for token in [tokenA, tokenB, tokenC] { pending.add(token) }
        let left = await pending.retry(server: server)
        XCTAssertEqual(left, 1)
        XCTAssertEqual(owed.tokens, [tokenB], "the one with no answer stays; the others are done")
    }

    @MainActor
    func testATokenAddedWhileARetryIsOnItsWayIsNotLost() async {
        let owed = MemoryOwed()
        let transport = ServerStub([204])
        let pending = PendingDeviceRevocations(store: owed, transport: transport)
        pending.add(tokenA)
        // Signing out again (another account's token) lands while the first request is being answered.
        transport.duringRequest = { _ = owed.save([tokenA, tokenB]) }
        _ = await pending.retry(server: server)
        XCTAssertEqual(owed.tokens, [tokenB], "A was answered and left; B, written meanwhile, is still owed")
    }

    @MainActor
    func testAddingTheSameTokenTwiceKeepsOne_AndOnlyTheNewestFewAreKept() {
        let owed = MemoryOwed()
        let pending = PendingDeviceRevocations(store: owed, transport: ServerStub([]))
        pending.add(tokenA)
        pending.add(tokenA)
        XCTAssertEqual(owed.tokens, [tokenA])
        let many = (0..<(PendingDeviceRevocations.maxKept + 3)).map { String(repeating: Character(UnicodeScalar(UInt8(65 + $0))), count: 43) }
        for token in many { pending.add(token) }
        XCTAssertEqual(owed.tokens.count, PendingDeviceRevocations.maxKept)
        XCTAssertEqual(owed.tokens, Array(many.suffix(PendingDeviceRevocations.maxKept)), "the oldest give way")
    }

    @MainActor
    func testATokenTheIPhoneCouldNotWriteDownIsStillTriedOnce() async {
        let owed = MemoryOwed()
        owed.refuses = true
        let transport = ServerStub([204])
        let pending = PendingDeviceRevocations(store: owed, transport: transport)
        await pending.revoke(tokenA, server: server)
        XCTAssertEqual(transport.requests.count, 1, "no Keychain slot is no reason to skip the request")
    }

    @MainActor
    func testWhatIsOwedIsNeverDroppedBecauseTheStoreCouldNotBeRewritten() async {
        let owed = MemoryOwed()
        let pending = PendingDeviceRevocations(store: owed, transport: ServerStub([nil]))
        pending.add(tokenA)
        owed.refuses = true
        let left = await pending.retry(server: server)
        XCTAssertEqual(left, 1)
        XCTAssertEqual(owed.tokens, [tokenA])
    }
}
