import Foundation
import XCTest
@testable import DoddyCore

/// One token per server (decision 2026-11-12-one-token-per-server), the app's half for the voice server: the three
/// requests to `POST /api/voice-auth` that make, renew and end this iPhone's own voice session for the signed-in Doddy
/// account (`account-session`, `refresh`, `sign-out`), and what each answer proves. The shapes are the server's
/// (`server/voice-token/test/account-session.test.js`). Every token here is made up.
///
/// Platforms: iPhone. The Watch and Mac apps are paused.

private final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Offline: Error {}
    private let lock = NSLock()
    private var queue: [(Int, String)?]
    private var recorded: [HTTPRequest] = []
    init(_ replies: [(Int, String)?]) { queue = replies }
    var requests: [HTTPRequest] { lock.withLock { recorded } }
    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        let next = lock.withLock { () -> (Int, String)? in
            recorded.append(request)
            return queue.isEmpty ? nil : queue.removeFirst()
        }
        guard let next else { throw Offline() }
        return (next.0, Data(next.1.utf8))
    }
}

private let endpoint = URL(string: "https://voice.example.com/api/voice-auth")!
private let reply = #"{"accessToken":"access-token-not-real","refreshToken":"refresh-token-not-real","expiresIn":600}"#
private let tokens = VoiceSessionTokens(accessToken: "access-token-not-real", refreshToken: "refresh-token-not-real", expiresIn: 600)

final class VoiceSessionWireTests: XCTestCase {
    private func body(_ request: HTTPRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any]) ?? [:]
    }

    // MARK: account-session

    func testTheExchangeSendsTheAccountsTokenAsTheBearerAndNothingElse() async throws {
        let transport = StubTransport([(200, reply)])
        let outcome = await VoiceSessionWire.exchange(endpoint: endpoint, accountToken: "supabase-token-not-real", transport: transport)
        XCTAssertEqual(outcome, .minted(tokens))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url, endpoint)
        XCTAssertEqual(request.headers["authorization"], "Bearer supabase-token-not-real")
        XCTAssertEqual(request.headers["content-type"], "application/json")
        XCTAssertEqual(body(request) as NSDictionary, ["action": "account-session"], "no identifier, no refresh token: the bearer is the proof")
    }

    func testEachAnswerToTheExchangeIsReadForWhatItProves() async {
        let cases: [(String, (Int, String)?, VoiceSessionWire.Exchange)] = [
            ("made", (200, reply), .minted(tokens)),
            ("the account's token was refused", (401, #"{"error":"session_expired"}"#), .accountRefused),
            // An older server doesn't know the action: nothing was made, and the account's token is used as before.
            ("an older server", (400, #"{"error":"unknown_action"}"#), .unavailable),
            ("limited", (429, #"{"error":"rate_limited"}"#), .unavailable),
            ("keys unreadable", (503, #"{"error":"account_check_unavailable"}"#), .unavailable),
            ("not configured", (503, #"{"error":"server_not_configured"}"#), .unavailable),
            ("server error", (500, #"{"error":"voice_auth_failed"}"#), .unavailable),
            ("no route", (404, ""), .unavailable),
            ("no answer at all", nil, .unavailable),
        ]
        for (name, answer, expected) in cases {
            let outcome = await VoiceSessionWire.exchange(endpoint: endpoint, accountToken: "supabase-token-not-real", transport: StubTransport([answer]))
            XCTAssertEqual(outcome, expected, name)
        }
    }

    func testAReplyThatIsNotASessionIsNotOne() async {
        let unreadable = [
            "", "not json", "[]", "{}",
            #"{"accessToken":"a","refreshToken":"r"}"#,                                  // no lifetime
            #"{"accessToken":"","refreshToken":"r","expiresIn":600}"#,                  // empty token
            #"{"accessToken":"a","refreshToken":"","expiresIn":600}"#,
            #"{"accessToken":"a","refreshToken":"r","expiresIn":0}"#,                   // already over
            #"{"accessToken":"a","refreshToken":"r","expiresIn":-5}"#,
            #"{"accessToken":"a","refreshToken":"r","expiresIn":"600"}"#,               // wrong type
            #"{"accessToken":1,"refreshToken":"r","expiresIn":600}"#,
        ]
        for text in unreadable {
            let outcome = await VoiceSessionWire.exchange(endpoint: endpoint, accountToken: "supabase-token-not-real", transport: StubTransport([(200, text)]))
            XCTAssertEqual(outcome, .unavailable, text)
        }
    }

    // MARK: refresh

    func testARefreshSendsTheRefreshTokenAndNoAuthorizationHeader() async throws {
        let transport = StubTransport([(200, reply)])
        let outcome = await VoiceSessionWire.refresh(endpoint: endpoint, refreshToken: "refresh-token-old-not-real", transport: transport)
        XCTAssertEqual(outcome, .rotated(tokens))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertNil(request.headers["authorization"], "the refresh token is the proof; no other token goes with it")
        XCTAssertEqual(body(request) as NSDictionary, ["action": "refresh", "refreshToken": "refresh-token-old-not-real"])
    }

    func testOnlyA401MeansTheSessionIsGone() async {
        let cases: [(Int, VoiceSessionWire.Refresh)] = [
            (401, .refused),
            (400, .unavailable), (429, .unavailable), (500, .unavailable), (503, .unavailable), (404, .unavailable),
        ]
        for (status, expected) in cases {
            let outcome = await VoiceSessionWire.refresh(endpoint: endpoint, refreshToken: "r", transport: StubTransport([(status, #"{"error":"session_expired"}"#)]))
            XCTAssertEqual(outcome, expected, "status \(status)")
        }
        let offline = await VoiceSessionWire.refresh(endpoint: endpoint, refreshToken: "r", transport: StubTransport([nil]))
        XCTAssertEqual(offline, .unavailable, "no answer is not an answer")
        let unreadable = await VoiceSessionWire.refresh(endpoint: endpoint, refreshToken: "r", transport: StubTransport([(200, "{}")]))
        XCTAssertEqual(unreadable, .unavailable)
    }

    // MARK: sign-out

    func testSigningOutSendsTheSessionsAccessTokenAsTheBearer() async throws {
        let transport = StubTransport([(200, #"{"signedOut":true}"#)])
        let outcome = await VoiceSessionWire.signOut(endpoint: endpoint, accessToken: "access-token-not-real", transport: transport)
        XCTAssertEqual(outcome, .ended)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.headers["authorization"], "Bearer access-token-not-real")
        XCTAssertEqual(body(request) as NSDictionary, ["action": "sign-out"])
    }

    func testASessionIsEndedOnlyWhenTheServerSaidSo() async {
        let cases: [(Int, VoiceSessionWire.SignOut)] = [
            (200, .ended),
            (401, .alreadyGone),     // the server no longer knows the session: an earlier try got through, or it ended
            (400, .unavailable), (429, .unavailable), (500, .unavailable), (503, .unavailable), (404, .unavailable),
            (204, .unavailable),     // not the server's answer to this action: not a confirmation
        ]
        for (status, expected) in cases {
            let outcome = await VoiceSessionWire.signOut(endpoint: endpoint, accessToken: "a", transport: StubTransport([(status, "{}")]))
            XCTAssertEqual(outcome, expected, "status \(status)")
        }
        let offline = await VoiceSessionWire.signOut(endpoint: endpoint, accessToken: "a", transport: StubTransport([nil]))
        XCTAssertEqual(offline, .unavailable)
    }
}
