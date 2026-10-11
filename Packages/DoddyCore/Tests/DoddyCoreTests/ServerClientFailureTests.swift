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

    func testParallelFirstUsesCreateOneAccount() async throws {
        let transport = SlowAccountTransport()
        let store = FixedCredentials()
        let client = DoddyServerClient(transport: transport, credentials: store)
        async let first = client.phoneStatus()
        async let second = client.phoneStatus()
        _ = try await (first, second)
        let created = await transport.accountsCreated
        XCTAssertEqual(created, 1)
        XCTAssertEqual(try store.load(), "tok1")
    }

    func testEveryReadSharesOneRuleAnUnreadableReplyIsAnError() async {
        let garbage = ServerResponse(status: 200, body: Data("{}".utf8))
        let transport = StepTransport(Array(repeating: .success(garbage), count: 4))
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        let reads: [(String, () async throws -> Void)] = [
            ("phone", { _ = try await client.phoneStatus() }),
            ("calls", { _ = try await client.callSettings() }),
            ("notes", { _ = try await client.callInbox() }),
            ("news", { _ = try await client.newsDigests() }),
        ]
        for (name, read) in reads {
            do {
                try await read()
                XCTFail("\(name): an unreadable reply must not become a value")
            } catch {
                XCTAssertEqual(error as? ServerError, .unexpected(status: 200), name)
            }
        }
        let paths = await transport.sent.map(\.path)
        XCTAssertEqual(paths, ["/v1/phone", "/v1/calls/settings", "/v1/call-notes", "/v1/news/digests"])
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

/// Takes a while to create an account, so a second first use arrives while the first is waiting.
private actor SlowAccountTransport: ServerTransport {
    private(set) var accountsCreated = 0

    func send(_ request: ServerRequest) async throws -> ServerResponse {
        guard request.path == "/v1/accounts" else {
            return ServerResponse(status: 200, body: Data(#"{"phone":null,"smsEnabled":false,"optedOut":false}"#.utf8))
        }
        accountsCreated += 1
        let token = "tok\(accountsCreated)"
        try await Task.sleep(for: .milliseconds(200))
        return ServerResponse(status: 201, body: Data(#"{"accountId":"a","deviceToken":"\#(token)"}"#.utf8))
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
