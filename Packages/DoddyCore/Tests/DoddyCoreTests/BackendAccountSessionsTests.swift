import Foundation
import XCTest
@testable import DoddyCore

/// One token per server (decision 2026-11-12-one-token-per-server), the app's half for the backend `doddy`: the iPhone
/// keeps ONE backend session for the signed-in Doddy account (`POST /v1/session/account`, `ds1` of 30 days), apart from
/// the earlier device session. With none, a refused one, or one near its end it exchanges the account's FRESH Supabase
/// token; when no session can be had it falls back to the Supabase token exactly as before and remembers nothing wrong;
/// signing out forgets the session here at once and keeps the backend's `DELETE /v1/web/devices/:id` owed until the
/// server confirms it (DOD-08), nothing of the session staying behind on this iPhone (DOD-11).
///
/// The server here is a model of the real one (`backend/src/accountSession.ts`, `devices.ts`): a renewal is the same row
/// and a new token, a revoked row gives the next exchange a new id, a session names its row and dies with it. Every token
/// is made up.
///
/// Platforms: iPhone. The Watch and Mac apps are paused.

private let exchange = "POST /v1/session/account"
private let revoke = "DELETE /v1/web/devices"

@MainActor
final class BackendAccountSessionsTests: XCTestCase {
    private func session(_ h: BackendTestHarness, file: StaticString = #filePath, line: UInt = #line) async throws -> String {
        let token = await h.sessions.token(for: backendTestServer)
        return try XCTUnwrap(token, "a session", file: file, line: line)
    }

    // MARK: Asking for the session

    func testWithNoSessionItExchangesAFreshSupabaseTokenAndKeepsTheSession() async throws {
        let h = BackendTestHarness()
        let token = try await session(h)
        XCTAssertEqual(h.server.seen.count, 1)
        let request = try XCTUnwrap(h.server.seen.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/session/account")
        XCTAssertEqual(request.bearer, "supabase-1-not-real", "the account's token goes in the header, once")
        XCTAssertEqual(request.body, #"{"deviceId":"\#(backendTestDeviceID)"}"#, "and the iPhone's device id is the whole body")
        XCTAssertEqual(h.account.freshCalls, 1)
        let kept = try XCTUnwrap(h.records.record, "kept in its own Keychain item, for the next launch")
        XCTAssertEqual(kept.token, token)
        XCTAssertEqual(kept.accountID, "account-1")
        XCTAssertEqual(kept.origin, BoundSessionToken(token: "x", issuedBy: backendTestServer)?.origin, "bound to the server that made it")
        XCTAssertEqual(kept.expiresAt, h.clock.addingTimeInterval(ModelBackendServer.thirtyDays), "the expiry the server wrote, not a guess")
        XCTAssertEqual(kept.deviceListID, h.server.rowID(of: token), "the row the sign-out will name")
        XCTAssertEqual(h.server.everydayStatus(for: token), 200)
    }

    func testAFreshSessionIsUsedWithoutAnyRequestAndSurvivesARestart() async throws {
        let h = BackendTestHarness()
        let first = try await session(h)
        let again = await h.sessions.token(for: backendTestServer)
        h.passDays(10)
        let later = await h.sessions.token(for: backendTestServer)
        let afterRestart = await h.makeSessions().token(for: backendTestServer)
        XCTAssertEqual(again, first)
        XCTAssertEqual(later, first)
        XCTAssertEqual(afterRestart, first, "the next launch finds it in the Keychain item")
        XCTAssertEqual(h.server.count(exchange), 1, "one exchange in all")
        XCTAssertEqual(h.account.freshCalls, 1, "a session in use doesn't even ask for the account's token")
    }

    func testSignedOutThereIsNothingToAskForAndNothingIsSent() async {
        let h = BackendTestHarness()
        h.account.accountID = nil
        let token = await h.sessions.token(for: backendTestServer)
        XCTAssertNil(token)
        XCTAssertTrue(h.server.seen.isEmpty)
        XCTAssertNil(h.records.record)
    }

    func testWithoutAnAccountTokenNothingIsSent() async {
        let h = BackendTestHarness()
        h.account.token = nil   // the sign-in service couldn't be reached
        let token = await h.sessions.token(for: backendTestServer)
        XCTAssertNil(token)
        XCTAssertTrue(h.server.seen.isEmpty)
    }

    func testWithoutADeviceIdAllowedForThisAddressNothingIsSentAndNothingIsAsked() async {
        // The device id goes only to an address the app's policy lets through (ADR-720): the app answers nil otherwise.
        let h = BackendTestHarness()
        h.deviceID = nil
        let token = await h.sessions.token(for: backendTestServer)
        XCTAssertNil(token)
        XCTAssertTrue(h.server.seen.isEmpty)
        XCTAssertEqual(h.account.freshCalls, 0)
    }

    // MARK: Renewing, two days before the end

    func testWithinTwoDaysOfTheEndItIsExchangedAgainWithAFreshTokenAndTheNewOneIsKept() async throws {
        let h = BackendTestHarness()
        let first = try await session(h)
        let before = try XCTUnwrap(h.records.record)
        h.passDays(27)   // three days left: not yet
        let notYet = await h.sessions.token(for: backendTestServer)
        XCTAssertEqual(notYet, first)
        XCTAssertEqual(h.server.count(exchange), 1)
        h.passDays(1.5)  // a day and a half left
        let renewed = try await session(h)
        XCTAssertNotEqual(renewed, first)
        XCTAssertEqual(h.server.count(exchange), 2)
        XCTAssertEqual(h.account.freshCalls, 2, "the exchange is made with a fresh Supabase token")
        let after = try XCTUnwrap(h.records.record)
        XCTAssertEqual(after.token, renewed)
        XCTAssertEqual(after.deviceListID, before.deviceListID, "a renewal is the same stored iPhone")
        XCTAssertEqual(after.expiresAt, h.clock.addingTimeInterval(ModelBackendServer.thirtyDays))
        XCTAssertEqual(h.owed.tokens, [], "the earlier token ends with its row, or by itself: nothing is owed for a renewal")
        let again = await h.sessions.token(for: backendTestServer)
        XCTAssertEqual(again, renewed)
        XCTAssertEqual(h.server.count(exchange), 2)
    }

    func testIfTheRenewalCannotBeDoneTheSessionInHandKeepsWorkingUntilItEnds() async throws {
        let h = BackendTestHarness()
        let first = try await session(h)
        h.passDays(29)   // a day left
        h.server.fault(exchange, .status(503, #"{"error":{"code":"provider_unavailable"}}"#))
        let still = await h.sessions.token(for: backendTestServer)
        XCTAssertEqual(still, first, "still valid for a day: used, not replaced by the Supabase token")
        XCTAssertEqual(h.records.record?.token, first)
        h.passDays(1.5)   // over: nothing valid is left
        let over = await h.sessions.token(for: backendTestServer)
        XCTAssertNil(over, "the caller falls back to the Supabase token")
        h.server.fault(exchange, nil)
        h.pass(3_600)
        let again = await h.sessions.token(for: backendTestServer)
        XCTAssertNotNil(again)
        XCTAssertNotEqual(again, first)
    }

    func testASessionThatRanOutIsNeverReturned() async throws {
        let h = BackendTestHarness()
        let first = try await session(h)
        h.passDays(31)
        let next = await h.sessions.token(for: backendTestServer)
        XCTAssertNotNil(next)
        XCTAssertNotEqual(next, first)
        XCTAssertEqual(h.owed.tokens, [], "one that ran its 30 days has nothing left to end")
    }

    // MARK: A refused session (401 at an everyday route)

    func testASessionTheBackendRefusedIsForgottenAndExchangedOnceWithAFreshToken() async throws {
        let h = BackendTestHarness()
        let first = try await session(h)
        h.server.revokeRow(of: first)   // revoked from another iPhone, say
        XCTAssertEqual(h.server.everydayStatus(for: first), 401)
        let renewed = await h.sessions.token(for: backendTestServer, refused: first)
        XCTAssertNotNil(renewed)
        XCTAssertNotEqual(renewed, first)
        XCTAssertEqual(h.server.count(exchange), 2, "once")
        XCTAssertEqual(h.account.freshCalls, 2)
        XCTAssertEqual(h.records.record?.token, renewed)
        XCTAssertNotEqual(h.records.record?.deviceListID, h.server.rowID(of: first), "a revoked iPhone's way back is a new row")
        XCTAssertEqual(h.owed.tokens, [], "the server said it doesn't accept it: nothing is left to end")
        XCTAssertEqual(h.server.count(revoke), 0)
        let live = try XCTUnwrap(renewed)
        XCTAssertEqual(h.server.everydayStatus(for: live), 200)
    }

    func testAfterARefusalAFailedExchangeKeepsNothingAndFallsBack() async throws {
        let h = BackendTestHarness()
        let first = try await session(h)
        h.server.fault(exchange, .status(404, #"{"error":{"code":"not_found"}}"#))
        let token = await h.sessions.token(for: backendTestServer, refused: first)
        XCTAssertNil(token, "no session: the caller sends the Supabase token, as before this change")
        XCTAssertNil(h.records.record, "the refused one is not kept to be sent again")
        XCTAssertEqual(h.server.count(exchange), 2, "one more try, never a loop")
        XCTAssertEqual(h.owed.tokens, [])
    }

    func testARefusalAboutAnEarlierTokenChangesNothing() async throws {
        let h = BackendTestHarness()
        let first = try await session(h)
        h.passDays(29)
        let second = try await session(h)   // renewed
        XCTAssertNotEqual(first, second)
        let answer = await h.sessions.token(for: backendTestServer, refused: first)
        XCTAssertEqual(answer, second, "a late 401 about the earlier token says nothing about the newer one")
        XCTAssertEqual(h.server.count(exchange), 2)
        XCTAssertEqual(h.records.record?.token, second)
    }

    func testARefusalOfTheSupabaseTokenIsNotARefusalOfTheSession() async throws {
        // A request sent the fallback token while a session was being made; its 401 is about that token.
        let h = BackendTestHarness()
        let first = try await session(h)
        let answer = await h.sessions.token(for: backendTestServer, refused: "supabase-1-not-real")
        XCTAssertEqual(answer, first)
        XCTAssertEqual(h.server.count(exchange), 1)
    }

    // MARK: The account's token refused at the exchange

    func testARefusedAccountTokenIsRenewedOnceAndTheExchangeAskedOnceMore() async {
        let h = BackendTestHarness()
        h.server.revokeAllAccountTokens()
        h.server.accept("supabase-2-not-real")   // only the renewed one is good
        let token = await h.sessions.token(for: backendTestServer)
        XCTAssertNotNil(token)
        XCTAssertEqual(h.server.seen.map(\.bearer), ["supabase-1-not-real", "supabase-2-not-real"])
        XCTAssertEqual(h.account.refusalCalls, 1)
    }

    func testARefusedAccountTokenIsNotAskedAboutAgainAndAgain() async {
        let h = BackendTestHarness()
        h.server.revokeAllAccountTokens()
        let token = await h.sessions.token(for: backendTestServer)
        XCTAssertNil(token)
        XCTAssertEqual(h.server.count(exchange), 2, "the token, and the one renewed token: no third try")
        XCTAssertEqual(h.account.refusalCalls, 1)
        XCTAssertNil(h.records.record)
    }

    // MARK: No session can be had: the Supabase token as before, nothing wrong remembered

    func testAnExchangeThatCannotBeCompletedMakesNoSessionAndStoresNothing() async {
        let faults: [ModelBackendServer.Fault] = [
            .offline,
            .status(404, #"{"error":{"code":"not_found","message":"Not found."}}"#),                // production without the route
            .status(503, #"{"error":{"code":"not_configured"}}"#),                                  // not set up here
            .status(503, #"{"error":"not_configured"}"#),
            .status(502, #"{"error":{"code":"provider_unavailable"}}"#),                            // the account check was unavailable
            .status(500, "{}"), .status(400, #"{"error":{"code":"invalid_request"}}"#),
            .status(429, #"{"error":{"code":"rate_limited","message":"Too many sign-ins from this network. Try again later."}}"#),
            .status(429, #"{"error":{"code":"quota_exceeded"}}"#),                                    // as many iPhones as the account allows
            .status(200, "not a session"), .status(200, "{}"),
        ]
        for fault in faults {
            let h = BackendTestHarness()
            h.server.fault(exchange, fault)
            let token = await h.sessions.token(for: backendTestServer)
            XCTAssertNil(token, "\(fault)")
            XCTAssertNil(h.records.record, "\(fault)")
            XCTAssertEqual(h.owed.tokens, [], "\(fault)")
            XCTAssertEqual(h.server.count(exchange), 1, "asked once, not in a loop: \(fault)")
            XCTAssertEqual(h.server.count(revoke), 0, "\(fault)")
        }
    }

    func testAnAnswerThatIsNotAnAccountSessionForThisAccountIsNotKept() async {
        let row = "00000000-0000-4000-8000-0000000000aa"
        let good = fakeBackendToken(sub: "account-1", dev: row, acc: true)
        let expires = "2027-02-14T08:00:00.000Z"   // thirty days after the test clock (15 Jan 2027)
        func body(token: String? = nil, expiresAt: String? = expires, access: String? = "full", list: String? = row) -> String {
            var fields: [String] = ["\"token\":\"\(token ?? good)\""]
            if let expiresAt { fields.append("\"expiresAt\":\"\(expiresAt)\"") }
            if let access { fields.append("\"access\":\"\(access)\"") }
            if let list { fields.append("\"deviceListId\":\"\(list)\"") }
            return "{" + fields.joined(separator: ",") + "}"
        }
        let bad: [String: String] = [
            "not a ds1 token": body(token: "eyJhbGciOiJub25lIn0.e30.sig"),
            "another account's session": body(token: fakeBackendToken(sub: "account-2", dev: row, acc: true)),
            "a device session, not an account session": body(token: fakeBackendToken(sub: "account-1", dev: row, acc: false)),
            "no expiry": body(expiresAt: nil),
            "an unreadable expiry": body(expiresAt: "tomorrow"),
            "not full access": body(access: "guest"),
            "no row id": body(list: nil),
            "a row id that is not an id": body(list: "../../v1/account"),
        ]
        for (name, text) in bad {
            let h = BackendTestHarness()
            h.server.fault(exchange, .status(200, text))
            let token = await h.sessions.token(for: backendTestServer)
            XCTAssertNil(token, name)
            XCTAssertNil(h.records.record, name)
        }
        // The same answer, made well, is taken.
        let h = BackendTestHarness()
        h.server.fault(exchange, .status(200, body()))
        let token = await h.sessions.token(for: backendTestServer)
        XCTAssertEqual(token, good)
    }

    func testNothingWrongIsRememberedAboutAServerTheNextLaunchAsksAgain() async throws {
        let h = BackendTestHarness()
        h.server.fault(exchange, .status(404, #"{"error":{"code":"not_found"}}"#))
        let first = await h.sessions.token(for: backendTestServer)
        XCTAssertNil(first, "no session: the caller falls back to the Supabase token, exactly as before")
        XCTAssertNil(h.records.record)
        // The next launch is a new object over the same Keychain items; the server has the route by now.
        let afterRestart = h.makeSessions()
        let second = await afterRestart.token(for: backendTestServer)
        XCTAssertNil(second)
        XCTAssertEqual(h.server.count(exchange), 2, "asked again at once: nothing was written down about the failure")
        h.server.fault(exchange, nil)
        let third = await h.makeSessions().token(for: backendTestServer)
        XCTAssertNotNil(third)
        XCTAssertNotNil(h.records.record)
    }

    func testWhileAFailureIsFreshTheSameLaunchDoesNotAskForEveryRequest() async {
        // Every backend request asks for its token first: a server that doesn't answer must not get a second request each.
        let h = BackendTestHarness()
        h.server.fault(exchange, .status(404, #"{"error":{"code":"not_found"}}"#))
        for _ in 0..<5 { _ = await h.sessions.token(for: backendTestServer) }
        XCTAssertEqual(h.server.count(exchange), 1)
        h.pass(299)
        _ = await h.sessions.token(for: backendTestServer)
        XCTAssertEqual(h.server.count(exchange), 1, "five minutes, in memory only")
        h.pass(2)
        _ = await h.sessions.token(for: backendTestServer)
        XCTAssertEqual(h.server.count(exchange), 2)
    }

    func testARateLimitIsGivenTheHourTheServerSays() async {
        let h = BackendTestHarness()
        h.server.fault(exchange, .status(429, #"{"error":{"code":"rate_limited"}}"#))
        let token = await h.sessions.token(for: backendTestServer)
        XCTAssertNil(token, "the caller carries on with the Supabase token: a limit at the exchange says nothing against it")
        h.pass(3_000)
        _ = await h.sessions.token(for: backendTestServer)
        XCTAssertEqual(h.server.count(exchange), 1, "asking again would only count again")
        h.pass(700)
        h.server.fault(exchange, nil)
        let later = await h.sessions.token(for: backendTestServer)
        XCTAssertNotNil(later)
        XCTAssertEqual(h.server.count(exchange), 2)
    }

    func testAFailureEndsWithSigningOut() async {
        let h = BackendTestHarness()
        h.server.fault(exchange, .status(404, "{}"))
        _ = await h.sessions.token(for: backendTestServer)
        h.server.fault(exchange, nil)
        await h.sessions.signedOut().value
        let token = await h.sessions.token(for: backendTestServer)
        XCTAssertNotNil(token, "a new sign-in asks at once")
    }

    // MARK: Whose session it is, and which server's

    func testASessionThatBelongsToAnotherAccountIsNeverUsedAndIsEndedAtTheServer() async throws {
        let h = BackendTestHarness()
        h.server.accept("supabase-3-not-real", account: "account-2")
        let others = try await session(h)
        h.account.accountID = "account-2"
        h.account.token = "supabase-3-not-real"
        let token = await h.sessions.token(for: backendTestServer)
        XCTAssertNotNil(token)
        XCTAssertNotEqual(token, others)
        XCTAssertEqual(h.records.record?.accountID, "account-2")
        _ = await h.sessions.retryOwed()
        XCTAssertFalse(h.server.isLive(others), "the first account's session was ended, never handed to the second")
        XCTAssertEqual(h.owed.tokens, [])
        XCTAssertEqual(h.server.liveRows, 1)
        XCTAssertEqual(h.server.seen.filter { $0.bearer == others }.map(\.method), ["DELETE"], "the only thing it was used for")
    }

    func testASessionOfAnotherServerIsNeverSentToThisOneAndStaysOwedToItsOwn() async throws {
        let h = BackendTestHarness()
        _ = try await session(h)
        let other = try XCTUnwrap(h.records.record)
        h.records.put(BackendSessionRecord(
            accountID: other.accountID, origin: BoundSessionToken(token: "x", issuedBy: otherBackendTestServer)!.origin,
            token: other.token, expiresAt: other.expiresAt, deviceListID: other.deviceListID))
        let launch = h.makeSessions()   // the next launch reads what is in the Keychain item
        let token = await launch.token(for: backendTestServer)
        XCTAssertNotNil(token)
        XCTAssertNotEqual(token, other.token, "a session made by another address is not used here")
        XCTAssertEqual(h.server.seen.filter { $0.bearer == other.token }, [], "and never sent here")
        XCTAssertEqual(launch.owedCount, 1, "it is owed an end where it was made, not forgotten")
        h.currentServer = otherBackendTestServer
        await launch.retryOwed()
        XCTAssertEqual(launch.owedCount, 0, "asked when that address is the one in use")
        XCTAssertEqual(h.server.count(revoke), 1)
    }

    func testTwoAsksAtOnceMakeOneSession() async {
        let h = BackendTestHarness()
        async let first = h.sessions.token(for: backendTestServer)
        async let second = h.sessions.token(for: backendTestServer)
        let both = await [first, second]
        XCTAssertEqual(h.server.count(exchange), 1)
        XCTAssertNotNil(both[0])
        XCTAssertEqual(both[0], both[1])
        XCTAssertEqual(h.server.liveRows, 1)
    }

    func testTwoAsksAtOnceNearTheEndMakeOneRenewal() async throws {
        let h = BackendTestHarness()
        _ = try await session(h)
        h.passDays(29)
        async let first = h.sessions.token(for: backendTestServer)
        async let second = h.sessions.token(for: backendTestServer)
        let both = await [first, second]
        XCTAssertEqual(h.server.count(exchange), 2)
        XCTAssertEqual(both[0], both[1])
    }

    func testIfTheKeychainRefusesTheSessionItIsUsedFromMemoryForThisLaunch() async throws {
        let h = BackendTestHarness()
        h.records.refusesToSave = true
        let token = try await session(h)
        XCTAssertNil(h.records.record)
        let again = await h.sessions.token(for: backendTestServer)
        XCTAssertEqual(again, token)
        XCTAssertEqual(h.server.count(exchange), 1)
        // The next launch has nothing, and asks: the same stored iPhone, a new token (the server renews a live row).
        let afterRestart = await h.makeSessions().token(for: backendTestServer)
        XCTAssertNotEqual(afterRestart, token)
        XCTAssertEqual(h.server.liveRows, 1)
    }

    // MARK: Signing out

    func testSigningOutForgetsTheSessionHereAtOnceAndKeepsTheServersEndOwed() async throws {
        let h = BackendTestHarness()
        let token = try await session(h)
        let kept = try XCTUnwrap(h.records.record)
        let task = h.sessions.signedOut()
        // Before any answer from the server:
        XCTAssertNil(h.records.record, "the session is gone from this iPhone at once")
        XCTAssertEqual(h.sessions.owedCount, 1, "and the end the server still owes is written down first")
        let written = try XCTUnwrap(h.owed.tokens.first.flatMap(BackendOwedSession.decode))
        XCTAssertEqual(written.token, token)
        XCTAssertEqual(written.deviceListID, kept.deviceListID)
        XCTAssertEqual(written.expiresAt, kept.expiresAt)
        await task.value
        XCTAssertFalse(h.server.isLive(token), "the server confirmed it ended")
        XCTAssertEqual(h.sessions.owedCount, 0, "owed no longer: it was answered")
        let afterwards = await h.sessions.token(for: backendTestServer)
        XCTAssertNotNil(afterwards, "signing in again asks the server for a new session")
        XCTAssertNotEqual(afterwards, token)
    }

    func testTheSignOutIsTheDeleteOfThisIPhonesRowMadeWithItsOwnSessionAndNoOtherToken() async throws {
        let h = BackendTestHarness()
        let token = try await session(h)
        let row = try XCTUnwrap(h.server.rowID(of: token))
        await h.sessions.signedOut().value
        let calls = h.server.seen.filter { $0.method == "DELETE" }
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.path, "/v1/web/devices/\(row)")
        XCTAssertEqual(calls.first?.bearer, token, "the iPhone's own session, never the account's Supabase token")
        XCTAssertNil(calls.first?.body)
        XCTAssertEqual(h.server.seen.filter { $0.bearer == "supabase-1-not-real" }.map(\.path), ["/v1/session/account"], "the Supabase token went to the exchange only")
    }

    func testAnUnansweredSignOutStaysOwedNeverCalledEndedAndTheNextLaunchFinishesIt() async throws {
        let h = BackendTestHarness()
        let token = try await session(h)
        h.server.fault(revoke, .offline)
        await h.sessions.signedOut().value
        XCTAssertNil(h.records.record)
        XCTAssertEqual(h.sessions.owedCount, 1, "signed out here, not ended there: still owed, never forgotten")
        XCTAssertTrue(h.server.isLive(token), "and nothing says it ended")
        // Neither is any of these an answer.
        for fault: ModelBackendServer.Fault in [.status(503, "{}"), .status(429, "{}"), .status(500, "{}"), .status(404, #"{"error":{"code":"not_found"}}"#), .status(200, "{}"), .status(200, "not json")] {
            h.server.fault(revoke, fault)
            let still = await h.sessions.retryOwed()
            XCTAssertEqual(still, 1, "\(fault)")
        }
        h.server.fault(revoke, nil)
        let afterRestart = h.makeSessions()   // the next launch
        XCTAssertEqual(afterRestart.owedCount, 1, "the obligation survived the restart")
        let left = await afterRestart.retryOwed()
        XCTAssertEqual(left, 0)
        XCTAssertFalse(h.server.isLive(token))
        XCTAssertEqual(h.owed.tokens, [])
    }

    func testASessionTheServerNoLongerAcceptsIsNoLongerOwed() async throws {
        // Revoked elsewhere, or the account was deleted: the server refuses it, so there is nothing left to end with it.
        let h = BackendTestHarness()
        let token = try await session(h)
        h.server.revokeRow(of: token)
        await h.sessions.signedOut().value
        XCTAssertEqual(h.sessions.owedCount, 0)
        XCTAssertEqual(h.server.count(revoke), 1)
    }

    func testAnOwedEndForASessionThatRanItsDaysIsDroppedWithoutAsking() async throws {
        let h = BackendTestHarness()
        _ = try await session(h)
        h.server.fault(revoke, .offline)
        await h.sessions.signedOut().value
        h.passDays(31)
        h.server.fault(revoke, nil)
        let left = await h.sessions.retryOwed()
        XCTAssertEqual(left, 0, "it ended by itself")
        XCTAssertEqual(h.server.count(revoke), 1, "no request for a session the server can't know any more")
    }

    func testIfTheOwedEndCannotBeWrittenDownItIsTriedOnceAnyway() async throws {
        let h = BackendTestHarness()
        let token = try await session(h)
        h.owed.refuses = true
        await h.sessions.signedOut().value
        XCTAssertNil(h.records.record, "forgotten here regardless")
        XCTAssertFalse(h.server.isLive(token), "and the server was asked")
    }

    func testSigningOutWithNoSessionOwesNothingAndSendsNothing() async {
        let h = BackendTestHarness()
        await h.sessions.signedOut().value
        XCTAssertTrue(h.server.seen.isEmpty)
        XCTAssertEqual(h.owed.tokens, [])
    }

    func testNoMoreThanFiveOwedEndsAreKept() async throws {
        let h = BackendTestHarness()
        h.server.fault(revoke, .offline)
        for number in 1...7 {
            h.server.accept("supabase-\(number)-not-real")
            h.account.token = "supabase-\(number)-not-real"
            h.passDays(0.5)
            h.currentServer = backendTestServer
            _ = await h.sessions.token(for: backendTestServer)
            await h.sessions.signedOut().value
        }
        XCTAssertEqual(h.owed.tokens.count, PendingDeviceRevocations.maxKept)
    }

    func testAnOwedEndNeedsNoSignedInAccount() async throws {
        let h = BackendTestHarness()
        let token = try await session(h)
        h.server.fault(revoke, .offline)
        await h.sessions.signedOut().value
        h.server.fault(revoke, nil)
        h.account.accountID = nil   // still signed out at the next launch
        let left = await h.makeSessions().retryOwed()
        XCTAssertEqual(left, 0, "the session itself is the proof, and it is used for nothing else")
        XCTAssertFalse(h.server.isLive(token))
    }

    func testASessionMadeWhileSigningOutIsNotKeptAndIsEnded() async {
        // The server answered the exchange after the person signed out: the session is for an account this iPhone no longer has.
        let h = BackendTestHarness()
        let sessions = h.sessions!
        h.server.duringRequest = { route in
            if route == "POST /v1/session/account" { await MainActor.run { _ = sessions.signedOut() } }
        }
        let token = await sessions.token(for: backendTestServer)
        h.server.duringRequest = nil
        XCTAssertNil(token)
        XCTAssertNil(h.records.record, "never stored")
        _ = await sessions.retryOwed()
        XCTAssertEqual(h.server.liveRows, 0, "and not left alive at the server")
        XCTAssertEqual(h.sessions.owedCount, 0)
    }

    func testARenewalThatFinishesAfterSigningOutIsNotKept() async throws {
        let h = BackendTestHarness()
        let first = try await session(h)
        h.passDays(29)
        let sessions = h.sessions!
        h.server.duringRequest = { route in
            if route == "POST /v1/session/account" { await MainActor.run { _ = sessions.signedOut() } }
        }
        let token = await sessions.token(for: backendTestServer)
        h.server.duringRequest = nil
        XCTAssertNil(token)
        XCTAssertNil(h.records.record)
        _ = await sessions.retryOwed()
        XCTAssertFalse(h.server.isLive(first))
        XCTAssertEqual(h.server.liveRows, 0)
        XCTAssertEqual(h.sessions.owedCount, 0)
    }

    func testAnotherAccountSigningInDuringAnExchangeNeverGetsTheFirstAccountsSession() async {
        let h = BackendTestHarness()
        let sessions = h.sessions!
        let account = h.account
        h.server.duringRequest = { route in
            if route == "POST /v1/session/account" { await MainActor.run { account.accountID = "account-2" } }
        }
        let token = await sessions.token(for: backendTestServer)
        h.server.duringRequest = nil
        XCTAssertNil(token)
        XCTAssertNil(h.records.record)
        _ = await sessions.retryOwed()
        XCTAssertEqual(h.server.liveRows, 0, "what the server made for the first account is ended, not kept for the second")
    }

    func testOnlyOneOwedPassRunsAtATime() async throws {
        let h = BackendTestHarness()
        _ = try await session(h)
        h.server.fault(revoke, .offline)
        await h.sessions.signedOut().value
        h.server.fault(revoke, nil)
        async let first = h.sessions.retryOwed()
        async let second = h.sessions.retryOwed()
        let both = await [first, second]
        XCTAssertEqual(both, [0, 0])
        XCTAssertEqual(h.server.count(revoke), 2, "the failed try, and one that got through")
    }

    // MARK: Signing in again on the same iPhone

    func testAnEndOwedFromAnEarlierSignOutNeverLeavesTheIPhoneWithoutAWayBack() async throws {
        // Signed out offline, signed in again before the owed end got through: the same stored iPhone, a new token. When the
        // owed end arrives it ends that row, which is the new session's too. The next request is refused and the app asks once
        // more, which gives a new row: one more request, never a dead end.
        let h = BackendTestHarness()
        let first = try await session(h)
        h.server.fault(revoke, .offline)
        await h.sessions.signedOut().value
        h.server.fault(revoke, nil)
        let second = try await session(h)
        XCTAssertNotEqual(second, first)
        XCTAssertEqual(h.server.rowID(of: second), h.server.rowID(of: first), "the same stored iPhone")
        _ = await h.sessions.retryOwed()
        XCTAssertEqual(h.server.everydayStatus(for: second), 401, "the row was ended")
        let third = await h.sessions.token(for: backendTestServer, refused: second)
        XCTAssertNotNil(third)
        let live = try XCTUnwrap(third)
        XCTAssertEqual(h.server.everydayStatus(for: live), 200)
        XCTAssertEqual(h.sessions.owedCount, 0)
    }

    // MARK: What the held session is, for the link routes

    func testTheHeldSessionIsReadableForTheLinkRoutesSelectionOnlyForThisServer() async throws {
        let h = BackendTestHarness()
        XCTAssertNil(h.sessions.heldToken(for: backendTestServer))
        let token = try await session(h)
        XCTAssertEqual(h.sessions.heldToken(for: backendTestServer), token)
        XCTAssertNil(h.sessions.heldToken(for: otherBackendTestServer), "another address's session is not this one's")
        await h.sessions.signedOut().value
        XCTAssertNil(h.sessions.heldToken(for: backendTestServer))
    }
}
