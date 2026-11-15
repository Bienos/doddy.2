import Foundation
import XCTest
@testable import DoddyCore

/// Decision 2026-11-12-account-and-device-tokens, step 5: the iPhone renews its messaging-server device token by rotation
/// before it runs out, with the account it is signed in to and without asking. DOD-08 (a token counts as renewed only once it
/// is stored), DOD-11 and cross-user isolation (another account's answer is never kept).

private let server = URL(string: "https://messaging.example.com")!
private let oldToken = String(repeating: "A", count: 43)
private let newToken = String(repeating: "B", count: 43)
private let otherToken = String(repeating: "C", count: 43)
private let accountA = "6c1d9a8f-3b52-4d4e-8f70-123456789abc"
private let accountB = "11111111-2222-4333-8444-555555555555"
private let day: TimeInterval = 86_400
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func reply(account: String = accountA, token: String = newToken, expiresIn: TimeInterval = 180 * day) -> Data {
    let when = ISO8601DateFormatter().string(from: now.addingTimeInterval(expiresIn))
    return Data(#"{"accountId":"\#(account)","deviceToken":"\#(token)","expiresAt":"\#(when)"}"#.utf8)
}

private final class Wire: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    private var answers: [(status: Int, body: Data)]
    private var gate: CheckedContinuation<Void, Never>?
    private var held = false
    var offline = false
    init(_ answers: [(status: Int, body: Data)]) { self.answers = answers }
    var requests: [HTTPRequest] { lock.withLock { recorded } }
    /// The next request waits until `release()`.
    func hold() { lock.withLock { held = true } }
    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        lock.withLock { recorded.append(request) }
        if lock.withLock({ held }) {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in lock.withLock { gate = c } }
        }
        if offline { throw URLError(.notConnectedToInternet) }
        return lock.withLock { answers.count > 1 ? answers.removeFirst() : answers[0] }
    }
    func release() {
        let c = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            held = false
            let g = gate
            gate = nil
            return g
        }
        c?.resume()
    }
    func sentDeviceToken(_ i: Int) -> String? {
        guard let body = requests[i].body, let json = try? JSONSerialization.jsonObject(with: body) as? [String: String] else { return nil }
        return json["deviceToken"]
    }
}

private final class Tokens: ServerCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    private var savedTokens: [String] = []
    var failSave = false
    init(_ token: String?) { self.token = token }
    var saved: [String] { lock.withLock { savedTokens } }
    func load() throws -> String? { lock.withLock { token } }
    func save(_ token: String) throws {
        if failSave { throw URLError(.cannotWriteToFile) }
        lock.withLock { self.token = token; savedTokens.append(token) }
    }
    func delete() throws { lock.withLock { token = nil } }
}

private final class Records: MessagingTokenRecordStore, @unchecked Sendable {
    private let lock = NSLock()
    private var record = MessagingTokenRecord()
    func load() -> MessagingTokenRecord { lock.withLock { record } }
    func save(_ record: MessagingTokenRecord) { lock.withLock { self.record = record } }
}

private final class Clock: @unchecked Sendable { var date = now }
private final class Discarded: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [String] = []
    var tokens: [String] { lock.withLock { list } }
    func add(_ token: String) { lock.withLock { list.append(token) } }
}

@MainActor
private final class Account: MessagingRenewalAccount {
    var session: DoddyAccountSession?
    var identityEpoch = 1
    var refreshes = 0
    var offline = false
    init(user: String? = "user-1") { session = user.map(Account.make) }
    static func make(_ user: String) -> DoddyAccountSession {
        DoddyAccountSession(accessToken: "access-not-real", refreshToken: "refresh-not-real", expiresAt: now.addingTimeInterval(3600), userID: user, email: nil, method: .apple)
    }
    func freshSession() async -> DoddyAccountSession? { offline ? nil : session }
    func refreshAfterRefusal() async throws -> String {
        refreshes += 1
        return "access-not-real"
    }
}

@MainActor
private struct Rig {
    let wire: Wire
    let tokens: Tokens
    let records = Records()
    let account: Account
    let renewal: MessagingTokenRenewal
    let clock = Clock()
    let discarded = Discarded()

    init(answers: [(status: Int, body: Data)] = [(200, reply())], token: String? = oldToken, signedIn: Bool = true, inUse: Bool = true) {
        wire = Wire(answers)
        tokens = Tokens(token)
        account = Account(user: signedIn ? "user-1" : nil)
        let clock = self.clock, discarded = self.discarded
        renewal = MessagingTokenRenewal(
            server: { server }, inUse: { inUse }, tokens: tokens, records: records, account: account, transport: wire,
            now: { clock.date }, discard: { discarded.add($0) })
    }

    /// The token known to expire at `expiresIn` from now, as a sign-in would have recorded it.
    func know(expiresIn: TimeInterval?, accountID: String? = accountA, lastAttempt: Date? = nil, token: String = oldToken) {
        records.save(MessagingTokenRecord(
            tokenFingerprint: MessagingTokenRenewal.fingerprint(token), expiresAt: expiresIn.map { now.addingTimeInterval($0) },
            accountID: accountID, lastAttempt: lastAttempt))
    }
}

private extension Date {
    var roundedToSecond: Date { Date(timeIntervalSince1970: timeIntervalSince1970.rounded()) }
}

@MainActor
final class MessagingTokenRenewalTests: XCTestCase {
    // MARK: When

    func testRenewsWithinFourteenDaysOfTheEnd() async throws {
        let rig = Rig()
        rig.know(expiresIn: 14 * day - 1)
        let result = await rig.renewal.renewIfDue()
        XCTAssertEqual(result, .renewed)
        XCTAssertEqual(rig.wire.requests.count, 1)
        XCTAssertEqual(rig.wire.requests[0].url.absoluteString, "https://messaging.example.com/v1/accounts/sign-in")
        XCTAssertEqual(rig.wire.sentDeviceToken(0), oldToken, "rotation sends the current device token")
    }

    func testDoesNothingWhileMoreThanFourteenDaysRemain() async {
        let rig = Rig()
        rig.know(expiresIn: 14 * day + 60)
        let result = await rig.renewal.renewIfDue()
        XCTAssertEqual(result, .notDue)
        XCTAssertTrue(rig.wire.requests.isEmpty)
    }

    func testATokenPastItsEndIsRenewedToo() async {
        let rig = Rig()
        rig.know(expiresIn: -day)
        let result = await rig.renewal.renewIfDue()
        XCTAssertEqual(result, .renewed)
    }

    func testATokenWithNoKnownEndIsRenewedOnceAtTheNextChance() async throws {
        let rig = Rig()
        // An older stored token: nothing recorded next to it.
        let first = await rig.renewal.renewIfDue()
        XCTAssertEqual(first, .renewed)
        XCTAssertEqual(rig.records.load().expiresAt, now.addingTimeInterval(180 * day).roundedToSecond)
        // The new token has an end, 180 days away: nothing more to do, even a day later.
        rig.clock.date = now.addingTimeInterval(2 * day)
        let second = await rig.renewal.renewIfDue()
        XCTAssertEqual(second, .notDue)
        XCTAssertEqual(rig.wire.requests.count, 1)
    }

    func testAnEndRecordedForAnotherTokenCountsAsUnknown() async {
        let rig = Rig()
        rig.know(expiresIn: 170 * day, token: otherToken)
        let result = await rig.renewal.renewIfDue()
        XCTAssertEqual(result, .renewed, "the recorded end belongs to a token that is no longer the stored one")
    }

    func testAtMostOneTryADay() async {
        let rig = Rig(answers: [(503, Data(#"{"error":"account_check_unavailable"}"#.utf8))])
        rig.know(expiresIn: day)
        let first = await rig.renewal.renewIfDue()
        XCTAssertEqual(first, .kept)
        rig.clock.date = now.addingTimeInterval(day - 60)
        let second = await rig.renewal.renewIfDue()
        XCTAssertEqual(second, .tooSoon)
        XCTAssertEqual(rig.wire.requests.count, 1)
        rig.clock.date = now.addingTimeInterval(day + 60)
        let third = await rig.renewal.renewIfDue()
        XCTAssertEqual(third, .kept)
        XCTAssertEqual(rig.wire.requests.count, 2, "a day later it tries again")
    }

    func testTheTryIsCountedEvenWhenTheAnswerNeverArrives() async {
        let rig = Rig()
        rig.wire.offline = true
        rig.know(expiresIn: day)
        _ = await rig.renewal.renewIfDue()
        XCTAssertEqual(rig.records.load().lastAttempt, now)
    }

    // MARK: Single flight

    func testTwoCallsAtOnceSendOneRequest() async {
        let rig = Rig()
        rig.know(expiresIn: day)
        rig.wire.hold()
        let first = Task { @MainActor in await rig.renewal.renewIfDue() }
        while rig.wire.requests.isEmpty { await Task.yield() }
        let second = await rig.renewal.renewIfDue()
        XCTAssertEqual(second, .alreadyRunning)
        rig.wire.release()
        let done = await first.value
        XCTAssertEqual(done, .renewed)
        XCTAssertEqual(rig.wire.requests.count, 1)
    }

    // MARK: Failure

    func testOfflineKeepsTheOldTokenAndItsEnd() async throws {
        let rig = Rig()
        rig.wire.offline = true
        rig.know(expiresIn: 3 * day)
        let result = await rig.renewal.renewIfDue()
        XCTAssertEqual(result, .kept)
        XCTAssertEqual(try rig.tokens.load(), oldToken)
        XCTAssertEqual(rig.records.load().expiresAt, now.addingTimeInterval(3 * day))
        XCTAssertTrue(rig.tokens.saved.isEmpty)
    }

    func testTheAccountsOwnTokenNotRenewableKeepsTheOldToken() async throws {
        let rig = Rig()
        rig.account.offline = true
        rig.know(expiresIn: 3 * day)
        let result = await rig.renewal.renewIfDue()
        XCTAssertEqual(result, .kept)
        XCTAssertTrue(rig.wire.requests.isEmpty)
        XCTAssertEqual(try rig.tokens.load(), oldToken)
    }

    func testARefusedAccountTokenIsRefreshedAndAskedOnceMore() async throws {
        let rig = Rig(answers: [(401, Data(#"{"error":"unauthorized"}"#.utf8)), (200, reply())])
        rig.know(expiresIn: 3 * day)
        let result = await rig.renewal.renewIfDue()
        XCTAssertEqual(result, .renewed)
        XCTAssertEqual(rig.account.refreshes, 1)
        XCTAssertEqual(rig.wire.requests.count, 2)
        XCTAssertEqual(try rig.tokens.load(), newToken)
    }

    func testAStillRefusedAccountLeavesTheOldTokenForTheExistingSignInPath() async throws {
        let rig = Rig(answers: [(401, Data(#"{"error":"unauthorized"}"#.utf8))])
        rig.know(expiresIn: 3 * day)
        let result = await rig.renewal.renewIfDue()
        XCTAssertEqual(result, .kept)
        XCTAssertEqual(rig.account.refreshes, 1, "refreshed once, not in a loop")
        XCTAssertEqual(rig.wire.requests.count, 2)
        XCTAssertEqual(try rig.tokens.load(), oldToken, "nothing is deleted here: a refused device token is dropped by the client on its own 401")
    }

    func testAConflictKeepsTheOldToken() async throws {
        let rig = Rig(answers: [(409, Data(#"{"error":"device_signed_in_to_another_account"}"#.utf8))])
        rig.know(expiresIn: 3 * day)
        let result = await rig.renewal.renewIfDue()
        XCTAssertEqual(result, .kept)
        XCTAssertEqual(try rig.tokens.load(), oldToken)
    }

    // MARK: Which account

    func testAnotherAccountsAnswerIsRefusedAndNotStored() async throws {
        let rig = Rig(answers: [(200, reply(account: accountB))])
        rig.know(expiresIn: 3 * day, accountID: accountA)
        let result = await rig.renewal.renewIfDue()
        XCTAssertEqual(result, .refusedOtherAccount)
        XCTAssertEqual(try rig.tokens.load(), oldToken)
        XCTAssertTrue(rig.tokens.saved.isEmpty)
        XCTAssertEqual(rig.records.load().accountID, accountA)
        XCTAssertEqual(rig.discarded.tokens, [newToken], "the token that came back is handed over to be ended, not kept")
    }

    func testAnAccountThatChangedWhileTheServerAnsweredIsNotStored() async throws {
        let rig = Rig()
        rig.know(expiresIn: 3 * day)
        rig.wire.hold()
        let task = Task { @MainActor in await rig.renewal.renewIfDue() }
        while rig.wire.requests.isEmpty { await Task.yield() }
        rig.account.identityEpoch += 1
        rig.account.session = Account.make("user-2")
        rig.wire.release()
        let result = await task.value
        XCTAssertEqual(result, .refusedOtherAccount)
        XCTAssertEqual(try rig.tokens.load(), oldToken)
        XCTAssertEqual(rig.discarded.tokens, [newToken])
    }

    func testATokenReplacedMeanwhileByTheClientIsNotOverwritten() async throws {
        let rig = Rig()
        rig.know(expiresIn: 3 * day)
        rig.wire.hold()
        let task = Task { @MainActor in await rig.renewal.renewIfDue() }
        while rig.wire.requests.isEmpty { await Task.yield() }
        try rig.tokens.save(otherToken)
        rig.wire.release()
        let result = await task.value
        XCTAssertEqual(result, .kept)
        XCTAssertEqual(try rig.tokens.load(), otherToken)
        XCTAssertEqual(rig.discarded.tokens, [newToken])
    }

    func testSignedOutDoesNothing() async {
        let rig = Rig(signedIn: false)
        rig.know(expiresIn: day)
        let result = await rig.renewal.renewIfDue()
        XCTAssertEqual(result, .notApplicable)
        XCTAssertTrue(rig.wire.requests.isEmpty)
    }

    func testAServerNotUsedForTheAccountDoesNothing() async {
        let rig = Rig(inUse: false)
        let result = await rig.renewal.renewIfDue()
        XCTAssertEqual(result, .notApplicable)
        XCTAssertTrue(rig.wire.requests.isEmpty)
    }

    func testNoStoredTokenDoesNothing() async {
        let rig = Rig(token: nil)
        let result = await rig.renewal.renewIfDue()
        XCTAssertEqual(result, .noToken)
        XCTAssertTrue(rig.wire.requests.isEmpty, "with no token the next call signs in by itself")
    }

    // MARK: What is stored

    func testRotationStoresTheNewTokenAndItsEndAndKeepsOnlyOne() async throws {
        let rig = Rig(answers: [(200, reply(expiresIn: 180 * day))])
        rig.know(expiresIn: 2 * day)
        let result = await rig.renewal.renewIfDue()
        XCTAssertEqual(result, .renewed)
        XCTAssertEqual(try rig.tokens.load(), newToken)
        XCTAssertEqual(rig.tokens.saved, [newToken])
        let record = rig.records.load()
        XCTAssertEqual(record.tokenFingerprint, MessagingTokenRenewal.fingerprint(newToken))
        XCTAssertEqual(record.expiresAt, now.addingTimeInterval(180 * day).roundedToSecond)
        XCTAssertEqual(record.accountID, accountA)
        XCTAssertNotEqual(record.tokenFingerprint, MessagingTokenRenewal.fingerprint(oldToken), "the old token is not kept")
        let written = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
        XCTAssertFalse(written.contains(newToken), "the record holds no token")
    }

    func testAnUnsavedTokenIsNotCountedAsRenewed() async throws {
        let rig = Rig()
        rig.tokens.failSave = true
        rig.know(expiresIn: 2 * day)
        let result = await rig.renewal.renewIfDue()
        XCTAssertEqual(result, .kept)
        XCTAssertEqual(try rig.tokens.load(), oldToken)
        XCTAssertEqual(rig.records.load().expiresAt, now.addingTimeInterval(2 * day), "the end of the token still kept")
    }

    func testASignInRecordsTheEndNextToTheToken() async {
        let rig = Rig(answers: [(200, reply(token: newToken))])
        let outcome = await rig.renewal.signIn(server: server, account: Account.make("user-1"), earlierDeviceToken: nil)
        XCTAssertEqual(outcome, .signedIn(accountID: accountA, deviceToken: newToken))
        let record = rig.records.load()
        XCTAssertEqual(record.tokenFingerprint, MessagingTokenRenewal.fingerprint(newToken))
        XCTAssertEqual(record.expiresAt, now.addingTimeInterval(180 * day).roundedToSecond)
        XCTAssertEqual(record.accountID, accountA)
    }

    func testForgettingClearsTheRecord() {
        let rig = Rig()
        rig.know(expiresIn: day, lastAttempt: now)
        rig.renewal.forget()
        XCTAssertEqual(rig.records.load(), MessagingTokenRecord())
    }

    func testTheServersTimeIsReadWithAndWithoutFractionalSeconds() {
        XCTAssertEqual(DoddyAccountLink.parseServerTime("2026-05-14T10:00:00.000Z"), DoddyAccountLink.parseServerTime("2026-05-14T10:00:00Z"))
        XCTAssertNotNil(DoddyAccountLink.parseServerTime("2026-05-14T10:00:00.123Z"))
        XCTAssertNil(DoddyAccountLink.parseServerTime("soon"))
    }
}
