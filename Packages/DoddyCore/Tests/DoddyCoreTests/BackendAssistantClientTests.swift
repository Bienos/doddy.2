import XCTest
@testable import DoddyCore

/// ADR-581: typed questions go to Doddy's own server (`POST /v1/assist`), signed in with the
/// device session. Uses the shared contract fixtures (also read by the server's tests).
final class BackendAssistantClientTests: XCTestCase {
    private let server = URL(string: "https://doddy.example.com")!
    private let plain = AssistantRequest(sessionID: UUID(), userText: "hi")

    /// A script for the session: which tokens it hands out, and how often it was asked.
    private actor Tokens {
        private(set) var asked = 0
        private(set) var renewals = 0
        private let first: String?
        private let renewed: String?
        init(first: String?, renewed: String?) {
            self.first = first
            self.renewed = renewed
        }
        func token() -> String? { asked += 1; return first }
        func renew() -> String? { renewals += 1; return renewed }
    }

    private func session(_ tokens: Tokens) -> AssistantSession {
        AssistantSession(token: { await tokens.token() }, renewed: { await tokens.renew() })
    }

    private func client(_ transport: FakeTransport, tokens: Tokens, baseURL: URL? = nil) -> BackendAssistantClient {
        BackendAssistantClient(baseURL: baseURL ?? server, session: session(tokens), transport: transport)
    }

    private func ok(_ request: AssistantRequest, text: String = "Answer", cited: [UUID] = []) -> GatewayHTTPResponse {
        let ids = cited.map { "\"\($0.uuidString.lowercased())\"" }.joined(separator: ",")
        return GatewayHTTPResponse(status: 200, body: Data(
            #"{"schemaVersion":1,"requestId":"\#(request.requestID.uuidString.lowercased())","text":"\#(text)","citedMemoryIDs":[\#(ids)],"usage":{"inputTokens":9,"outputTokens":3}}"#.utf8))
    }

    /// The server's own error body (`backend/src/http.ts`): no schemaVersion, no request ID.
    private func failure(_ status: Int, _ code: String, retryAfter: Int? = nil, headers: [String: String] = [:]) -> GatewayHTTPResponse {
        let retry = retryAfter.map { #","retryAfterSeconds":\#($0)"# } ?? ""
        return GatewayHTTPResponse(status: status, headers: headers, body: Data(
            #"{"error":{"code":"\#(code)","message":"text the app never shows","correlationId":"0b2c8f1e-0000-4000-8000-000000000000"\#(retry)}}"#.utf8))
    }

    // MARK: - the request

    func testPostsTheSharedRequestShapeToDoddysServerWithTheDeviceSession() async throws {
        let transport = FakeTransport([.success(ok(plain))])
        let tokens = Tokens(first: "ds1.token", renewed: nil)
        let reply = try await client(transport, tokens: tokens).respond(plain)

        XCTAssertEqual(reply.text, "Answer")
        let sent = await transport.requests
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].url.absoluteString, "https://doddy.example.com/v1/assist")
        XCTAssertEqual(sent[0].method, "POST")
        XCTAssertEqual(sent[0].headers["authorization"], "Bearer ds1.token")
        XCTAssertEqual(sent[0].headers["content-type"], "application/json")
        XCTAssertEqual(sent[0].timeout, 35)
        let body = try Fixtures.XCTUnwrapJSON(try XCTUnwrap(sent[0].body))
        XCTAssertEqual(body["userText"] as? String, "hi")
        XCTAssertEqual(body["schemaVersion"] as? Int, 1)
        // No invite code, no gateway address, no user identity: the session says who is asking.
        XCTAssertNil(body["inviteCode"])
        XCTAssertNil(body["userId"])
    }

    func testTheSharedReplyFixtureDecodes() async throws {
        let fixture = try Fixtures.data("assist_response_v1.json")
        let requestID = UUID(uuidString: "6f1c1f5e-3b0a-4c55-9d0e-0a1b2c3d4e51")!
        let request = AssistantRequest(sessionID: UUID(), userText: "Where did I park the car?", requestID: requestID)
        let transport = FakeTransport([.success(GatewayHTTPResponse(status: 200, body: fixture))])
        let reply = try await client(transport, tokens: Tokens(first: "ds1.token", renewed: nil)).respond(request)
        XCTAssertEqual(reply.citedMemoryIDs, [UUID(uuidString: "b7c9d1e2-4f35-4a6b-8c7d-9e0f1a2b3c4d")!])
        XCTAssertTrue(reply.text.hasPrefix("You noted that you parked on level 3"))
    }

    func testAReplyForAnotherRequestOrWithBadCitationsIsDiscarded() async {
        let other = GatewayHTTPResponse(status: 200, body: Data(
            #"{"schemaVersion":1,"requestId":"11111111-1111-4111-8111-111111111111","text":"x","citedMemoryIDs":[]}"#.utf8))
        let badID = GatewayHTTPResponse(status: 200, body: Data(
            #"{"schemaVersion":1,"requestId":"\#(plain.requestID.uuidString.lowercased())","text":"x","citedMemoryIDs":["not-a-uuid"]}"#.utf8))
        for (response, expected) in [(other, AssistantError.malformedResponse), (badID, .invalidCitations)] {
            let transport = FakeTransport([.success(response)])
            do {
                _ = try await client(transport, tokens: Tokens(first: "ds1.token", renewed: nil)).respond(plain)
                XCTFail("expected \(expected)")
            } catch { XCTAssertEqual(error as? AssistantError, expected) }
        }
    }

    // MARK: - signing in

    func testAnExpiredSessionIsRenewedOnceAndTheQuestionAskedAgain() async throws {
        let transport = FakeTransport([.success(failure(401, "unauthenticated")), .success(ok(plain))])
        let tokens = Tokens(first: "ds1.stale", renewed: "ds1.fresh")
        _ = try await client(transport, tokens: tokens).respond(plain)

        let sent = await transport.requests
        XCTAssertEqual(sent.map { $0.headers["authorization"] }, ["Bearer ds1.stale", "Bearer ds1.fresh"])
        let renewals = await tokens.renewals
        XCTAssertEqual(renewals, 1)
    }

    func testAServerThatKeepsRefusingStopsAfterOneRetry() async {
        let transport = FakeTransport([.success(failure(401, "unauthenticated"))])
        let tokens = Tokens(first: "ds1.stale", renewed: "ds1.fresh")
        do { _ = try await client(transport, tokens: tokens).respond(plain); XCTFail("expected notAuthorized") }
        catch { XCTAssertEqual(error as? AssistantError, .notAuthorized) }
        let sent = await transport.requests
        XCTAssertEqual(sent.count, 2)
    }

    func testNoSessionMeansNothingIsSent() async {
        for tokens in [Tokens(first: nil, renewed: nil), Tokens(first: "ds1.stale", renewed: nil)] {
            let transport = FakeTransport([.success(failure(401, "unauthenticated"))])
            do { _ = try await client(transport, tokens: tokens).respond(plain); XCTFail("expected notAuthorized") }
            catch { XCTAssertEqual(error as? AssistantError, .notAuthorized) }
        }
        let none = FakeTransport([.success(ok(plain))])
        _ = try? await client(none, tokens: Tokens(first: nil, renewed: nil)).respond(plain)
        let sent = await none.requests
        XCTAssertTrue(sent.isEmpty, "without a session the question never leaves the iPhone")
    }

    func testABuildWithoutAServerSaysSoAndSendsNothing() async {
        for url in [nil, URL(string: "http://doddy.example.com"), URL(string: "ftp://doddy.example.com")] {
            let transport = FakeTransport([.success(ok(plain))])
            let tokens = Tokens(first: "ds1.token", renewed: nil)
            do { _ = try await client(transport, tokens: tokens, baseURL: url ?? URL(string: "x:")).respond(plain) }
            catch { XCTAssertEqual(error as? AssistantError, .notConfigured) }
            let sent = await transport.requests
            let asked = await tokens.asked
            XCTAssertTrue(sent.isEmpty)
            XCTAssertEqual(asked, 0, "the token isn't even fetched")
        }
        let noURL = BackendAssistantClient(baseURL: nil, session: session(Tokens(first: "t", renewed: nil)), transport: FakeTransport([.success(ok(plain))]))
        do { _ = try await noURL.respond(plain); XCTFail("expected notConfigured") }
        catch { XCTAssertEqual(error as? AssistantError, .notConfigured) }
    }

    // MARK: - the server's errors

    func testEveryServerErrorCodeBecomesAPlainError() {
        let cases: [(Int, String, AssistantError)] = [
            (401, "unauthenticated", .notAuthorized),
            (429, "rate_limited", .rateLimited(retryAfterSeconds: nil)),
            (429, "quota_exceeded", .dailyLimitReached),
            (503, "live_not_configured", .notConfigured),
            (504, "provider_timeout", .timeout),
            (400, "invalid_request", .invalidRequest),
            (413, "payload_too_large", .invalidRequest),
            (422, "refused", .refused),
            (502, "malformed_provider_result", .malformedResponse),
            (502, "provider_unavailable", .providerUnavailable),
            (500, "internal", .providerUnavailable),
            (418, "something_new", .providerUnavailable),
        ]
        for (status, code, expected) in cases {
            XCTAssertEqual(BackendAssistantClient.error(from: failure(status, code)), expected, code)
        }
        XCTAssertFalse(AssistantError.dailyLimitReached.canRetryNow)
    }

    func testRetryAfterComesFromTheBodyOrTheHeader() {
        XCTAssertEqual(BackendAssistantClient.error(from: failure(429, "rate_limited", retryAfter: 7)), .rateLimited(retryAfterSeconds: 7))
        XCTAssertEqual(
            BackendAssistantClient.error(from: failure(429, "rate_limited", headers: ["retry-after": "12"])), .rateLimited(retryAfterSeconds: 12))
    }

    func testAnUnreadableErrorFallsBackToTheStatus() {
        let cases: [(Int, AssistantError)] = [
            (401, .notAuthorized), (429, .rateLimited(retryAfterSeconds: nil)), (400, .invalidRequest), (413, .invalidRequest),
            (504, .timeout), (502, .providerUnavailable), (500, .providerUnavailable),
        ]
        for (status, expected) in cases {
            XCTAssertEqual(BackendAssistantClient.error(from: GatewayHTTPResponse(status: status, body: Data("<html>".utf8))), expected, "\(status)")
        }
    }

    func testNetworkFailuresKeepTheirMeaning() async {
        let cases: [(TransportFailure, AssistantError)] = [(.offline, .offline), (.timedOut, .timeout), (.cancelled, .cancelled), (.other, .providerUnavailable)]
        for (failure, expected) in cases {
            let transport = FakeTransport([.failure(failure)])
            do { _ = try await client(transport, tokens: Tokens(first: "ds1.token", renewed: nil)).respond(plain); XCTFail("expected \(expected)") }
            catch { XCTAssertEqual(error as? AssistantError, expected) }
        }
    }

    func testTheWordingNoLongerMentionsAGatewayOrAnInviteCode() {
        let messages = [AssistantError.notConfigured, .notAuthorized].map(\.userMessage)
        for message in messages {
            XCTAssertFalse(message.lowercased().contains("gateway"), message)
            XCTAssertFalse(message.lowercased().contains("invite"), message)
        }
    }
}
