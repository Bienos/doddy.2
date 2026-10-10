import Foundation
import XCTest
@testable import DoddyCore

/// Shared fixtures written by the backend (`npm run fixtures`); the TypeScript tests validate the same files.
private func fixture(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("contracts/online-accounts/\(name).json"))
}

private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    try JSONDecoder().decode(T.self, from: fixture(name))
}

final class OnlineAccountsContractTests: XCTestCase {
    func testEveryFixtureDecodes() throws {
        let catalog = try decode(ToolsCatalog.self, "catalog-disconnected")
        XCTAssertEqual(catalog.mode, .mock)
        XCTAssertEqual(catalog.toolkits.map(\.id), ["gmail", "googledrive", "notion", "todoist", "websearch"])
        let accounts = catalog.toolkits.filter(\.hasAccount)
        XCTAssertEqual(accounts.count, 4)
        XCTAssertTrue(accounts.allSatisfy { $0.status == .disconnected }, "nothing is connected by default")
        XCTAssertTrue(catalog.toolkits.flatMap(\.tools).allSatisfy { !$0.enabled }, "every switch starts off")
        let writes = catalog.toolkits.flatMap(\.tools).filter { $0.risk == .write }.map(\.name).sorted()
        XCTAssertEqual(writes, ["add_todoist_task", "draft_email"])
        XCTAssertEqual(Set(writes), CloudToolName.writes, "the app and the server agree on which tools write")
        XCTAssertEqual(Set(catalog.toolkits.flatMap(\.tools).map(\.name)), CloudToolName.all)

        let on = try decode(ToolsCatalog.self, "catalog-gmail-on")
        XCTAssertEqual(on.toolkits[0].status, .connected)
        XCTAssertEqual(on.toolkits[0].tools.first { $0.name == "check_email" }?.enabled, true)
        XCTAssertEqual(on.toolkits[0].tools.first { $0.name == "draft_email" }?.enabled, true)

        let connect = try decode(ConnectResponse.self, "connect-response-mock")
        XCTAssertNil(connect.authorizationUrl, "mock mode never opens a sign-in page")

        let connected = try decode(ToolkitResult.self, "toolkit-result-connected")
        XCTAssertEqual(connected.toolkit.status, .connected)
        XCTAssertEqual(connected.receipt.operation, .connect)
        XCTAssertTrue(connected.toolkit.tools.allSatisfy { !$0.enabled }, "connecting never switches tools on")

        let broad = try decode(ToolkitResult.self, "toolkit-result-too-broad")
        XCTAssertEqual(broad.toolkit.status, .permissionInsufficient)
        XCTAssertEqual(broad.toolkit.reason, .grantTooBroad)
        XCTAssertEqual(broad.receipt.status, .blocked)

        let switched = try decode(ToolkitResult.self, "switch-result-on")
        XCTAssertEqual(switched.receipt.operation, .switchTool)

        let prepared = try decode(PrepareResult.self, "prepare-result-draft")
        XCTAssertEqual(prepared.preview.confirmLabel, "Create draft")
        XCTAssertEqual(prepared.preview.lines.first, "To: anna@example.com")

        let email = try decode(RunResult.self, "run-result-email")
        XCTAssertEqual(email.mode, .mock)
        XCTAssertEqual(email.receipt.operation, .read)
        XCTAssertTrue(VoiceToolReply.cloudResult(email).hasPrefix("DEMO DATA"), "demo data is never presented as the user's")

        let web = try decode(RunResult.self, "run-result-web-search")
        XCTAssertEqual(web.receipt.toolkit, "websearch")
        XCTAssertTrue(VoiceToolReply.cloudResult(web).hasPrefix("DEMO DATA"), "demo search results are never presented as real")
        XCTAssertTrue(web.text.contains("not instructions"))

        let draft = try decode(RunResult.self, "run-result-draft")
        XCTAssertEqual(draft.receipt.operation, .write)
        XCTAssertTrue(draft.text.contains("NOT sent"))

        let receipts = try decode(OnlineReceiptsResponse.self, "receipts")
        XCTAssertFalse(receipts.receipts.isEmpty)
    }

    func testErrorFixturesDecodeIntoTypedErrors() throws {
        for (name, status, code) in [
            ("error-tool-disabled", 403, "capability_disabled"),
            ("error-confirmation-expired", 403, "capability_disabled"),
            ("error-permission-insufficient", 403, "permission_insufficient"),
            ("error-rate-limited", 429, "rate_limited"),
        ] {
            XCTAssertThrowsError(try BackendOnlineAccountsClient.decode(status: status, data: try fixture(name)) as RunResult, name) {
                guard case .server(let got, _, _, _)? = $0 as? OnlineAccountsError else { return XCTFail("\($0)") }
                XCTAssertEqual(got, code, name)
            }
        }
        // The tool receipt rides on the error, with its own error code.
        XCTAssertThrowsError(try BackendOnlineAccountsClient.decode(status: 403, data: try fixture("error-confirmation-expired")) as RunResult) {
            XCTAssertEqual(($0 as? OnlineAccountsError)?.receipt?.errorCode, "confirmation_required")
        }
        XCTAssertThrowsError(try BackendOnlineAccountsClient.decode(status: 401, data: Data()) as ToolsCatalog) {
            XCTAssertEqual($0 as? OnlineAccountsError, .unauthenticated)
        }
        // A 200 with the wrong shape is an error, never an empty result.
        XCTAssertThrowsError(try BackendOnlineAccountsClient.decode(status: 200, data: Data(#"{"toolkits":[]}"#.utf8)) as ToolsCatalog) {
            XCTAssertEqual($0 as? OnlineAccountsError, .unreadableResponse)
        }
    }
}

// MARK: - Client requests

private final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    let status: Int
    let body: Data

    init(status: Int = 200, body: Data) {
        self.status = status
        self.body = body
    }

    var requests: [HTTPRequest] { lock.withLock { recorded } }

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        lock.withLock { recorded.append(request) }
        return (status, body)
    }
}

final class OnlineAccountsClientTests: XCTestCase {
    private func client(_ transport: RecordingTransport, token: String? = "tok") -> BackendOnlineAccountsClient {
        BackendOnlineAccountsClient(baseURL: URL(string: "https://doddy.example.com")!, sessionToken: { token }, transport: transport)!
    }

    private func object(_ data: Data?) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: XCTUnwrap(data)) as! [String: Any]
    }

    func testSwitchIsAPutWithOnlyTheToolAndTheState() async throws {
        let transport = RecordingTransport(body: try fixture("switch-result-on"))
        _ = try await client(transport).setSwitch(tool: "check_email", enabled: true)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.url.absoluteString, "https://doddy.example.com/v1/tools/switch")
        XCTAssertEqual(request.headers["authorization"], "Bearer tok")
        XCTAssertEqual(try object(request.body) as NSDictionary, ["tool": "check_email", "enabled": true] as NSDictionary)
    }

    func testRunSendsArgumentsTimeZoneAndALowercaseApproval() async throws {
        let transport = RecordingTransport(body: try fixture("run-result-draft"))
        let approval = UUID(uuidString: "50CBF646-DBEF-4A17-9EFA-C529621DF5BF")!
        let call = CloudToolCall(name: "draft_email", arguments: ["to": .string("anna@example.com"), "subject": .string("Lunch Friday"), "body": .string("Yes, 1pm works.")])
        _ = try await client(transport).run(call, timeZone: "Europe/Warsaw", approvalId: approval)
        let sent = try object(try XCTUnwrap(transport.requests.first).body)
        XCTAssertEqual(Set(sent.keys), ["tool", "arguments", "timeZone", "approvalId"], "no user id, connection id or tool slug is ever sent")
        XCTAssertEqual(sent["approvalId"] as? String, "50cbf646-dbef-4a17-9efa-c529621df5bf")
        XCTAssertEqual(sent["timeZone"] as? String, "Europe/Warsaw")
        XCTAssertEqual((sent["arguments"] as? [String: String])?["subject"], "Lunch Friday")
    }

    func testAReadSendsNoApproval() async throws {
        let transport = RecordingTransport(body: try fixture("run-result-email"))
        _ = try await client(transport).run(CloudToolCall(name: "check_email", arguments: [:]), timeZone: "UTC", approvalId: nil)
        XCTAssertNil(try object(try XCTUnwrap(transport.requests.first).body)["approvalId"])
    }

    func testNothingIsSentWithoutASessionToken() async {
        let transport = RecordingTransport(body: Data())
        do {
            _ = try await client(transport, token: nil).catalog()
            XCTFail("expected notConfigured")
        } catch {
            XCTAssertEqual(error, .notConfigured)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testToolkitRoutesUseTheToolkitInThePath() async throws {
        let transport = RecordingTransport(body: try fixture("toolkit-result-connected"))
        _ = try await client(transport).disconnect(toolkit: "gmail")
        XCTAssertEqual(transport.requests.first?.url.absoluteString, "https://doddy.example.com/v1/tools/gmail/disconnect")
        XCTAssertEqual(transport.requests.first?.method, "POST")
    }
}

// MARK: - Voice

final class CloudToolVoiceTests: XCTestCase {
    func testOnlyKnownToolsAreRoutedAndArgumentsPassThrough() {
        let data = Data(#"{"to":"anna@example.com","subject":"Hi","body":"Hello","cc":["x@y.z"]}"#.utf8)
        guard case .cloudTool(let call) = VoiceToolRequest.parse(name: "draft_email", parametersJSON: data) else { return XCTFail("not routed") }
        XCTAssertTrue(call.isWrite)
        XCTAssertEqual(call.arguments["cc"], .array([.string("x@y.z")]), "the server, not the app, rejects fields it doesn't know")

        guard case .cloudTool(let read) = VoiceToolRequest.parse(name: "check_email", parametersJSON: Data("{}".utf8)) else { return XCTFail("not routed") }
        XCTAssertFalse(read.isWrite)

        XCTAssertEqual(VoiceToolRequest.parse(name: "send_email", parametersJSON: data), .unsupported(name: "send_email"))
        XCTAssertEqual(VoiceToolRequest.parse(name: "GMAIL_SEND_EMAIL", parametersJSON: data), .unsupported(name: "GMAIL_SEND_EMAIL"))
        XCTAssertEqual(
            VoiceToolRequest.parse(name: "check_email", parametersJSON: Data("[1]".utf8)),
            .invalid(name: "check_email", reason: "arguments must be a JSON object"))
    }

    func testRepliesNeverClaimMoreThanIsKnown() throws {
        let disabled = try XCTUnwrap(failure("error-tool-disabled"))
        let off = VoiceToolReply.cloudFailed(disabled, tool: "check_email")
        XCTAssertTrue(off.hasPrefix("failed:") && off.contains("switched off") && off.contains("Settings, Online accounts"))

        let expired = VoiceToolReply.cloudFailed(try XCTUnwrap(failure("error-confirmation-expired")), tool: "draft_email")
        XCTAssertTrue(expired.contains("confirmation expired") && expired.contains("Nothing was done"))

        XCTAssertTrue(VoiceToolReply.cloudFailed(try XCTUnwrap(failure("error-permission-insufficient")), tool: "check_email").contains("needs reconnecting"))

        // A write that may have reached the server is "unknown", not "failed".
        XCTAssertTrue(VoiceToolReply.cloudFailed(.transport("URLError"), tool: "add_todoist_task").hasPrefix("unknown:"))
        XCTAssertTrue(VoiceToolReply.cloudFailed(.unreadableResponse, tool: "draft_email").hasPrefix("unknown:"))
        // A read that didn't arrive changed nothing.
        XCTAssertTrue(VoiceToolReply.cloudFailed(.transport("URLError"), tool: "check_email").hasPrefix("failed:"))
        XCTAssertTrue(VoiceToolReply.cloudFailed(.notConfigured, tool: "check_email").contains("aren't set up"))

        XCTAssertEqual(
            VoiceToolReply.cloudDeclined("add_todoist_task"),
            "declined: the user chose not to do \"Add a task\". Nothing was done.")
    }

    private func failure(_ name: String) throws -> OnlineAccountsError? {
        do {
            _ = try BackendOnlineAccountsClient.decode(status: 403, data: try fixture(name)) as RunResult
            return nil
        } catch {
            return error as? OnlineAccountsError
        }
    }
}

// MARK: - Settings model

private actor FakeOnline: OnlineAccountsClient {
    var catalogView: ToolsCatalog
    var failNextSwitch: OnlineAccountsError?
    private(set) var calls: [String] = []

    init(_ catalog: ToolsCatalog) { catalogView = catalog }

    func failSwitch(with error: OnlineAccountsError) { failNextSwitch = error }

    func catalog() async throws(OnlineAccountsError) -> ToolsCatalog {
        calls.append("catalog")
        return catalogView
    }

    func connect(toolkit: String) async throws(OnlineAccountsError) -> ConnectResponse {
        calls.append("connect:\(toolkit)")
        return try! JSONDecoder().decode(ConnectResponse.self, from: fixture("connect-response-mock"))
    }

    func complete(toolkit: String, _ request: CompleteRequest) async throws(OnlineAccountsError) -> ToolkitResult {
        calls.append("complete:\(toolkit)")
        return try! JSONDecoder().decode(ToolkitResult.self, from: fixture("toolkit-result-connected"))
    }

    func disconnect(toolkit: String) async throws(OnlineAccountsError) -> ToolkitResult {
        calls.append("disconnect:\(toolkit)")
        var result = try! JSONDecoder().decode(ToolkitResult.self, from: fixture("toolkit-result-connected"))
        result = ToolkitResult(toolkit: result.toolkit, receipt: result.receipt)
        return result
    }

    func setSwitch(tool: String, enabled: Bool) async throws(OnlineAccountsError) -> ToolkitResult {
        calls.append("switch:\(tool):\(enabled)")
        if let error = failNextSwitch {
            failNextSwitch = nil
            throw error
        }
        return try! JSONDecoder().decode(ToolkitResult.self, from: fixture("switch-result-on"))
    }

    func prepare(_ call: CloudToolCall) async throws(OnlineAccountsError) -> PrepareResult { throw .notConfigured }
    func run(_ call: CloudToolCall, timeZone: String, approvalId: UUID?) async throws(OnlineAccountsError) -> RunResult { throw .notConfigured }
    func receipts() async throws(OnlineAccountsError) -> [OnlineToolReceipt] { [] }
}

private struct NeverAuthenticator: WebAuthenticator {
    func authenticate(url: URL, callbackScheme: String) async throws(WebAuthenticationError) -> URL { throw .failed }
}

extension ToolkitResult {
    fileprivate init(toolkit: ToolkitView, receipt: OnlineToolReceipt) {
        self = try! JSONDecoder().decode(ToolkitResult.self, from: JSONEncoder().encode(Wrapper(toolkit: toolkit, receipt: receipt)))
    }
    private struct Wrapper: Encodable {
        let toolkit: ToolkitView
        let receipt: OnlineToolReceipt
    }
}

@MainActor
final class OnlineAccountsModelTests: XCTestCase {
    private func model() async throws -> (OnlineAccountsModel, FakeOnline) {
        let catalog = try decode(ToolsCatalog.self, "catalog-disconnected")
        let client = FakeOnline(catalog)
        let model = OnlineAccountsModel(client: client, authenticator: NeverAuthenticator())
        await model.refresh()
        return (model, client)
    }

    func testWithoutAServerNothingIsShownAsConnected() async {
        let model = OnlineAccountsModel(client: nil, authenticator: NeverAuthenticator())
        XCTAssertEqual(model.load, .notConfigured)
        await model.connect("gmail")
        await model.setSwitch("check_email", enabled: true)
        XCTAssertNil(model.catalog)
        XCTAssertFalse(model.isEnabled("check_email"))
    }

    func testDemoConnectWaitsForATapAndNeverOpensASignInPage() async throws {
        let (model, client) = try await model()
        XCTAssertTrue(model.isDemo)
        await model.connect("gmail")
        XCTAssertEqual(model.demoAttempt?.toolkit, "gmail")
        let beforeTap = await client.calls
        XCTAssertFalse(beforeTap.contains { $0.hasPrefix("complete") }, "nothing completes without the user's tap")

        await model.completeDemo(approve: true)
        XCTAssertNil(model.demoAttempt)
        XCTAssertEqual(model.toolkit("gmail")?.status, .connected)
        XCTAssertEqual(model.lastReceipt?.operation, .connect)
        XCTAssertFalse(model.isEnabled("check_email"), "connecting does not switch anything on")
    }

    func testASwitchMovesOnlyWhenTheServerSaysSo() async throws {
        let (model, client) = try await model()
        await client.failSwitch(with: .server(code: "not_connected", message: "Gmail isn't connected.", retryAfterSeconds: nil, receipt: nil))
        await model.setSwitch("check_email", enabled: true)
        XCTAssertFalse(model.isEnabled("check_email"))
        XCTAssertEqual(model.message, "Gmail isn't connected.")

        await model.setSwitch("check_email", enabled: true)
        XCTAssertTrue(model.isEnabled("check_email"))
        XCTAssertNil(model.message)
        XCTAssertTrue(model.switching.isEmpty)
    }

    func testDisconnectAppliesTheServersAnswer() async throws {
        let (model, client) = try await model()
        await model.disconnect("gmail")
        let calls = await client.calls
        XCTAssertTrue(calls.contains("disconnect:gmail"))
        XCTAssertNil(model.busyToolkit)
    }
}

final class WebSearchToolTests: XCTestCase {
    func testWebSearchIsARoutedReadWithoutAnAccount() throws {
        let catalog = try decode(ToolsCatalog.self, "catalog-disconnected")
        let web = try XCTUnwrap(catalog.toolkits.first { $0.id == "websearch" })
        XCTAssertFalse(web.hasAccount)
        XCTAssertEqual(web.status, .connected, "nothing to connect: ready whenever the server has it set up")
        XCTAssertEqual(web.tools.map(\.name), [CloudToolName.webSearch])
        XCTAssertFalse(web.tools[0].enabled, "starts off like every other tool")

        XCTAssertFalse(CloudToolName.isWrite(CloudToolName.webSearch))
        XCTAssertFalse(CloudToolName.needsAccount(CloudToolName.webSearch))
        XCTAssertTrue(CloudToolName.needsAccount(CloudToolName.checkEmail))
        let parsed = VoiceToolRequest.parse(name: "web_search", parametersJSON: Data(#"{"query":"Warsaw weather"}"#.utf8))
        guard case .cloudTool(let call) = parsed else { return XCTFail("expected a cloud tool call, got \(parsed)") }
        XCTAssertEqual(call.name, "web_search")
    }

    func testOlderServersWithoutTheFieldStillDecodeAsAccounts() throws {
        let json = #"{"id":"gmail","title":"Gmail","access":"a","status":"disconnected","reason":null,"connectedAt":null,"remoteCleanup":"none","tools":[]}"#
        let view = try JSONDecoder().decode(ToolkitView.self, from: Data(json.utf8))
        XCTAssertNil(view.needsAccount)
        XCTAssertTrue(view.hasAccount)
    }

    func testWebSearchFailuresSayWhatHappened() {
        let limit = OnlineAccountsError.server(code: "quota_exceeded", message: "m", retryAfterSeconds: nil, receipt: nil)
        XCTAssertTrue(VoiceToolReply.cloudFailed(limit, tool: "web_search").contains("web search limit"))
        XCTAssertTrue(VoiceToolReply.cloudFailed(limit, tool: "check_email").contains("usage limit says to wait"), "account tools keep their wording")
        let off = OnlineAccountsError.server(code: "capability_disabled", message: "m", retryAfterSeconds: nil, receipt: nil)
        XCTAssertTrue(VoiceToolReply.cloudFailed(off, tool: "web_search").contains("\"Search the web\" is switched off"))
        let down = OnlineAccountsError.server(code: "provider_unavailable", message: "m", retryAfterSeconds: nil, receipt: nil)
        XCTAssertEqual(VoiceToolReply.cloudFailed(down, tool: "web_search"), "failed: Web search couldn't be reached. Nothing was changed.")
    }

    func testActivityLogNamesTheLookUpButNotTheSearchWords() throws {
        let request = try XCTUnwrap(ActivityRequest.describe(cloud: "web_search"))
        XCTAssertEqual(request.app, .web)
        XCTAssertEqual(request.title, "Searched the web")
        XCTAssertNil(request.detail)
        XCTAssertTrue(request.isLookup)
        XCTAssertEqual(ActivityApp.web.title, "Web search")
    }
}
