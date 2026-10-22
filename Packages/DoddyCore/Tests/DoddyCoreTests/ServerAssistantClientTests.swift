import XCTest
@testable import DoddyCore

/// Messages asks the messaging server (ADR-586): the wire is the gateway's, errors are `AssistantError`s, and a
/// question that may have reached the server without an answer is "took too long", never "offline".
final class ServerAssistantClientTests: XCTestCase {
    private let id = UUID(uuidString: "6f1c1f5e-3b0a-4c55-9d0e-0a1b2c3d4e51")!

    private func request(_ text: String = "Kiedy mam dentystę?") -> AssistantRequest {
        AssistantRequest(sessionID: UUID(), userText: text, locale: "pl", requestID: id)
    }

    private func answer(_ text: String = "W piątek o 9:00.", cited: [UUID] = [], requestID: UUID? = nil) -> Result<ServerResponse, any Error> {
        let ids = cited.map { "\"\($0.uuidString.lowercased())\"" }.joined(separator: ",")
        let body = #"{"schemaVersion":1,"requestId":"\#((requestID ?? id).uuidString.lowercased())","text":"\#(text)","citedMemoryIDs":[\#(ids)],"usage":{"inputTokens":10,"outputTokens":5}}"#
        return .success(ServerResponse(status: 200, body: Data(body.utf8)))
    }

    private func failure(_ status: Int, _ code: String, retryAfter: Int? = nil) -> Result<ServerResponse, any Error> {
        let retry = retryAfter.map { #","retryAfterSeconds":\#($0)"# } ?? ""
        return .success(ServerResponse(status: status, body: Data(#"{"schemaVersion":1,"requestId":"\#(id.uuidString.lowercased())","error":{"code":"\#(code)","message":"m"\#(retry)}}"#.utf8)))
    }

    private func client(_ steps: [Result<ServerResponse, any Error>], token: String? = "tok") -> (ServerAssistantClient, StepTransport, FixedCredentials) {
        let transport = StepTransport(steps)
        let credentials = FixedCredentials(token: token)
        return (ServerAssistantClient(server: DoddyServerClient(transport: transport, credentials: credentials)), transport, credentials)
    }

    private func error(_ block: () async throws -> some Any) async -> AssistantError? {
        do { _ = try await block(); return nil } catch { return error as? AssistantError }
    }

    func testTheQuestionGoesToTheAssistantRouteWithTheDeviceTokenAndTheGatewaysWire() async throws {
        let (client, transport, _) = client([answer()])
        let reply = try await client.respond(request())
        XCTAssertEqual(reply.text, "W piątek o 9:00.")
        let sent = await transport.sent
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].method, .post)
        XCTAssertEqual(sent[0].path, "/v1/assistant/ask")
        XCTAssertEqual(sent[0].bearerToken, "tok")
        XCTAssertEqual(sent[0].timeout, 50)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(sent[0].body)) as? [String: Any])
        XCTAssertEqual(body["schemaVersion"] as? Int, 1)
        XCTAssertEqual(body["userText"] as? String, "Kiedy mam dentystę?")
        XCTAssertEqual(body["locale"] as? String, "pl")
        XCTAssertEqual(body["requestId"] as? String, id.uuidString.lowercased())
        XCTAssertEqual(Set(body.keys), ["schemaVersion", "requestId", "sessionId", "locale", "userText", "turns", "memories"])
    }

    func testAnAccountIsMadeOnFirstUseAndTheCitationsComeBackAsIds() async throws {
        let note = UUID()
        let (client, transport, credentials) = client([
            .success(ServerResponse(status: 201, body: Data(#"{"accountId":"a","deviceToken":"fresh"}"#.utf8))),
            answer(cited: [note]),
        ], token: nil)
        let reply = try await client.respond(request())
        XCTAssertEqual(reply.citedMemoryIDs, [note])
        let sent = await transport.sent
        XCTAssertEqual(sent.map(\.path), ["/v1/accounts", "/v1/assistant/ask"])
        XCTAssertEqual(sent[1].bearerToken, "fresh")
        XCTAssertEqual(try credentials.load(), "fresh")
    }

    func testAnAnswerForAnotherRequestIsRefused() async {
        let (client, _, _) = client([answer(requestID: UUID())])
        let e = await error { try await client.respond(self.request()) }
        XCTAssertEqual(e, .malformedResponse)
    }

    func testTheServersErrorCodesBecomeTheAppsErrors() async {
        let cases: [(Result<ServerResponse, any Error>, AssistantError)] = [
            (failure(400, "invalidRequest"), .invalidRequest),
            (failure(422, "refused"), .refused),
            (failure(429, "dailyLimitReached"), .dailyLimitReached),
            (failure(429, "rateLimited", retryAfter: 30), .rateLimited(retryAfterSeconds: 30)),
            (failure(503, "providerUnavailable"), .providerUnavailable),
            (failure(503, "notConfigured"), .notConfigured),
            (failure(504, "timeout"), .timeout),
            // The shared rate limit answers without the wire body.
            (.success(ServerResponse(status: 429, body: Data(#"{"error":"rate_limited"}"#.utf8))), .rateLimited(retryAfterSeconds: nil)),
            (.success(ServerResponse(status: 413)), .invalidRequest),
            (.success(ServerResponse(status: 500)), .providerUnavailable),
        ]
        for (step, expected) in cases {
            let (client, _, _) = client([step])
            let e = await error { try await client.respond(self.request()) }
            XCTAssertEqual(e, expected)
        }
    }

    func testARevokedTokenIsReplacedOnceAndTheQuestionIsAskedAgain() async throws {
        let (client, transport, credentials) = client([
            .success(ServerResponse(status: 401)),
            .success(ServerResponse(status: 201, body: Data(#"{"accountId":"b","deviceToken":"second"}"#.utf8))),
            answer(),
        ], token: "old")
        let reply = try await client.respond(request())
        XCTAssertEqual(reply.text, "W piątek o 9:00.")
        let sent = await transport.sent
        XCTAssertEqual(sent.map(\.path), ["/v1/assistant/ask", "/v1/accounts", "/v1/assistant/ask"])
        XCTAssertEqual(sent[2].bearerToken, "second")
        XCTAssertEqual(try credentials.load(), "second")
    }

    func testARevokedTokenTwiceIsNotAuthorizedAndIsNotRetriedAgain() async {
        let (client, transport, _) = client([
            .success(ServerResponse(status: 401)),
            .success(ServerResponse(status: 201, body: Data(#"{"accountId":"b","deviceToken":"second"}"#.utf8))),
            .success(ServerResponse(status: 401)),
        ], token: "old")
        let e = await error { try await client.respond(self.request()) }
        XCTAssertEqual(e, .notAuthorized)
        let count = await transport.sent.count
        XCTAssertEqual(count, 3)
    }

    func testNoNetworkIsOfflineButATimeoutOrADroppedConnectionIsTookTooLong() async {
        let (never, _, _) = client([.failure(URLError(.notConnectedToInternet))])
        let offline = await error { try await never.respond(self.request()) }
        XCTAssertEqual(offline, .offline, "it certainly never left the phone")

        for code in [URLError.Code.timedOut, .networkConnectionLost] {
            let (maybe, _, _) = client([.failure(URLError(code))])
            let e = await error { try await maybe.respond(self.request()) }
            XCTAssertEqual(e, .timeout, "it may have reached the server, so it is not 'offline, try again'")
        }
    }

    func testStoppingTheQuestionIsCancelledNotAnError() async {
        let (client, _, _) = client([.failure(URLError(.cancelled))])
        let question = request()
        let task = Task { try await client.respond(question) }
        task.cancel()
        do { _ = try await task.value; XCTFail("expected cancelled") } catch {
            // A cancelled task that the transport turned into URLError.cancelled is cancelled; one that had
            // already finished before cancel() can only be a timeout.
            XCTAssertTrue([AssistantError.cancelled, .timeout].contains(error as? AssistantError), "\(error)")
        }
    }

    func testWithoutAServerAddressItIsNotConfiguredAndNothingIsSent() async {
        let e = await error { try await ServerAssistantClient(server: nil).respond(self.request()) }
        XCTAssertEqual(e, .notConfigured)
    }

    func testTheServiceUsesItLikeAnyOtherClient() async throws {
        let client = ServerAssistantClient(server: DoddyServerClient(transport: EchoTransport(), credentials: FixedCredentials(token: "tok")))
        let service = AssistantService(recall: StubRecall(), client: client, backoff: [], sleep: { _ in })
        let result = try await service.ask("Kiedy mam dentystę?", sessionID: UUID(), history: [], locale: "pl",
                                           policy: AssistantPolicy(consentGranted: true, includeNotes: false))
        XCTAssertEqual(result.answer.text, "Odpowiedź.")
        XCTAssertEqual(result.answer.basis, .general)
    }
}

/// Answers every question with the request id it was sent, as the server does.
private struct EchoTransport: ServerTransport {
    func send(_ request: ServerRequest) async throws -> ServerResponse {
        let sent = try JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any]
        let requestID = sent?["requestId"] as? String ?? ""
        return ServerResponse(status: 200, body: Data(#"{"schemaVersion":1,"requestId":"\#(requestID)","text":"Odpowiedź.","citedMemoryIDs":[]}"#.utf8))
    }
}

private struct StubRecall: RecallService {
    func recall(_ question: String, limit: Int) async throws -> RecallOutcome { .noMatch }
}
