import Foundation
import XCTest
@testable import DoddyCore

// ADR-483: the in-conversation card for an online account that isn't connected or a tool that is off.

private func fixtureData(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("contracts/online-accounts/\(name).json"))
}

/// A fixture with some fields changed, decoded as `T`.
private func edited<T: Decodable>(_ type: T.Type, _ name: String, _ change: (inout [String: Any]) -> Void = { _ in }) throws -> T {
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData(name)) as? [String: Any])
    change(&object)
    return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
}

/// The first toolkit in a catalog fixture whose id is `id`, changed.
private func catalogFixture(_ name: String, toolkit id: String, _ change: @escaping (inout [String: Any]) -> Void) throws -> ToolsCatalog {
    try edited(ToolsCatalog.self, name) { object in
        var toolkits = object["toolkits"] as! [[String: Any]]
        let index = toolkits.firstIndex { $0["id"] as? String == id }!
        change(&toolkits[index])
        object["toolkits"] = toolkits
    }
}

private func serverError(_ name: String) throws -> OnlineAccountsError {
    do {
        _ = try BackendOnlineAccountsClient.decode(status: 403, data: try fixtureData(name)) as RunResult
        throw XCTSkip("fixture \(name) decoded as a success")
    } catch let error as OnlineAccountsError {
        return error
    }
}

private func code(_ code: String) -> OnlineAccountsError {
    .server(code: code, message: "m", retryAfterSeconds: nil, receipt: nil)
}

final class CloudAccessOfferTests: XCTestCase {
    func testANewUsersFirstAskOffersConnectEvenThoughTheServerSaidSwitchedOff() throws {
        // The server checks the switch before the connection, so this is what a new user gets.
        let error = try serverError("error-tool-disabled")
        XCTAssertEqual(error.code, "capability_disabled")
        let offer = try XCTUnwrap(CloudAccessOffer.decide(
            after: error, tool: "check_email", catalog: try edited(ToolsCatalog.self, "catalog-disconnected")))
        XCTAssertEqual(offer.kind, .connect)
        XCTAssertEqual(offer.toolkit, "gmail")
        XCTAssertEqual(offer.accountTitle, "Gmail")
        XCTAssertEqual(offer.tool, "check_email")
        XCTAssertEqual(offer.toolTitle, "Check my email")
        XCTAssertTrue(offer.isDemo, "the mock server's card says it is a demo")
    }

    func testAConnectedAccountWithTheSwitchOffOffersOnlyTheSwitch() throws {
        let catalog = try edited(ToolsCatalog.self, "catalog-gmail-on")
        let offer = try XCTUnwrap(CloudAccessOffer.decide(after: try serverError("error-tool-disabled"), tool: "read_email", catalog: catalog))
        XCTAssertEqual(offer.kind, .turnOn)
        XCTAssertEqual(offer.toolTitle, "Read an email")
    }

    func testExpiredOrWrongAccessOffersReconnect() throws {
        for status in ["expired", "permission_insufficient"] {
            let catalog = try catalogFixture("catalog-disconnected", toolkit: "gmail") { $0["status"] = status }
            let offer = CloudAccessOffer.decide(after: code("connection_expired"), tool: "check_email", catalog: catalog)
            XCTAssertEqual(offer?.kind, .reconnect, status)
        }
        let insufficient = try serverError("error-permission-insufficient")
        let catalog = try catalogFixture("catalog-disconnected", toolkit: "gmail") { $0["status"] = "permission_insufficient" }
        XCTAssertEqual(CloudAccessOffer.decide(after: insufficient, tool: "check_email", catalog: catalog)?.kind, .reconnect)
    }

    func testNoOfferWhenTheServerCantConnectTheAccount() throws {
        let catalog = try catalogFixture("catalog-disconnected", toolkit: "gmail") { $0["status"] = "unavailable" }
        XCTAssertNil(CloudAccessOffer.decide(after: code("not_connected"), tool: "check_email", catalog: catalog))
    }

    func testNoOfferWhenTheToolIsAlreadyOn() throws {
        // The catalog is newer than the error: nothing for the user to do.
        let catalog = try edited(ToolsCatalog.self, "catalog-gmail-on")
        XCTAssertNil(CloudAccessOffer.decide(after: code("capability_disabled"), tool: "check_email", catalog: catalog))
    }

    func testFailuresThatArentAboutAccessNeverOfferASignIn() throws {
        let catalog = try edited(ToolsCatalog.self, "catalog-disconnected")
        // A write that may have gone through is never answered with a sign-in.
        let unsureReceipt = try edited(OnlineToolReceipt.self, "error-tool-disabled") { object in
            var receipt = (object["error"] as! [String: Any])["receipt"] as! [String: Any]
            receipt["status"] = "outcome_unknown"
            object = receipt
        }
        let unsure = OnlineAccountsError.server(code: "capability_disabled", message: "m", retryAfterSeconds: nil, receipt: unsureReceipt)
        let errors: [OnlineAccountsError] = [
            try serverError("error-rate-limited"),
            try serverError("error-confirmation-expired"),
            unsure,
            code("live_not_configured"),
            code("provider_unavailable"),
            .transport("URLError"),
            .unreadableResponse,
            .unauthenticated,
            .notConfigured,
        ]
        for error in errors {
            XCTAssertNil(CloudAccessOffer.decide(after: error, tool: "check_email", catalog: catalog), "\(error)")
        }
    }

    func testAToolTheCatalogDoesntListGetsNoOffer() throws {
        let catalog = try edited(ToolsCatalog.self, "catalog-disconnected")
        XCTAssertNil(CloudAccessOffer.decide(after: code("not_connected"), tool: "send_email", catalog: catalog))
    }

    func testWebSearchHasNoAccountSoOnlyItsSwitchIsOffered() throws {
        let catalog = try edited(ToolsCatalog.self, "catalog-disconnected")
        let offer = CloudAccessOffer.decide(after: code("capability_disabled"), tool: "web_search", catalog: catalog)
        XCTAssertEqual(offer?.kind, .turnOn)
    }

    func testTheAgentIsToldToPointAtTheCardNotSettings() throws {
        let offer = try XCTUnwrap(CloudAccessOffer.decide(
            after: try serverError("error-tool-disabled"), tool: "check_email", catalog: try edited(ToolsCatalog.self, "catalog-disconnected")))
        let reply = CloudAccess.agentReply(offer)
        XCTAssertTrue(reply.hasPrefix("failed: Gmail isn't connected."))
        XCTAssertTrue(reply.contains("Nothing was done"))
        XCTAssertFalse(reply.contains("Online accounts"), "no detour to Settings")
        let message = CloudAccess.agentMessage(offer)
        XCTAssertTrue(message.contains("connected Gmail and switched on \"Check my email\""))
        XCTAssertTrue(message.contains("check_email, once"))
    }
}

// MARK: - The tap

private actor AccessClient: OnlineAccountsClient {
    var connectResponse: ConnectResponse
    var completeResult: ToolkitResult
    var switchResult: ToolkitResult
    var connectError: OnlineAccountsError?
    private(set) var calls: [String] = []
    private(set) var completions: [CompletionResult] = []

    init(connect: ConnectResponse, complete: ToolkitResult, switched: ToolkitResult) {
        connectResponse = connect
        completeResult = complete
        switchResult = switched
    }

    func failConnect(_ error: OnlineAccountsError) { connectError = error }
    func setComplete(_ result: ToolkitResult) { completeResult = result }
    func setSwitchResult(_ result: ToolkitResult) { switchResult = result }

    func catalog() async throws(OnlineAccountsError) -> ToolsCatalog { throw .notConfigured }
    func connect(toolkit: String) async throws(OnlineAccountsError) -> ConnectResponse {
        calls.append("connect:\(toolkit)")
        if let connectError { throw connectError }
        return connectResponse
    }
    func complete(toolkit: String, _ request: CompleteRequest) async throws(OnlineAccountsError) -> ToolkitResult {
        calls.append("complete:\(toolkit)")
        completions.append(request.result)
        return completeResult
    }
    func disconnect(toolkit: String) async throws(OnlineAccountsError) -> ToolkitResult {
        calls.append("disconnect:\(toolkit)")
        throw .notConfigured
    }
    func setSwitch(tool: String, enabled: Bool) async throws(OnlineAccountsError) -> ToolkitResult {
        calls.append("switch:\(tool):\(enabled)")
        return switchResult
    }
    func prepare(_ call: CloudToolCall) async throws(OnlineAccountsError) -> PrepareResult { throw .notConfigured }
    func run(_ call: CloudToolCall, timeZone: String, approvalId: UUID?) async throws(OnlineAccountsError) -> RunResult { throw .notConfigured }
    func receipts() async throws(OnlineAccountsError) -> [OnlineToolReceipt] { [] }
}

private final class ScriptedAuthenticator: WebAuthenticator, @unchecked Sendable {
    enum Script { case returnQuery(String), fail(WebAuthenticationError) }
    let script: Script
    private(set) var opened: [(url: URL, scheme: String)] = []
    init(_ script: Script) { self.script = script }

    func authenticate(url: URL, callbackScheme: String) async throws(WebAuthenticationError) -> URL {
        opened.append((url, callbackScheme))
        switch script {
        case .returnQuery(let query): return URL(string: "\(callbackScheme)://oauth?\(query)")!
        case .fail(let error): throw error
        }
    }
}

final class CloudAccessOpenTests: XCTestCase {
    private func offer(_ kind: CloudAccessOffer.Kind, tool: String = "check_email") -> CloudAccessOffer {
        CloudAccessOffer(kind: kind, toolkit: "gmail", accountTitle: "Gmail", tool: tool, toolTitle: "Check my email", isDemo: false)
    }

    private func liveConnect() throws -> ConnectResponse {
        try edited(ConnectResponse.self, "connect-response-mock") { object in
            object["mode"] = "live"
            object["authorizationUrl"] = "https://connect.example.com/link/abc"
        }
    }

    private func makeClient(connect: ConnectResponse? = nil) throws -> AccessClient {
        AccessClient(
            connect: try connect ?? edited(ConnectResponse.self, "connect-response-mock"),
            complete: try edited(ToolkitResult.self, "toolkit-result-connected"),
            switched: try edited(ToolkitResult.self, "switch-result-on"))
    }

    func testDemoTapConnectsAndSwitchesOnOnlyTheToolAskedFor() async throws {
        let client = try makeClient()
        let auth = ScriptedAuthenticator(.fail(.failed))
        let outcome = await CloudAccess.open(offer(.connect), client: client, authenticator: auth)
        XCTAssertEqual(outcome, .ready)
        let calls = await client.calls
        XCTAssertEqual(calls, ["connect:gmail", "complete:gmail", "switch:check_email:true"])
        let completions = await client.completions
        XCTAssertEqual(completions, [.mock(approve: true)])
        XCTAssertTrue(auth.opened.isEmpty, "a demo never opens a sign-in page")
    }

    func testLiveTapOpensTheProvidersPageAndCompletesWithItsAnswer() async throws {
        let connect = try liveConnect()
        let client = try makeClient(connect: connect)
        let auth = ScriptedAuthenticator(.returnQuery("status=success&connected_account_id=ca_1&attempt=\(connect.attemptId.uuidString)"))
        let outcome = await CloudAccess.open(offer(.connect), client: client, authenticator: auth)
        XCTAssertEqual(outcome, .ready)
        XCTAssertEqual(auth.opened.map { $0.url.absoluteString }, ["https://connect.example.com/link/abc"])
        XCTAssertEqual(auth.opened.map { $0.scheme }, ["doddy-dev"])
        let completions = await client.completions
        XCTAssertEqual(completions, [.callback(status: "success", connectedAccountId: "ca_1")])
    }

    func testClosingTheSignInPageChangesNothingAndSwitchesNothingOn() async throws {
        let client = try makeClient(connect: try liveConnect())
        await client.setComplete(try edited(ToolkitResult.self, "toolkit-result-connected") { object in
            var receipt = object["receipt"] as! [String: Any]
            receipt["status"] = "canceled"
            receipt["summary"] = "Connecting was canceled. Nothing was connected."
            object["receipt"] = receipt
            var toolkit = object["toolkit"] as! [String: Any]
            toolkit["status"] = "disconnected"
            object["toolkit"] = toolkit
        })
        let outcome = await CloudAccess.open(offer(.connect), client: client, authenticator: ScriptedAuthenticator(.fail(.canceled)))
        XCTAssertEqual(outcome, .canceled)
        let calls = await client.calls
        XCTAssertEqual(calls, ["connect:gmail", "complete:gmail"], "the attempt is closed on the server, no switch")
        let completions = await client.completions
        XCTAssertEqual(completions, [.canceled])
    }

    func testAReturnForAnotherAttemptIsTreatedAsCanceled() async throws {
        let client = try makeClient(connect: try liveConnect())
        let auth = ScriptedAuthenticator(.returnQuery("status=success&connected_account_id=ca_1&attempt=\(UUID().uuidString)"))
        _ = await CloudAccess.open(offer(.connect), client: client, authenticator: auth)
        let completions = await client.completions
        XCTAssertEqual(completions, [.canceled])
    }

    func testAConnectionThatDidntSucceedIsAFailureInTheServersWords() async throws {
        let client = try makeClient()
        await client.setComplete(try edited(ToolkitResult.self, "toolkit-result-too-broad"))
        let outcome = await CloudAccess.open(offer(.connect), client: client, authenticator: ScriptedAuthenticator(.fail(.failed)))
        guard case .failed(let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertFalse(message.isEmpty)
        let calls = await client.calls
        XCTAssertFalse(calls.contains { $0.hasPrefix("switch") }, "nothing is switched on for a blocked connection")
    }

    func testTheSwitchMustBeConfirmedOnByTheServer() async throws {
        let client = try makeClient()
        await client.setSwitchResult(try edited(ToolkitResult.self, "toolkit-result-connected"))
        let outcome = await CloudAccess.open(offer(.turnOn), client: client, authenticator: ScriptedAuthenticator(.fail(.failed)))
        XCTAssertEqual(outcome, .failed("Gmail connected. Its tools are off until you switch them on."))
    }

    func testTurnOnNeverSignsIn() async throws {
        let client = try makeClient()
        let outcome = await CloudAccess.open(offer(.turnOn), client: client, authenticator: ScriptedAuthenticator(.fail(.failed)))
        XCTAssertEqual(outcome, .ready)
        let calls = await client.calls
        XCTAssertEqual(calls, ["switch:check_email:true"])
    }

    func testAServerErrorIsShownAsIs() async throws {
        let client = try makeClient()
        await client.failConnect(.transport("URLError"))
        let outcome = await CloudAccess.open(offer(.reconnect), client: client, authenticator: ScriptedAuthenticator(.fail(.failed)))
        XCTAssertEqual(outcome, .failed(OnlineAccountsError.transport("URLError").userMessage))
    }
}
