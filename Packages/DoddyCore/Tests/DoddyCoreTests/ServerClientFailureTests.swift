import XCTest
@testable import DoddyCore

/// How the messaging client reads failures that leave the outcome open (DOD-08): a request that
/// may have reached the server is never reported as "offline, try again".
final class ServerClientFailureTests: XCTestCase {
    func testCallMeNowThatTimesOutIsUnknownAndNotRetried() async throws {
        let transport = StepTransport([.failure(URLError(.timedOut))])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        let request = try await client.callMeNow()
        XCTAssertEqual(request, CallRequest(callId: nil, status: "unknown"))
        let sent = await transport.sent
        XCTAssertEqual(sent.map(\.path), ["/v1/calls/outbound"])
        // Longer than the server's own 15 s ElevenLabs timeout.
        XCTAssertGreaterThan(sent[0].timeout, 15)
    }

    func testCallMeNowThroughATransportThatOnlySaysOfflineIsUnknown() async throws {
        // The app's transport turns every URLSession error, timeouts included, into `.offline`.
        let transport = StepTransport([.failure(ServerError.offline)])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        let request = try await client.callMeNow()
        XCTAssertEqual(request.status, "unknown")
    }

    func testCallMeNowWithNoNetworkAtAllIsOffline() async {
        let transport = StepTransport([.failure(URLError(.notConnectedToInternet))])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        do {
            _ = try await client.callMeNow()
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? ServerError, .offline)
        }
    }

    func testSendNewsNowThatTimesOutIsUnknown() async throws {
        let transport = StepTransport([.failure(URLError(.networkConnectionLost))])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        let result = try await client.sendNewsNow()
        XCTAssertEqual(result.status, "unknown")
        XCTAssertNil(result.digestId)
        let sent = await transport.sent
        XCTAssertGreaterThan(sent[0].timeout, 120, "the server may wait for the AI writer twice")
    }

    func testReadsThatTimeOutAreStillOffline() async {
        let transport = StepTransport([.failure(URLError(.timedOut))])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        do {
            _ = try await client.phoneStatus()
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? ServerError, .offline)
        }
        let sent = await transport.sent
        XCTAssertEqual(sent[0].timeout, ServerRequest.defaultTimeout)
    }

    func testARetriedUpdateKeepsItsIdempotencyKeyUntilTheServerAcceptsIt() async throws {
        let accepted = ServerResponse(status: 202, body: Data(#"{"messages":[]}"#.utf8))
        let transport = StepTransport([.failure(URLError(.timedOut)), .success(accepted), .success(accepted)])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        do {
            _ = try await client.sendUpdate("Hi", channels: [.sms])
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? ServerError, .offline)
        }
        _ = try await client.sendUpdate("Hi", channels: [.sms])
        _ = try await client.sendUpdate("Hi", channels: [.sms])
        let keys = try await transport.sent.map { request in
            try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])["idempotencyKey"] as? String
        }
        XCTAssertEqual(keys[0], keys[1], "the retry is the same update")
        XCTAssertNotEqual(keys[1], keys[2], "once accepted, sending again is a new update")
    }

    func testIdempotencyMismatchIsNotReadAsAChannelThatIsOff() {
        let response = ServerResponse(status: 409, body: Data(#"{"error":"idempotency_mismatch"}"#.utf8))
        XCTAssertEqual(DoddyServerClient.error(from: response), .invalidRequest(fields: ["idempotencyKey"]))
    }

    func testCallInboxListsNotesThatCantBeReadSoTheyCanBeDiscarded() async throws {
        let id = UUID()
        let body = #"{"notes":[],"unreadable":[{"id":"\#(id.uuidString.lowercased())","createdAt":"2026-10-10T09:02:18.197Z"}]}"#
        let transport = StepTransport([.success(ServerResponse(status: 200, body: Data(body.utf8)))])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        let inbox = try await client.callInbox()
        XCTAssertEqual(inbox.unreadable.map(\.id), [id])
        XCTAssertNotNil(inbox.unreadable.first?.createdDate)
        // Older servers send no list.
        let old = try JSONDecoder().decode(CallInbox.self, from: Data(#"{"notes":[]}"#.utf8))
        XCTAssertEqual(old.unreadable, [])
    }

    func testACallInboxThatFailsToLoadIsAnErrorNotAnEmptyInbox() async {
        let transport = StepTransport([.success(ServerResponse(status: 503, body: Data(#"{"error":"not_configured"}"#.utf8)))])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        do {
            _ = try await client.callInbox()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ServerError, .notConfigured("not_configured"))
        }
    }

    func testOnlyErrorsBeforeTheRequestLeftCountAsNotSent() {
        XCTAssertTrue(ServerTransportFailure.certainlyNotSent(URLError(.notConnectedToInternet)))
        XCTAssertTrue(ServerTransportFailure.certainlyNotSent(URLError(.cannotConnectToHost)))
        XCTAssertFalse(ServerTransportFailure.certainlyNotSent(URLError(.timedOut)))
        XCTAssertFalse(ServerTransportFailure.certainlyNotSent(URLError(.networkConnectionLost)))
        XCTAssertFalse(ServerTransportFailure.certainlyNotSent(ServerError.offline))
    }
}

/// Answers each request with the next scripted step: a response or a thrown error.
actor StepTransport: ServerTransport {
    private var steps: [Result<ServerResponse, any Error>]
    private(set) var sent: [ServerRequest] = []

    init(_ steps: [Result<ServerResponse, any Error>]) { self.steps = steps }

    func send(_ request: ServerRequest) async throws -> ServerResponse {
        sent.append(request)
        guard !steps.isEmpty else { throw URLError(.notConnectedToInternet) }
        return try steps.removeFirst().get()
    }
}

final class FixedCredentials: ServerCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    init(token: String? = nil) { self.token = token }

    func load() throws -> String? { lock.withLock { token } }
    func save(_ token: String) throws { lock.withLock { self.token = token } }
    func delete() throws { lock.withLock { token = nil } }
}
