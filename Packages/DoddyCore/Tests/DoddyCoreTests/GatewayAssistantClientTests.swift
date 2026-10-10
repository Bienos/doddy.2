import XCTest
@testable import DoddyCore

/// Scripted HTTP transport that records every request.
actor FakeTransport: HTTPTransport {
    private var script: [Result<HTTPResponse, TransportFailure>]
    private(set) var requests: [HTTPRequest] = []

    init(_ script: [Result<HTTPResponse, TransportFailure>]) { self.script = script }

    func send(_ request: HTTPRequest) async throws(TransportFailure) -> HTTPResponse {
        requests.append(request)
        let next = script.count > 1 ? script.removeFirst() : script[0]
        return try next.get()
    }
}

final class GatewayAssistantClientTests: XCTestCase {
    private let config = GatewayConfiguration(string: "https://doddy-gateway.example.com")!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let host = "doddy-gateway.example.com"

    private func ok(_ body: String) -> HTTPResponse { HTTPResponse(status: 200, body: Data(body.utf8)) }
    private func registerOK(token: String = "v1.tok.sig", ttl: TimeInterval = 3600) -> HTTPResponse {
        ok(#"{"schemaVersion":1,"token":"\#(token)","expiresAtMs":\#(Int64((now.timeIntervalSince1970 + ttl) * 1000))}"#)
    }
    private func answer(for request: AssistantRequest, text: String = "Answer", cited: [UUID] = []) -> HTTPResponse {
        let ids = cited.map { "\"\($0.uuidString.lowercased())\"" }.joined(separator: ",")
        return ok(#"{"schemaVersion":1,"requestId":"\#(request.requestID.uuidString.lowercased())","text":"\#(text)","citedMemoryIDs":[\#(ids)]}"#)
    }
    private func client(_ transport: FakeTransport, credentials: InMemoryCredentialStore, configuration: GatewayConfiguration? = nil) -> GatewayAssistantClient {
        GatewayAssistantClient(configuration: configuration ?? config, transport: transport, credentials: credentials, now: { [now] in now })
    }
    private let plain = AssistantRequest(sessionID: UUID(), userText: "hi")

    // MARK: Contract fixtures (shared with the gateway tests)

    func testRequestEncodingMatchesTheSharedFixtureShape() throws {
        let fixture = try Fixtures.json("assist_request_v1.json")
        let recordID = UUID(uuidString: "b7c9d1e2-4f35-4a6b-8c7d-9e0f1a2b3c4d")!
        let captured = Date(timeIntervalSince1970: 1_791_451_800) // 2026-10-08T09:30:00Z
        let record = try MemoryRecord(
            id: recordID, rawText: "Parked on level 3, near the lift, at the Galeria car park.",
            source: .explicitText, capturedAt: captured)
        let request = AssistantRequest(
            sessionID: UUID(uuidString: "0d3a7c52-8b1e-4f60-a4a9-5d7c1e2f3a64")!,
            userText: "Where did I park the car?",
            groundingMemories: [MemoryCandidate(record: record, matchedTerms: ["park"])],
            recentTurns: [.init(role: .user, text: "Hi"), .init(role: .assistant, text: "Hi, I'm Doddy, an AI. What can I help with?")],
            locale: "en",
            requestID: UUID(uuidString: "6f1c1f5e-3b0a-4c55-9d0e-0a1b2c3d4e51")!)

        let produced = try Fixtures.XCTUnwrapJSON(WireCoding.encode(WireCoding.wireRequest(from: request)))
        XCTAssertEqual(NSDictionary(dictionary: produced), NSDictionary(dictionary: fixture))
    }

    func testResponseAndErrorFixturesDecode() throws {
        let response = try JSONDecoder().decode(AssistWireResponse.self, from: Fixtures.data("assist_response_v1.json"))
        XCTAssertEqual(response.citedMemoryIDs, ["b7c9d1e2-4f35-4a6b-8c7d-9e0f1a2b3c4d"])
        XCTAssertEqual(response.usage, .init(inputTokens: 212, outputTokens: 31))

        let failure = HTTPResponse(status: 429, body: try Fixtures.data("assist_error_v1.json"))
        XCTAssertEqual(GatewayAssistantClient.error(from: failure), .rateLimited(retryAfterSeconds: 30))

        let register = try JSONDecoder().decode(RegisterWireResponse.self, from: Fixtures.data("register_response_v1.json"))
        XCTAssertEqual(register.schemaVersion, 1)
        let registerRequest = try JSONDecoder().decode(RegisterWireRequest.self, from: Fixtures.data("register_request_v1.json"))
        XCTAssertEqual(registerRequest.inviteCode, "EXAMPLE-INVITE-CODE")
    }

    // MARK: Registration and token use

    func testFirstQuestionRegistersThenAsksAndKeepsTheToken() async throws {
        let transport = FakeTransport([.success(registerOK()), .success(answer(for: plain))])
        let credentials = InMemoryCredentialStore(inviteCode: "BETA-1")
        let reply = try await client(transport, credentials: credentials).respond(plain)

        XCTAssertEqual(reply.text, "Answer")
        let sent = await transport.requests
        XCTAssertEqual(sent.map { $0.url.absoluteString }, [
            "https://doddy-gateway.example.com/api/register", "https://doddy-gateway.example.com/api/assist",
        ])
        XCTAssertEqual(sent[1].headers["authorization"], "Bearer v1.tok.sig")
        let stored = await credentials.token()
        XCTAssertEqual(stored?.value, "v1.tok.sig")
    }

    func testAValidStoredTokenIsReusedWithoutRegistering() async throws {
        let transport = FakeTransport([.success(answer(for: plain))])
        let credentials = InMemoryCredentialStore(inviteCode: "BETA-1")
        await credentials.setToken(DeviceToken(value: "v1.old.sig", expiresAt: now.addingTimeInterval(3600), gatewayHost: host))
        _ = try await client(transport, credentials: credentials).respond(plain)
        let sent = await transport.requests
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(sent[0].url.path.hasSuffix("/assist"))
    }

    func testATokenAboutToExpireIsRenewed() async throws {
        let transport = FakeTransport([.success(registerOK()), .success(answer(for: plain))])
        let credentials = InMemoryCredentialStore(inviteCode: "BETA-1")
        await credentials.setToken(DeviceToken(value: "v1.old.sig", expiresAt: now.addingTimeInterval(30), gatewayHost: host))
        _ = try await client(transport, credentials: credentials).respond(plain)
        let sent = await transport.requests
        XCTAssertEqual(sent.count, 2)
    }

    func testATokenIssuedByAnotherHostIsNeverSentToTheNewOne() async throws {
        let transport = FakeTransport([.success(registerOK(token: "v1.new.sig")), .success(answer(for: plain))])
        let credentials = InMemoryCredentialStore(inviteCode: "BETA-1")
        await credentials.setToken(DeviceToken(value: "v1.secret-for-old-host.sig", expiresAt: now.addingTimeInterval(3600), gatewayHost: "old-gateway.example.com"))
        _ = try await client(transport, credentials: credentials).respond(plain)
        let sent = await transport.requests
        XCTAssertEqual(sent.map { $0.url.lastPathComponent }, ["register", "assist"])
        XCTAssertFalse(sent.contains { $0.headers["authorization"]?.contains("secret-for-old-host") == true })
        let stored = await credentials.token()
        XCTAssertEqual(stored?.gatewayHost, host)
    }

    func testA401RegistersAgainOnceAndRetries() async throws {
        let unauthorized = HTTPResponse(status: 401, body: Data(#"{"schemaVersion":1,"error":{"code":"notAuthorized","message":"x"}}"#.utf8))
        let transport = FakeTransport([.success(unauthorized), .success(registerOK(token: "v1.new.sig")), .success(answer(for: plain))])
        let credentials = InMemoryCredentialStore(inviteCode: "BETA-1")
        await credentials.setToken(DeviceToken(value: "v1.stale.sig", expiresAt: now.addingTimeInterval(3600), gatewayHost: host))
        _ = try await client(transport, credentials: credentials).respond(plain)
        let sent = await transport.requests
        XCTAssertEqual(sent.map { $0.url.lastPathComponent }, ["assist", "register", "assist"])
        XCTAssertEqual(sent[2].headers["authorization"], "Bearer v1.new.sig")
    }

    func testRepeated401MeansNotAuthorizedAndStopsAfterOneRetry() async {
        let unauthorized = HTTPResponse(status: 401, body: Data(#"{"schemaVersion":1,"error":{"code":"notAuthorized","message":"x"}}"#.utf8))
        let transport = FakeTransport([.success(registerOK()), .success(unauthorized), .success(registerOK()), .success(unauthorized)])
        let credentials = InMemoryCredentialStore(inviteCode: "BETA-1")
        do { _ = try await client(transport, credentials: credentials).respond(plain); XCTFail("expected notAuthorized") }
        catch { XCTAssertEqual(error as? AssistantError, .notAuthorized) }
        let sent = await transport.requests
        XCTAssertEqual(sent.count, 4)
    }

    func testBadInviteCodeIsNotAuthorizedAndMissingOneIsNotConfigured() async {
        let rejected = HTTPResponse(status: 401, body: Data(#"{"schemaVersion":1,"error":{"code":"notAuthorized","message":"x"}}"#.utf8))
        do { _ = try await client(FakeTransport([.success(rejected)]), credentials: InMemoryCredentialStore(inviteCode: "WRONG")).respond(plain) }
        catch { XCTAssertEqual(error as? AssistantError, .notAuthorized) }

        let transport = FakeTransport([.success(answer(for: plain))])
        do { _ = try await client(transport, credentials: InMemoryCredentialStore()).respond(plain) }
        catch { XCTAssertEqual(error as? AssistantError, .notConfigured) }
        let sent = await transport.requests
        XCTAssertEqual(sent.count, 0, "nothing is sent without an invite code")
    }

    func testNoGatewayAddressMeansNotConfiguredAndNothingIsSent() async {
        let transport = FakeTransport([.success(answer(for: plain))])
        let sut = GatewayAssistantClient(configuration: nil, transport: transport, credentials: InMemoryCredentialStore(inviteCode: "x"))
        do { _ = try await sut.respond(plain) } catch { XCTAssertEqual(error as? AssistantError, .notConfigured) }
        let sent = await transport.requests
        XCTAssertEqual(sent.count, 0)
    }

    // MARK: Egress (A-16)

    func testTheAssistRequestCarriesOnlyApprovedFields() async throws {
        let record = try makeRecord("Parked on level 3")
        let request = AssistantRequest(sessionID: UUID(), userText: "where", groundingMemories: [candidate(record)])
        let transport = FakeTransport([.success(answer(for: request, cited: [record.id]))])
        let credentials = InMemoryCredentialStore(inviteCode: "BETA-SECRET-CODE")
        await credentials.setToken(DeviceToken(value: "v1.tok.sig", expiresAt: now.addingTimeInterval(3600), gatewayHost: host))
        _ = try await client(transport, credentials: credentials).respond(request)

        let sent = await transport.requests[0]
        let object = try Fixtures.XCTUnwrapJSON(XCTUnwrap(sent.body))
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "requestId", "sessionId", "locale", "userText", "turns", "memories"])
        let memory = try XCTUnwrap((object["memories"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(memory.keys), ["id", "text", "source", "capturedAt"])
        let body = String(decoding: try XCTUnwrap(sent.body), as: UTF8.self)
        let deviceID = await credentials.deviceID().uuidString.lowercased()
        XCTAssertFalse(body.contains("BETA-SECRET-CODE"), "invite code never rides in the assist body")
        XCTAssertFalse(body.lowercased().contains(deviceID), "device id never rides in the assist body")
    }

    // MARK: Failures and bad replies (A-15, A-14)

    func testTransportFailuresMapToTheTaxonomy() async {
        let cases: [(TransportFailure, AssistantError)] = [
            (.offline, .offline), (.timedOut, .timeout), (.cancelled, .cancelled), (.other, .providerUnavailable),
        ]
        for (failure, expected) in cases {
            let credentials = InMemoryCredentialStore(inviteCode: "x")
            await credentials.setToken(DeviceToken(value: "v1.t.s", expiresAt: now.addingTimeInterval(3600), gatewayHost: host))
            do { _ = try await client(FakeTransport([.failure(failure)]), credentials: credentials).respond(plain); XCTFail() }
            catch { XCTAssertEqual(error as? AssistantError, expected) }
        }
    }

    func testHTTPStatusesWithoutAWireBodyStillMap() {
        func map(_ status: Int, _ headers: [String: String] = [:]) -> AssistantError {
            GatewayAssistantClient.error(from: HTTPResponse(status: status, headers: headers, body: Data("<html>".utf8)))
        }
        XCTAssertEqual(map(429, ["retry-after": "9"]), .rateLimited(retryAfterSeconds: 9))
        XCTAssertEqual(map(413), .invalidRequest)
        XCTAssertEqual(map(504), .timeout)
        XCTAssertEqual(map(502), .providerUnavailable)
        XCTAssertEqual(map(500), .providerUnavailable)
    }

    func testReplyForADifferentRequestOrWithBrokenJSONIsDiscarded() throws {
        let other = AssistantRequest(sessionID: UUID(), userText: "other")
        XCTAssertThrowsError(try GatewayAssistantClient.interpret(answer(for: other), for: plain)) {
            XCTAssertEqual($0 as? AssistantError, .malformedResponse)
        }
        XCTAssertThrowsError(try GatewayAssistantClient.interpret(ok("not json"), for: plain)) {
            XCTAssertEqual($0 as? AssistantError, .malformedResponse)
        }
        XCTAssertThrowsError(try GatewayAssistantClient.interpret(ok(#"{"schemaVersion":2,"requestId":"x","text":"t","citedMemoryIDs":[]}"#), for: plain)) {
            XCTAssertEqual($0 as? AssistantError, .malformedResponse)
        }
    }

    func testANonUUIDCitationIsInvalidCitations() throws {
        let body = #"{"schemaVersion":1,"requestId":"\#(plain.requestID.uuidString.lowercased())","text":"t","citedMemoryIDs":["n1"]}"#
        XCTAssertThrowsError(try GatewayAssistantClient.interpret(ok(body), for: plain)) {
            XCTAssertEqual($0 as? AssistantError, .invalidCitations)
        }
    }

    // MARK: Configuration

    func testOnlyPlainHTTPSAddressesAreAccepted() {
        XCTAssertEqual(GatewayConfiguration(string: " https://g.example.com/ ")?.baseURL.absoluteString, "https://g.example.com")
        XCTAssertEqual(GatewayConfiguration(string: "https://g.example.com/base/")?.endpoint("assist").absoluteString, "https://g.example.com/base/api/assist")
        for bad in ["", "http://g.example.com", "g.example.com", "https://localhost", "https://user:pw@g.example.com",
                    "https://g.example.com?x=1", "https://g.example.com#f", "ftp://g.example.com"] {
            XCTAssertNil(GatewayConfiguration(string: bad), bad)
        }
    }
}
