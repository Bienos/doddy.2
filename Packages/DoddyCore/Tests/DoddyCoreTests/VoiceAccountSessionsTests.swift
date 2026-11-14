import Foundation
import XCTest
@testable import DoddyCore

/// One token per server (decision 2026-11-12-one-token-per-server), the app's half for the voice server: the
/// iPhone keeps ONE voice-server session for the signed-in Doddy account. With none it asks `account-session` with a
/// fresh Supabase token; it renews the session with its rotating refresh token and keeps every new pair; a refused
/// session is asked for again once; signing out forgets it here at once and keeps the server's sign-out owed until the
/// server answers (DOD-08: nothing is "ended" that the server did not confirm; DOD-11: nothing is kept after sign-out).
///
/// The server here is a model of the real one (`server/voice-token/src/voice-auth.js`): a refresh token works once, a
/// refresh token used a second time ends the whole session, a sign-out needs a live access token. Every token is made up.
///
/// Platforms: iPhone. The Watch and Mac apps are paused.

@MainActor
final class VoiceAccountSessionsTests: XCTestCase {
    // MARK: Asking for the session

    func testWithNoSessionItAsksAccountSessionWithAFreshSupabaseTokenAndKeepsThePair() async throws {
        let h = VoiceTestHarness()
        let token = await h.sessions.accessToken()
        XCTAssertEqual(token, "access-2-not-real")
        XCTAssertEqual(h.server.seen.map(\.action), ["account-session"])
        XCTAssertEqual(h.server.seen.first?.bearer, "supabase-1-not-real")
        XCTAssertEqual(h.account.freshCalls, 1)
        let kept = try XCTUnwrap(h.pairs.pair, "kept in the Keychain slot, for the next launch")
        XCTAssertEqual(kept.accountID, "account-1")
        XCTAssertEqual(kept.accessToken, "access-2-not-real")
        XCTAssertEqual(kept.refreshToken, "refresh-3-not-real")
        XCTAssertEqual(kept.accessExpiresAt, h.clock.addingTimeInterval(600))
    }

    func testAFreshPairIsUsedWithoutAnyRequest() async {
        let h = VoiceTestHarness()
        let first = await h.sessions.accessToken()
        let again = await h.sessions.accessToken()
        let afterRestart = await h.makeSessions().accessToken()
        XCTAssertEqual(first, again)
        XCTAssertEqual(afterRestart, first, "the next launch finds the pair in the Keychain slot")
        XCTAssertEqual(h.server.seen.map(\.action), ["account-session"], "one exchange in all")
        XCTAssertEqual(h.account.freshCalls, 1, "a pair in use doesn't even ask for the account's token")
    }

    func testSignedOutThereIsNothingToAskForAndNothingIsSent() async {
        let h = VoiceTestHarness()
        h.account.accountID = nil
        let token = await h.sessions.accessToken()
        XCTAssertNil(token)
        XCTAssertTrue(h.server.seen.isEmpty)
        XCTAssertNil(h.pairs.pair)
    }

    func testWithoutAnAccountTokenNothingIsSentToTheServer() async {
        let h = VoiceTestHarness()
        h.account.token = nil   // the sign-in service couldn't be reached
        let token = await h.sessions.accessToken()
        XCTAssertNil(token)
        XCTAssertTrue(h.server.seen.isEmpty)
    }

    // MARK: Renewing

    func testAnExpiredAccessTokenIsRenewedWithTheRefreshTokenAndTheRotatedPairIsKept() async throws {
        let h = VoiceTestHarness()
        _ = await h.sessions.accessToken()
        let before = try XCTUnwrap(h.pairs.pair)
        h.tenMinutesPass()
        let token = await h.sessions.accessToken()
        XCTAssertEqual(h.server.seen.map(\.action), ["account-session", "refresh"])
        XCTAssertEqual(h.server.seen.last?.refreshToken, before.refreshToken)
        let after = try XCTUnwrap(h.pairs.pair)
        XCTAssertEqual(token, after.accessToken)
        XCTAssertNotEqual(after.refreshToken, before.refreshToken, "the new refresh token is the one kept, every time")
        XCTAssertEqual(after.accessExpiresAt, h.clock.addingTimeInterval(600))
        XCTAssertEqual(h.account.freshCalls, 1, "renewing needs no new sign-in token")
        // And the next ask is served from the new pair.
        let again = await h.sessions.accessToken()
        XCTAssertEqual(again, token)
        XCTAssertEqual(h.server.count("refresh"), 1)
    }

    func testARefreshTokenIsNeverUsedTwice() async {
        let h = VoiceTestHarness()
        _ = await h.sessions.accessToken()
        for _ in 0..<3 {
            h.tenMinutesPass()
            let token = await h.sessions.accessToken()
            XCTAssertNotNil(token)
        }
        let used = h.server.seen.compactMap(\.refreshToken)
        XCTAssertEqual(used.count, 3)
        XCTAssertEqual(Set(used).count, 3, "each refresh went out with the token the one before had given")
        XCTAssertEqual(h.server.liveSessions, 1, "the server saw no reused token, so it ended nothing")
    }

    func testTwoAsksAtOnceMakeOneRefresh() async {
        // A second refresh with the same token would be read by the server as a stolen one and end the session.
        let h = VoiceTestHarness()
        _ = await h.sessions.accessToken()
        h.tenMinutesPass()
        async let first = h.sessions.accessToken()
        async let second = h.sessions.accessToken()
        let both = await [first, second]
        XCTAssertEqual(h.server.count("refresh"), 1)
        XCTAssertEqual(both[0], both[1])
        XCTAssertNotNil(both[0])
        XCTAssertEqual(h.server.liveSessions, 1)
    }

    func testTwoFirstAsksAtOnceMakeOneSession() async {
        let h = VoiceTestHarness()
        async let first = h.sessions.accessToken()
        async let second = h.sessions.accessToken()
        let both = await [first, second]
        XCTAssertEqual(h.server.count("account-session"), 1)
        XCTAssertEqual(both[0], both[1])
        XCTAssertEqual(h.server.liveSessions, 1)
    }

    func testARefusedRefreshAsksAccountSessionAgainOnceAndKeepsTheNewPair() async throws {
        let h = VoiceTestHarness()
        _ = await h.sessions.accessToken()
        h.tenMinutesPass()
        h.server.endEverySession()   // the refresh token is no good any more
        let token = await h.sessions.accessToken()
        XCTAssertEqual(h.server.seen.map(\.action), ["account-session", "refresh", "account-session"])
        XCTAssertNotNil(token)
        XCTAssertEqual(try XCTUnwrap(h.pairs.pair).accessToken, token)
        XCTAssertEqual(h.account.freshCalls, 2, "the second exchange asked for the account's token again")
        XCTAssertEqual(h.owed.tokens, [], "a session the server no longer knows leaves nothing to end")
    }

    func testARefusedRefreshThenAFailedExchangeKeepsNothingAndFallsBack() async {
        let h = VoiceTestHarness()
        _ = await h.sessions.accessToken()
        h.tenMinutesPass()
        h.server.endEverySession()
        h.server.fault("account-session", .status(503, #"{"error":"account_check_unavailable"}"#))
        let token = await h.sessions.accessToken()
        XCTAssertNil(token, "no session: the caller sends the account's token as before")
        XCTAssertEqual(h.server.count("account-session"), 2)
        XCTAssertEqual(h.server.count("refresh"), 1, "once, never again with the same dead token")
        XCTAssertNil(h.pairs.pair, "the dead pair is not kept")
    }

    func testARefreshThatCouldNotBeDoneKeepsThePairForLater() async throws {
        let h = VoiceTestHarness()
        _ = await h.sessions.accessToken()
        let kept = try XCTUnwrap(h.pairs.pair)
        h.tenMinutesPass()
        h.server.fault("refresh", .offline)
        let token = await h.sessions.accessToken()
        XCTAssertNil(token)
        XCTAssertEqual(h.pairs.pair, kept, "offline says nothing about the session: the refresh token stays")
        XCTAssertEqual(h.server.count("account-session"), 1, "no new session is made just because the network failed")
        h.server.fault("refresh", nil)
        let later = await h.sessions.accessToken()
        XCTAssertNotNil(later)
        XCTAssertEqual(h.server.liveSessions, 1)
    }

    func testIfTheKeychainRefusesTheRotatedPairItIsUsedFromMemoryAndTheDeadTokenIsNotKept() async throws {
        let h = VoiceTestHarness()
        _ = await h.sessions.accessToken()
        let old = try XCTUnwrap(h.pairs.pair)
        h.tenMinutesPass()
        h.pairs.refusesToSave = true
        let token = await h.sessions.accessToken()
        XCTAssertNotNil(token, "this launch carries on with the pair it was given")
        XCTAssertNil(h.pairs.pair, "the spent refresh token \(old.refreshToken) must not stay behind to be sent again")
        let again = await h.sessions.accessToken()
        XCTAssertEqual(again, token)
        XCTAssertEqual(h.server.count("refresh"), 1)
        XCTAssertEqual(h.server.liveSessions, 1)
    }

    // MARK: The exchange not working

    func testAnOlderServerThatDoesNotKnowTheActionMakesNoPairAndIsAskedAgainNextTime() async {
        let h = VoiceTestHarness()
        h.server.fault("account-session", .status(400, #"{"error":"unknown_action"}"#))
        let first = await h.sessions.accessToken()
        XCTAssertNil(first, "no session: the caller falls back to the account's token, exactly as before")
        XCTAssertNil(h.pairs.pair)
        XCTAssertEqual(h.owed.tokens, [])
        // Nothing wrong is remembered about the server: the next start asks again, and a server that has it now answers.
        let second = await h.sessions.accessToken()
        XCTAssertNil(second)
        XCTAssertEqual(h.server.count("account-session"), 2)
        h.server.fault("account-session", nil)
        let third = await h.sessions.accessToken()
        XCTAssertNotNil(third)
        XCTAssertNotNil(h.pairs.pair)
    }

    func testAnExchangeThatCannotBeCompletedMakesNoPair() async {
        let faults: [ModelVoiceServer.Fault] = [
            .offline, .status(429, #"{"error":"rate_limited"}"#), .status(503, #"{"error":"account_check_unavailable"}"#),
            .status(503, #"{"error":"server_not_configured"}"#), .status(500, "{}"), .status(404, ""), .status(200, "not a session"),
        ]
        for fault in faults {
            let h = VoiceTestHarness()
            h.server.fault("account-session", fault)
            let token = await h.sessions.accessToken()
            XCTAssertNil(token, "\(fault)")
            XCTAssertNil(h.pairs.pair, "\(fault)")
            XCTAssertEqual(h.server.count("account-session"), 1, "asked once for this start, not in a loop: \(fault)")
        }
    }

    func testARefusedAccountTokenIsRenewedOnceAndTheExchangeAskedOnceMore() async {
        let h = VoiceTestHarness()
        h.server.revokeAllAccountTokens()
        h.server.accept("supabase-2-not-real")   // only the renewed one is good
        let token = await h.sessions.accessToken()
        XCTAssertNotNil(token)
        XCTAssertEqual(h.server.seen.map(\.bearer), ["supabase-1-not-real", "supabase-2-not-real"])
        XCTAssertEqual(h.account.refusalCalls, 1)
    }

    func testARefusedAccountTokenIsNotAskedAboutAgainAndAgain() async {
        let h = VoiceTestHarness()
        h.server.revokeAllAccountTokens()
        let token = await h.sessions.accessToken()
        XCTAssertNil(token)
        XCTAssertEqual(h.server.count("account-session"), 2, "the token, and the one renewed token: no third try")
        XCTAssertEqual(h.account.refusalCalls, 1)
        XCTAssertNil(h.pairs.pair)
    }

    func testWithNoServerAddressNothingIsSent() async {
        let h = VoiceTestHarness()
        let sessions = h.makeSessions(endpointURL: nil)
        let token = await sessions.accessToken()
        XCTAssertNil(token)
        XCTAssertTrue(h.server.seen.isEmpty)
    }

    // MARK: A refused session

    func testASessionTheVoiceServerRefusedIsForgottenAndAskedForAgain() async throws {
        let h = VoiceTestHarness()
        let refusedMaybe = await h.sessions.accessToken()
        let refused = try XCTUnwrap(refusedMaybe)
        let old = try XCTUnwrap(h.pairs.pair)
        let task = h.sessions.refused(refused)
        XCTAssertNil(h.pairs.pair, "gone from the Keychain slot at once")
        await task?.value
        XCTAssertEqual(h.owed.tokens, [], "the server was asked about it, and has answered")
        let renewed = await h.sessions.accessToken()
        XCTAssertNotNil(renewed)
        XCTAssertNotEqual(renewed, refused)
        XCTAssertEqual(h.server.count("account-session"), 2)
        XCTAssertNotEqual(h.pairs.pair?.refreshToken, old.refreshToken)
    }

    func testASessionThatWasRefusedButIsStillAliveIsEndedAtTheServerNotLeftBehind() async throws {
        let h = VoiceTestHarness()
        let refusedMaybe = await h.sessions.accessToken()   // say the 401 was a clock or a key, not the session
        let refused = try XCTUnwrap(refusedMaybe)
        _ = h.sessions.refused(refused)
        _ = await h.sessions.retryOwed()
        XCTAssertEqual(h.server.liveSessions, 0)
        XCTAssertEqual(h.owed.tokens, [])
    }

    func testRefusingAnOlderTokenLeavesTheNewerPairAlone() async throws {
        let h = VoiceTestHarness()
        let firstMaybe = await h.sessions.accessToken()
        let first = try XCTUnwrap(firstMaybe)
        h.tenMinutesPass()
        let secondMaybe = await h.sessions.accessToken()
        let second = try XCTUnwrap(secondMaybe)
        XCTAssertNotEqual(first, second)
        XCTAssertNil(h.sessions.refused(first), "a late 401 about the earlier access token says nothing about this one")
        XCTAssertEqual(h.pairs.pair?.accessToken, second)
    }

    func testAPairThatBelongsToAnotherAccountIsNeverUsed() async throws {
        let h = VoiceTestHarness()
        _ = await h.sessions.accessToken()
        let others = try XCTUnwrap(h.pairs.pair)
        h.account.accountID = "account-2"
        let token = await h.sessions.accessToken()
        XCTAssertNotNil(token)
        XCTAssertNotEqual(token, others.accessToken)
        XCTAssertEqual(h.pairs.pair?.accountID, "account-2")
        _ = await h.sessions.retryOwed()
        XCTAssertEqual(h.owed.tokens, [])
        XCTAssertEqual(h.server.liveSessions, 1, "the first account's session was ended, only the new one lives")
    }

    // MARK: Signing out

    func testSigningOutForgetsThePairHereAtOnceAndKeepsTheServersSignOutOwed() async throws {
        let h = VoiceTestHarness()
        _ = await h.sessions.accessToken()
        let kept = try XCTUnwrap(h.pairs.pair)
        let task = h.sessions.signedOut()
        // Before any answer from the server:
        XCTAssertNil(h.pairs.pair, "the pair is gone from this iPhone at once")
        XCTAssertEqual(h.owed.tokens, [kept.refreshToken], "and the sign-out the server still owes is written down")
        await task.value
        XCTAssertEqual(h.server.liveSessions, 0, "the server confirmed it ended the session")
        XCTAssertEqual(h.owed.tokens, [], "owed no longer: it was answered")
        let afterwards = await h.sessions.accessToken()
        XCTAssertNotNil(afterwards, "signing in again asks the server for a new session")
    }

    func testSigningOutSendsTheOwedCallWithAFreshAccessTokenFromTheRefreshToken() async throws {
        let h = VoiceTestHarness()
        _ = await h.sessions.accessToken()
        let kept = try XCTUnwrap(h.pairs.pair)
        await h.sessions.signedOut().value
        XCTAssertEqual(h.server.seen.map(\.action), ["account-session", "refresh", "sign-out"])
        XCTAssertEqual(h.server.seen[1].refreshToken, kept.refreshToken)
        XCTAssertNotNil(h.server.seen[2].bearer)
        XCTAssertNotEqual(h.server.seen[2].bearer, kept.accessToken, "the access token that was kept may have run out; the one just made is used")
    }

    func testAnOfflineSignOutStaysOwedAndTheNextLaunchFinishesIt() async throws {
        let h = VoiceTestHarness()
        _ = await h.sessions.accessToken()
        let kept = try XCTUnwrap(h.pairs.pair)
        h.server.fault("refresh", .offline)
        await h.sessions.signedOut().value
        XCTAssertNil(h.pairs.pair)
        XCTAssertEqual(h.owed.tokens, [kept.refreshToken], "signed out here, not ended there: still owed, never forgotten")
        XCTAssertEqual(h.server.liveSessions, 1, "and nothing says it ended")
        // Busy is not an answer either.
        h.server.fault("refresh", .status(503, "{}"))
        let still = await h.sessions.retryOwed()
        XCTAssertEqual(still, 1)
        // The next launch builds a new object over the same slots.
        h.server.fault("refresh", nil)
        let afterRestart = h.makeSessions()
        XCTAssertEqual(afterRestart.owedCount, 1, "the obligation survived the restart")
        let left = await afterRestart.retryOwed()
        XCTAssertEqual(left, 0)
        XCTAssertEqual(h.server.liveSessions, 0)
        XCTAssertEqual(h.owed.tokens, [])
    }

    func testIfTheSignOutFailsAfterTheRefreshWhatIsOwedIsTheNewRefreshTokenNotTheSpentOne() async throws {
        let h = VoiceTestHarness()
        _ = await h.sessions.accessToken()
        let kept = try XCTUnwrap(h.pairs.pair)
        h.server.fault("sign-out", .offline)
        await h.sessions.signedOut().value
        XCTAssertEqual(h.owed.tokens.count, 1)
        XCTAssertNotEqual(h.owed.tokens.first, kept.refreshToken, "that one was spent by the refresh")
        h.server.fault("sign-out", nil)
        let left = await h.sessions.retryOwed()
        XCTAssertEqual(left, 0)
        XCTAssertEqual(h.server.liveSessions, 0, "ended once the server answered, with no spent token sent again")
        let refreshes = h.server.seen.compactMap(\.refreshToken)
        XCTAssertEqual(Set(refreshes).count, refreshes.count)
    }

    func testASessionTheServerAlreadyEndedIsNoLongerOwed() async {
        // The account was deleted, which ended every voice session at the server: the owed call finds nothing to end.
        let h = VoiceTestHarness()
        _ = await h.sessions.accessToken()
        h.server.endEverySession()
        await h.sessions.signedOut().value
        XCTAssertEqual(h.owed.tokens, [])
        XCTAssertEqual(h.server.seen.map(\.action), ["account-session", "refresh"])
    }

    func testIfTheOwedCallCannotBeWrittenDownItIsTriedOnceAnyway() async {
        let h = VoiceTestHarness()
        _ = await h.sessions.accessToken()
        h.owed.refuses = true
        await h.sessions.signedOut().value
        XCTAssertNil(h.pairs.pair, "forgotten here regardless")
        XCTAssertEqual(h.server.liveSessions, 0, "and the server was asked")
    }

    func testSigningOutWithNoSessionOwesNothing() async {
        let h = VoiceTestHarness()
        await h.sessions.signedOut().value
        XCTAssertTrue(h.server.seen.isEmpty)
        XCTAssertEqual(h.owed.tokens, [])
    }

    func testASessionMadeWhileSigningOutIsNotKeptAndIsEnded() async {
        // The server answered the exchange after the person signed out: the pair is for an account this iPhone no longer has.
        let h = VoiceTestHarness()
        let sessions = h.sessions!
        h.server.duringRequest = { action in
            if action == "account-session" { await MainActor.run { _ = sessions.signedOut() } }
        }
        let token = await sessions.accessToken()
        h.server.duringRequest = nil
        XCTAssertNil(token)
        XCTAssertNil(h.pairs.pair, "never stored")
        _ = await sessions.retryOwed()
        XCTAssertEqual(h.server.liveSessions, 0, "and not left alive at the server")
        XCTAssertEqual(h.owed.tokens, [])
    }

    func testARefreshThatFinishesAfterSigningOutIsNotKept() async {
        let h = VoiceTestHarness()
        _ = await h.sessions.accessToken()
        h.tenMinutesPass()
        let sessions = h.sessions!
        h.server.duringRequest = { action in
            if action == "refresh" { await MainActor.run { _ = sessions.signedOut() } }
        }
        let token = await sessions.accessToken()
        h.server.duringRequest = nil
        XCTAssertNil(token)
        XCTAssertNil(h.pairs.pair)
        _ = await sessions.retryOwed()
        XCTAssertEqual(h.server.liveSessions, 0)
        XCTAssertEqual(h.owed.tokens, [])
    }

    func testNoMoreThanFiveOwedCallsAreKept() async {
        let h = VoiceTestHarness()
        h.server.fault("refresh", .offline)
        for number in 1...7 {
            h.server.accept("supabase-\(number)-not-real")
            h.account.token = "supabase-\(number)-not-real"
            _ = await h.sessions.accessToken()
            await h.sessions.signedOut().value
        }
        XCTAssertEqual(h.owed.tokens.count, PendingDeviceRevocations.maxKept)
    }

    func testAnOwedCallNeedsNoSignedInAccount() async {
        let h = VoiceTestHarness()
        _ = await h.sessions.accessToken()
        h.server.fault("refresh", .offline)
        await h.sessions.signedOut().value
        h.server.fault("refresh", nil)
        h.account.accountID = nil   // still signed out at the next launch
        let left = await h.makeSessions().retryOwed()
        XCTAssertEqual(left, 0, "the refresh token itself is the proof, and it is used for nothing else")
        XCTAssertEqual(h.server.liveSessions, 0)
    }
}
