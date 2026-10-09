import Foundation
import XCTest
@testable import DoddyCore

/// Shared fixtures written by the backend (`npm run fixtures`); the TypeScript tests validate the same files.
private func fixture(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("contracts/connected-apps/\(name).json"))
}

private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    try JSONDecoder().decode(T.self, from: fixture(name))
}

final class ConnectedAppsContractTests: XCTestCase {
    func testEveryFixtureDecodes() throws {
        let view = try decode(ConnectionView.self, "connection-view-disconnected")
        XCTAssertEqual(view.status, .disconnected)
        XCTAssertFalse(view.access.canWrite)

        let connect = try decode(ConnectResponse.self, "connect-response-mock")
        XCTAssertEqual(connect.mode, .mock)
        XCTAssertNil(connect.authorizationUrl, "mock mode never opens a sign-in page")

        let connected = try decode(ConnectionResult.self, "connection-result-connected")
        XCTAssertEqual(connected.connection.status, .connected)
        XCTAssertEqual(connected.receipt.status, .succeeded)

        let broad = try decode(ConnectionResult.self, "connection-result-not-read-only")
        XCTAssertEqual(broad.connection.status, .permissionInsufficient)
        XCTAssertEqual(broad.connection.reason, .grantNotReadOnly)
        XCTAssertEqual(broad.receipt.status, .blocked)

        let off = try decode(ConnectionResult.self, "connection-result-disconnected")
        XCTAssertEqual(off.connection.status, .disconnected)

        let events = try decode(EventsResult.self, "events-result-mock")
        XCTAssertEqual(events.mode, .mock)
        XCTAssertEqual(events.events.count, 3)
        XCTAssertTrue(events.events[0].allDay)
        XCTAssertTrue(events.events[1].isRecurring)
        XCTAssertNil(events.receipt.providerReference)

        let empty = try decode(EventsResult.self, "events-result-empty")
        XCTAssertTrue(empty.events.isEmpty)
        XCTAssertEqual(empty.receipt.status, .succeeded)

        let limited = try decode(ConnectedAppsErrorBody.self, "error-rate-limited")
        XCTAssertEqual(limited.error.code, "rate_limited")
        XCTAssertEqual(limited.error.retryAfterSeconds, 30)

        let blocked = try decode(ConnectedAppsErrorBody.self, "error-not-connected")
        XCTAssertEqual(blocked.error.receipt?.status, .blocked)
    }

    func testCompleteRequestEncodesTheServersUnion() throws {
        let id = UUID(uuidString: "8B0C7F1E-2D3A-4B5C-9D8E-0F1A2B3C4D5E")!
        func json(_ result: CompletionResult) throws -> [String: Any] {
            let data = try JSONEncoder().encode(CompleteRequest(attemptId: id, nonce: "n", result: result))
            return try JSONSerialization.jsonObject(with: data) as! [String: Any]
        }
        let callback = try json(.callback(status: "success", connectedAccountId: "ca_1"))
        XCTAssertEqual(callback["attemptId"] as? String, "8b0c7f1e-2d3a-4b5c-9d8e-0f1a2b3c4d5e")
        XCTAssertEqual(callback["result"] as? [String: String], ["kind": "callback", "status": "success", "connectedAccountId": "ca_1"])
        XCTAssertEqual(try json(.verifier(sessionUri: "s"))["result"] as? [String: String], ["kind": "verifier", "sessionUri": "s"])
        XCTAssertEqual(try json(.canceled)["result"] as? [String: String], ["kind": "canceled"])
        XCTAssertEqual(try json(.mock(approve: false))["result"] as? [String: String], ["kind": "mock", "outcome": "deny"])
    }

    func testResponsesDecodeOrFailTyped() throws {
        XCTAssertThrowsError(try BackendConnectedAppsClient.decode(status: 401, data: Data()) as ConnectionView) {
            XCTAssertEqual($0 as? ConnectedAppsError, .unauthenticated)
        }
        XCTAssertThrowsError(try BackendConnectedAppsClient.decode(status: 409, data: try fixture("error-not-connected")) as EventsResult) {
            guard case .server(let code, _, _, let receipt)? = $0 as? ConnectedAppsError else { return XCTFail("\($0)") }
            XCTAssertEqual(code, "not_connected")
            XCTAssertEqual(receipt?.status, .blocked)
        }
        // A 200 with a body that doesn't match is an error, never an empty day.
        XCTAssertThrowsError(try BackendConnectedAppsClient.decode(status: 200, data: Data(#"{"events":[]}"#.utf8)) as EventsResult) {
            XCTAssertEqual($0 as? ConnectedAppsError, .unreadableResponse)
        }
    }

    func testServerURLMustBeHTTPSOrLoopback() {
        XCTAssertTrue(BackendConnectedAppsClient.isAllowed(URL(string: "https://doddy.example.com")!))
        XCTAssertTrue(BackendConnectedAppsClient.isAllowed(URL(string: "http://127.0.0.1:8787")!))
        XCTAssertTrue(BackendConnectedAppsClient.isAllowed(URL(string: "http://localhost:8787")!))
        XCTAssertFalse(BackendConnectedAppsClient.isAllowed(URL(string: "http://doddy.example.com")!))
        XCTAssertFalse(BackendConnectedAppsClient.isAllowed(URL(string: "ftp://doddy.example.com")!))
        XCTAssertFalse(BackendConnectedAppsClient.isAllowed(URL(string: "https://doddy.example.com?x=1")!))
    }
}

final class ConnectedAppsSupportTests: XCTestCase {
    private func date(_ iso: String) -> Date { ConnectedAppsDates.instant(iso)! }

    func testTomorrowIsTheNextLocalDateInTheGivenZone() {
        let lateUTC = date("2026-10-09T23:30:00Z")
        XCTAssertEqual(LocalDay.tomorrow(from: lateUTC, in: TimeZone(identifier: "Europe/Warsaw")!), "2026-10-11")
        XCTAssertEqual(LocalDay.tomorrow(from: lateUTC, in: TimeZone(identifier: "America/Los_Angeles")!), "2026-10-10")
        // The evening before the autumn DST change.
        XCTAssertEqual(LocalDay.tomorrow(from: date("2026-10-24T21:59:00Z"), in: TimeZone(identifier: "Europe/Warsaw")!), "2026-10-25")
    }

    func testCallbackParsingAcceptsOnlyTheExpectedSchemeAndAttempt() {
        let id = UUID(uuidString: "8B0C7F1E-2D3A-4B5C-9D8E-0F1A2B3C4D5E")!
        let ok = URL(string: "doddy-dev://connected-apps/return?attempt=8b0c7f1e-2d3a-4b5c-9d8e-0f1a2b3c4d5e&status=success&connected_account_id=ca_1")!
        XCTAssertEqual(ConnectionCallback.result(from: ok, expectedScheme: "doddy-dev", attemptId: id), .callback(status: "success", connectedAccountId: "ca_1"))
        XCTAssertNil(ConnectionCallback.result(from: ok, expectedScheme: "doddy", attemptId: id))
        let other = URL(string: "doddy-dev://connected-apps/return?attempt=00000000-0000-4000-8000-000000000000&status=success")!
        XCTAssertNil(ConnectionCallback.result(from: other, expectedScheme: "doddy-dev", attemptId: id))
        let doubled = URL(string: "doddy-dev://connected-apps/return?status=failed&status=success")!
        XCTAssertNil(ConnectionCallback.result(from: doubled, expectedScheme: "doddy-dev", attemptId: id))
        let verifier = URL(string: "doddy-dev://connected-apps/return?session_uri=composio%3A%2F%2Fs%2F1")!
        XCTAssertEqual(ConnectionCallback.result(from: verifier, expectedScheme: "doddy-dev", attemptId: id), .verifier(sessionUri: "composio://s/1"))
    }

    func testMemoryTextNamesTheSourceAndLocalTime() throws {
        let result = try decode(EventsResult.self, "events-result-mock")
        XCTAssertEqual(
            ConnectedAppsDates.memoryText(for: result.events[2], window: result.window),
            "Demo: Dentist — 2026-10-10 14:00–14:45 Europe/Warsaw (from Google Calendar)")
        XCTAssertEqual(
            ConnectedAppsDates.memoryText(for: result.events[0], window: result.window),
            "Demo: Mum's birthday — 2026-10-10, all day (from Google Calendar)")
    }

    func testConnectedAccountsIsLimitedNotAvailable() {
        XCTAssertEqual(CapabilityCatalog.v1ConnectedApps.status(of: .connectedAccounts), .limited("Google Calendar read-only, needs a Doddy server"))
        XCTAssertFalse(CapabilityCatalog.v1ConnectedApps.isAvailable(.connectedAccounts))
        XCTAssertEqual(CapabilityCatalog.m0.status(of: .connectedAccounts), .notImplemented(plannedMilestone: "unscheduled"))
    }
}

// MARK: - View model

private actor FakeClient: ConnectedAppsClient {
    var view: ConnectionView
    var calls: [String] = []
    var completions: [CompletionResult] = []
    var eventsError: ConnectedAppsError?
    let attempt: ConnectResponse
    let connected: ConnectionResult
    let disconnected: ConnectionResult
    let events: EventsResult

    init(liveURL: URL? = nil) throws {
        view = try decode(ConnectionView.self, "connection-view-disconnected")
        let mock = try decode(ConnectResponse.self, "connect-response-mock")
        attempt = liveURL == nil ? mock : ConnectResponse(
            mode: .live, attemptId: mock.attemptId, nonce: mock.nonce, authorizationUrl: liveURL,
            callbackScheme: mock.callbackScheme, expiresAt: mock.expiresAt)
        connected = try decode(ConnectionResult.self, "connection-result-connected")
        disconnected = try decode(ConnectionResult.self, "connection-result-disconnected")
        events = try decode(EventsResult.self, "events-result-mock")
    }

    func setEventsError(_ error: ConnectedAppsError?) { eventsError = error }
    func setView(_ newView: ConnectionView) { view = newView }

    func status() async throws(ConnectedAppsError) -> ConnectionView { calls.append("status"); return view }
    func connect() async throws(ConnectedAppsError) -> ConnectResponse { calls.append("connect"); return attempt }
    func complete(_ request: CompleteRequest) async throws(ConnectedAppsError) -> ConnectionResult {
        calls.append("complete")
        completions.append(request.result)
        switch request.result {
        case .mock(true), .callback("success", _), .verifier:
            view = connected.connection
            return connected
        default:
            return ConnectionResult(connection: view, receipt: connected.receipt)
        }
    }
    func tomorrowEvents(_ request: EventsRequest) async throws(ConnectedAppsError) -> EventsResult {
        calls.append("events:\(request.date):\(request.timeZone)")
        if let eventsError { throw eventsError }
        return events
    }
    func disconnect() async throws(ConnectedAppsError) -> ConnectionResult {
        calls.append("disconnect")
        view = disconnected.connection
        return disconnected
    }
    func receipts() async throws(ConnectedAppsError) -> [ConnectedAppReceipt] { calls.append("receipts"); return [] }
}

private struct FakeAuthenticator: WebAuthenticator {
    let result: Result<URL, WebAuthenticationError>
    func authenticate(url: URL, callbackScheme: String) async throws(WebAuthenticationError) -> URL { try result.get() }
}

@MainActor
final class ConnectedAppsModelTests: XCTestCase {
    private let warsaw = TimeZone(identifier: "Europe/Warsaw")!
    private let now = ConnectedAppsDates.instant("2026-10-09T10:00:00Z")!

    func testWithoutAServerEverythingSaysNotConfigured() async {
        let model = ConnectedAppsModel(client: nil, authenticator: FakeAuthenticator(result: .failure(.failed)))
        XCTAssertEqual(model.cardState, .notConfigured)
        await model.connect()
        XCTAssertEqual(model.cardState, .notConfigured)
        XCTAssertNil(model.events)
    }

    func testMockFlowAsksForADemoTapThenReadsAndLabelsDemoData() async throws {
        let client = try FakeClient()
        let model = ConnectedAppsModel(client: client, authenticator: FakeAuthenticator(result: .failure(.failed)))
        await model.load()
        XCTAssertEqual(model.cardState, .disconnected)
        await model.connect()
        XCTAssertEqual(model.cardState, .awaitingDemoApproval, "no fake Google sign-in in mock mode")
        await model.completeDemo(approve: true)
        XCTAssertEqual(model.cardState, .connected)
        XCTAssertTrue(model.isDemo)

        await model.loadTomorrow(now: now, timeZone: warsaw)
        XCTAssertEqual(model.events?.events.count, 3)
        XCTAssertEqual(model.lastReceipt?.operation, .read)
        let calls = await client.calls
        XCTAssertTrue(calls.contains("events:2026-10-10:Europe/Warsaw"), "\(calls)")
    }

    func testLiveFlowUsesTheSystemBrowserAndSendsTheCallbackToTheServer() async throws {
        let client = try FakeClient(liveURL: URL(string: "https://connect.composio.dev/link/x")!)
        let attempt = client.attempt
        let callback = URL(string: "doddy-dev://connected-apps/return?attempt=\(attempt.attemptId.uuidString.lowercased())&status=success&connected_account_id=ca_1")!
        let model = ConnectedAppsModel(client: client, authenticator: FakeAuthenticator(result: .success(callback)))
        await model.load()
        await model.connect()
        let completions = await client.completions
        XCTAssertEqual(completions, [.callback(status: "success", connectedAccountId: "ca_1")])
        XCTAssertEqual(model.cardState, .connected)
    }

    func testClosingTheBrowserIsReportedAsCanceled() async throws {
        let client = try FakeClient(liveURL: URL(string: "https://connect.composio.dev/link/x")!)
        let model = ConnectedAppsModel(client: client, authenticator: FakeAuthenticator(result: .failure(.canceled)))
        await model.load()
        await model.connect()
        let completions = await client.completions
        XCTAssertEqual(completions, [.canceled])
        XCTAssertEqual(model.cardState, .disconnected)
    }

    func testAnErrorIsNeverShownAsAnEmptyDay() async throws {
        let client = try FakeClient()
        let model = ConnectedAppsModel(client: client, authenticator: FakeAuthenticator(result: .failure(.failed)))
        await model.load()
        await model.connect()
        await model.completeDemo(approve: true)
        await model.loadTomorrow(now: now, timeZone: warsaw)
        XCTAssertNotNil(model.events)
        await client.setEventsError(.server(code: "provider_timeout", message: "Google Calendar took too long to answer. Nothing was changed.", retryAfterSeconds: nil, receipt: nil))
        await model.loadTomorrow(now: now, timeZone: warsaw)
        XCTAssertNil(model.events, "stale or empty results are not shown for a failed read")
        XCTAssertEqual(model.message, "Google Calendar took too long to answer. Nothing was changed.")
    }

    func testExpiredAccessRefreshesStatusAndClearsEvents() async throws {
        let client = try FakeClient()
        let model = ConnectedAppsModel(client: client, authenticator: FakeAuthenticator(result: .failure(.failed)))
        await model.load()
        await model.connect()
        await model.completeDemo(approve: true)
        await model.loadTomorrow(now: now, timeZone: warsaw)
        let connected = client.connected.connection
        let expired = ConnectionView(
            provider: connected.provider, mode: connected.mode, status: .expired, reason: .revokedOrExpired,
            accountLabel: nil, connectedAt: nil, lastCheckedAt: nil, remoteCleanup: .none, access: connected.access)
        await client.setView(expired)
        await client.setEventsError(.server(code: "connection_expired", message: "expired", retryAfterSeconds: nil, receipt: nil))
        await model.loadTomorrow(now: now, timeZone: warsaw)
        XCTAssertEqual(model.cardState, .expired)
        XCTAssertNil(model.events)
    }

    func testDisconnectClearsTransientEventsAndBlocksReads() async throws {
        let client = try FakeClient()
        let model = ConnectedAppsModel(client: client, authenticator: FakeAuthenticator(result: .failure(.failed)))
        await model.load()
        await model.connect()
        await model.completeDemo(approve: true)
        await model.loadTomorrow(now: now, timeZone: warsaw)
        await model.disconnect()
        XCTAssertNil(model.events)
        XCTAssertEqual(model.cardState, .disconnected)
        let before = await client.calls.count
        await model.loadTomorrow(now: now, timeZone: warsaw)
        let after = await client.calls.count
        XCTAssertEqual(before, after, "no read is attempted while disconnected")
    }

    func testResultsExpire() async throws {
        let client = try FakeClient()
        let model = ConnectedAppsModel(client: client, authenticator: FakeAuthenticator(result: .failure(.failed)))
        await model.load()
        await model.connect()
        await model.completeDemo(approve: true)
        await model.loadTomorrow(now: now, timeZone: warsaw)
        let expiry = ConnectedAppsDates.instant(model.events!.expiresAt)!
        model.discardExpiredEvents(now: expiry.addingTimeInterval(-1))
        XCTAssertNotNil(model.events)
        model.discardExpiredEvents(now: expiry)
        XCTAssertNil(model.events)
    }

    func testDuplicateTapsDoNotStartTwoConnections() async throws {
        let client = try FakeClient()
        let model = ConnectedAppsModel(client: client, authenticator: FakeAuthenticator(result: .failure(.failed)))
        await model.load()
        async let first: Void = model.connect()
        async let second: Void = model.connect()
        _ = await (first, second)
        let connects = await client.calls.filter { $0 == "connect" }.count
        XCTAssertEqual(connects, 1)
    }
}
