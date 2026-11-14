import Foundation
import XCTest
@testable import DoddyCore

/// One token per server (decision 2026-11-12-one-token-per-server): which token a request for a voice token carries
/// while a Doddy account is signed in. This server's own session first; the account's Supabase token, exactly as before
/// this change, when no session can be had (an older server, or the exchange couldn't be completed) or when the session
/// was refused twice. A rate limit is shown as it always was. Every token here is made up.
///
/// Platforms: iPhone. The Watch and Mac apps are paused.

private actor Calls {
    private(set) var sent: [String] = []
    private(set) var refused: [String] = []
    private(set) var sessionAsks = 0
    private(set) var accountAsks = 0
    func didSend(_ token: String) { sent.append(token) }
    func didRefuse(_ token: String) { refused.append(token) }
    func askedForSession() { sessionAsks += 1 }
    func askedForAccount() { accountAsks += 1 }
}

private func answer(_ status: Int, retryAfter: String? = nil, body: String = #"{"token":"conversation-token-not-real"}"#) -> Result<VoiceTokenAnswer, VoiceTokenError> {
    .success(VoiceTokenAnswer(status: status, body: Data(body.utf8), retryAfter: retryAfter))
}

final class VoiceTokenAttemptTests: XCTestCase {
    /// Runs the attempt with these sessions (handed out one per ask; nil = none could be had), this account token, and
    /// what the voice-token endpoint answers to each token it is sent.
    private func run(
        sessions: [String?], account: String? = "supabase-token-not-real", answers: [String: Result<VoiceTokenAnswer, VoiceTokenError>]
    ) async -> (Result<VoiceTokenAnswer, VoiceTokenError>?, Calls) {
        let calls = Calls()
        let queue = Queue(sessions)
        let result = await VoiceTokenAttempt.run(
            sessionToken: { await calls.askedForSession(); return await queue.next() },
            sessionRefused: { await calls.didRefuse($0) },
            accountToken: { await calls.askedForAccount(); return account },
            send: { token in
                await calls.didSend(token)
                return answers[token] ?? answer(500)
            })
        return (result, calls)
    }

    private actor Queue {
        private var items: [String?]
        init(_ items: [String?]) { self.items = items }
        func next() -> String? { items.isEmpty ? nil : items.removeFirst() }
    }

    func testTheSessionsTokenIsSentAndTheAccountsTokenIsNotEvenAskedFor() async {
        let (result, calls) = await run(sessions: ["session-1"], answers: ["session-1": answer(200)])
        XCTAssertEqual(result, answer(200))
        let sent = await calls.sent
        XCTAssertEqual(sent, ["session-1"])
        let accountAsks = await calls.accountAsks
        XCTAssertEqual(accountAsks, 0)
    }

    func testWithNoSessionTheAccountsTokenIsSentExactlyAsBeforeThisChange() async {
        // An older server (400 unknown_action) or an exchange that couldn't be completed: no session, no mark left.
        let (result, calls) = await run(sessions: [nil], answers: ["supabase-token-not-real": answer(200)])
        XCTAssertEqual(result, answer(200))
        let sent = await calls.sent
        XCTAssertEqual(sent, ["supabase-token-not-real"])
        let refused = await calls.refused
        XCTAssertEqual(refused, [])
    }

    func testARefusedSessionIsForgottenAndAskedForOnceMoreThenUsed() async {
        let (result, calls) = await run(
            sessions: ["session-1", "session-2"], answers: ["session-1": answer(401), "session-2": answer(200)])
        XCTAssertEqual(result, answer(200))
        let sent = await calls.sent
        XCTAssertEqual(sent, ["session-1", "session-2"])
        let refused = await calls.refused
        XCTAssertEqual(refused, ["session-1"])
        let accountAsks = await calls.accountAsks
        XCTAssertEqual(accountAsks, 0)
    }

    func testASessionRefusedTwiceFallsBackToTheAccountsToken() async {
        let (result, calls) = await run(
            sessions: ["session-1", "session-2", "session-3"],
            answers: ["session-1": answer(401), "session-2": answer(401), "session-3": answer(200),
                      "supabase-token-not-real": answer(200)])
        XCTAssertEqual(result, answer(200))
        let sent = await calls.sent
        XCTAssertEqual(sent, ["session-1", "session-2", "supabase-token-not-real"], "asked once more, not again and again")
        let refused = await calls.refused
        XCTAssertEqual(refused, ["session-1", "session-2"])
        let sessionAsks = await calls.sessionAsks
        XCTAssertEqual(sessionAsks, 2)
    }

    func testARefusedSessionWithNoNewSessionFallsBack() async {
        let (result, calls) = await run(
            sessions: ["session-1", nil], answers: ["session-1": answer(401), "supabase-token-not-real": answer(200)])
        XCTAssertEqual(result, answer(200))
        let sent = await calls.sent
        XCTAssertEqual(sent, ["session-1", "supabase-token-not-real"])
    }

    func testARateLimitedAnswerPassesThroughUnchangedWithoutAnyRetryOrFallback() async {
        let limited = answer(429, retryAfter: "1800", body: #"{"error":"rate_limited"}"#)
        let (result, calls) = await run(sessions: ["session-1"], answers: ["session-1": limited])
        XCTAssertEqual(result, limited, "the same answer, the same Retry-After")
        let sent = await calls.sent
        XCTAssertEqual(sent, ["session-1"], "the account is the same under either token: a second try would only count again")
        let refused = await calls.refused
        XCTAssertEqual(refused, [], "a limit says nothing about the session")
        // ... and reads exactly as it did: the existing text, from the existing code.
        guard case .success(let reply)? = result else { return XCTFail("expected an answer") }
        let read = VoiceTokenServer.token(status: reply.status, body: reply.body, retryAfter: reply.retryAfter)
        XCTAssertEqual(read, .failure(.rateLimited(retryAfterSeconds: 1800)))
        XCTAssertEqual(
            VoiceTokenServer.message(for: .rateLimited(retryAfterSeconds: 1800)),
            "You've started a lot of conversations. Try again in about 30 minutes; your notes still work.")
    }

    func testOtherAnswersPassThroughToo() async {
        for status in [200, 400, 404, 500, 503] {
            let (result, calls) = await run(sessions: ["session-1"], answers: ["session-1": answer(status)])
            XCTAssertEqual(result, answer(status), "status \(status)")
            let sent = await calls.sent
            XCTAssertEqual(sent, ["session-1"], "status \(status)")
        }
    }

    func testARequestThatCouldNotBeMadeIsReportedAsItWasNotRetriedWithAnotherToken() async {
        let (result, calls) = await run(sessions: ["session-1"], answers: ["session-1": .failure(.offline)])
        XCTAssertEqual(result, .failure(.offline))
        let sent = await calls.sent
        XCTAssertEqual(sent, ["session-1"])
    }

    func testTheAccountsTokenBeingRefusedIsAnswerNotSomethingToRetry() async {
        // Exactly as before: a 401 for the account's own token is the caller's to read (session expired).
        let (result, calls) = await run(sessions: [nil], answers: ["supabase-token-not-real": answer(401)])
        XCTAssertEqual(result, answer(401))
        let sent = await calls.sent
        XCTAssertEqual(sent, ["supabase-token-not-real"])
        let refused = await calls.refused
        XCTAssertEqual(refused, [], "only a voice session is forgotten, never the account's token")
    }

    func testWithNeitherTokenThereIsNothingToSendAndTheCallerGoesOn() async {
        let (result, calls) = await run(sessions: [nil], account: nil, answers: [:])
        XCTAssertNil(result, "signed out, or no token could be had: the caller uses the older voice session, as before")
        let sent = await calls.sent
        XCTAssertEqual(sent, [])
    }
}

/// The same rules with the real session keeper and a model of the voice server behind them, as `VoiceTokenClient` runs
/// them: the session first, the account's token as the fallback.
@MainActor
final class VoiceStartsWithTheAccountTests: XCTestCase {
    private actor SentLog {
        private(set) var tokens: [String] = []
        func add(_ token: String) { tokens.append(token) }
    }

    private func start(_ h: VoiceTestHarness) async -> (result: Result<VoiceTokenAnswer, VoiceTokenError>?, sent: [String]) {
        let log = SentLog()
        let sessions = h.sessions!
        let server = h.server
        let account = h.account
        let result = await VoiceTokenAttempt.run(
            sessionToken: { await sessions.accessToken() },
            sessionRefused: { token in _ = await sessions.refused(token) },
            accountToken: { await account.freshToken() },
            send: { token in
                await log.add(token)
                return answer(server.voiceTokenStatus(for: token))
            })
        return (result, await log.tokens)
    }

    func testTheFirstStartMakesTheSessionAndLaterStartsReuseIt() async {
        let h = VoiceTestHarness()
        let first = await start(h)
        let second = await start(h)
        XCTAssertEqual(first.result, answer(200))
        XCTAssertEqual(second.result, answer(200))
        XCTAssertEqual(h.server.count("account-session"), 1)
        XCTAssertEqual(first.sent.count, 1)
        XCTAssertEqual(first.sent, second.sent)
        XCTAssertNotEqual(first.sent.first, "supabase-1-not-real", "the voice server's own token goes, not the account's")
    }

    func testASessionTheServerEndedIsMadeAgainOnceAndTheStartStillWorks() async {
        let h = VoiceTestHarness()
        let first = await start(h)
        h.server.endEverySession()   // signed out elsewhere, or the account's voice sessions were ended
        let second = await start(h)
        XCTAssertEqual(second.result, answer(200))
        XCTAssertEqual(second.sent.count, 2)
        XCTAssertEqual(second.sent.first, first.sent.first, "the kept session was tried first and refused")
        XCTAssertNotEqual(second.sent.last, first.sent.first)
        XCTAssertFalse(second.sent.contains("supabase-1-not-real"))
        XCTAssertEqual(h.server.count("account-session"), 2)
        _ = await h.sessions.retryOwed()
        XCTAssertEqual(h.owed.tokens, [], "nothing left to end at the server")
    }

    func testAnOlderServerThatDoesNotKnowTheExchangeKeepsTheOldWayAndRemembersNothing() async {
        let h = VoiceTestHarness()
        h.server.fault("account-session", .status(400, #"{"error":"unknown_action"}"#))
        let first = await start(h)
        let second = await start(h)
        XCTAssertEqual(first.result, answer(200))
        XCTAssertEqual(first.sent, ["supabase-1-not-real"], "exactly what was sent before this change")
        XCTAssertEqual(second.sent, ["supabase-1-not-real"])
        XCTAssertNil(h.pairs.pair)
        XCTAssertEqual(h.owed.tokens, [])
        h.server.fault("account-session", nil)   // the server is updated
        let third = await start(h)
        XCTAssertEqual(third.result, answer(200))
        XCTAssertNotEqual(third.sent, ["supabase-1-not-real"], "and the next start uses the session")
    }

    func testSessionsRefusedTwiceFallBackToTheAccountsTokenAndNothingIsLeftAlive() async {
        let h = VoiceTestHarness()
        h.server.refuseSessions = true
        let started = await start(h)
        XCTAssertEqual(started.result, answer(200))
        XCTAssertEqual(started.sent.count, 3)
        XCTAssertEqual(started.sent.last, "supabase-1-not-real")
        XCTAssertEqual(h.server.count("account-session"), 2, "one session, and one more after it was refused: never a third")
        _ = await h.sessions.retryOwed()
        XCTAssertEqual(h.server.liveSessions, 0, "both refused sessions were forgotten here and ended there, none left alive")
        XCTAssertNil(h.pairs.pair)
        XCTAssertEqual(h.owed.tokens, [])
    }

    func testAfterSigningOutTheNextStartUsesANewSessionAndTheOldOneIsEnded() async {
        let h = VoiceTestHarness()
        let first = await start(h)
        await h.sessions.signedOut().value
        XCTAssertEqual(h.server.liveSessions, 0)
        let second = await start(h)
        XCTAssertEqual(second.result, answer(200))
        XCTAssertNotEqual(second.sent, first.sent)
        XCTAssertEqual(h.server.liveSessions, 1)
    }
}
