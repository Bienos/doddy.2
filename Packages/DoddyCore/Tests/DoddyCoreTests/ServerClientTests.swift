import XCTest
@testable import DoddyCore

/// The client against a scripted transport. The server side of these calls is tested for real
/// in server/test (Postgres + HTTP); here we pin what the app sends and how it reads replies.
final class ServerClientTests: XCTestCase {
    func testAccountIsCreatedOnceAndTokenIsSentAsBearer() async throws {
        let transport = ScriptedTransport([
            ServerResponse(status: 201, body: json(#"{"accountId":"a","deviceToken":"tok"}"#)),
            ServerResponse(status: 200, body: json(#"{"phone":null,"smsEnabled":false,"optedOut":false}"#)),
            ServerResponse(status: 200, body: json(#"{"phone":"+48500100200","smsEnabled":true,"optedOut":false}"#)),
        ])
        let store = MemoryCredentials()
        let client = DoddyServerClient(transport: transport, credentials: store)

        let first = try await client.phoneStatus()
        let second = try await client.phoneStatus()
        XCTAssertEqual(first, .none)
        XCTAssertTrue(second.smsEnabled)
        let sent = await transport.sent
        XCTAssertEqual(sent.map(\.path), ["/v1/accounts", "/v1/phone", "/v1/phone"])
        XCTAssertNil(sent[0].bearerToken)
        XCTAssertEqual(sent[1].bearerToken, "tok")
        XCTAssertEqual(try store.load(), "tok")
    }

    func testUnauthorizedForgetsTheTokenSoANewAccountIsMadeNextTime() async throws {
        let transport = ScriptedTransport([ServerResponse(status: 401)])
        let store = MemoryCredentials(token: "old")
        let client = DoddyServerClient(transport: transport, credentials: store)
        do {
            _ = try await client.phoneStatus()
            XCTFail("expected accountMissing")
        } catch {
            XCTAssertEqual(error as? ServerError, .accountMissing)
        }
        XCTAssertNil(try store.load())
    }

    func testPushTokenIsSentAsLowercaseHex() async throws {
        let transport = ScriptedTransport([ServerResponse(status: 204)])
        let client = DoddyServerClient(transport: transport, credentials: MemoryCredentials(token: "t"))
        try await client.registerPushToken(Data([0x0A, 0xFF, 0x10]), environment: .sandbox)
        let sent = await transport.sent
        let body = try XCTUnwrap(sent.first?.body)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String],
                       ["token": "0aff10", "environment": "sandbox"])
    }

    func testConsentCarriesTheWordingVersionAndWithdrawalDoesNot() async throws {
        let transport = ScriptedTransport([ServerResponse(status: 204), ServerResponse(status: 204)])
        let client = DoddyServerClient(transport: transport, credentials: MemoryCredentials(token: "t"))
        try await client.setSMSConsent(true)
        try await client.setSMSConsent(false)
        let sent = await transport.sent
        let bodies = try sent.map { try JSONSerialization.jsonObject(with: $0.body!) as! NSDictionary }
        XCTAssertEqual(bodies[0], ["consent": true, "textVersion": SMSConsent.textVersion])
        XCTAssertEqual(bodies[1], ["consent": false])
    }

    func testServerErrorsMapToSpecificCases() {
        func map(_ status: Int, _ body: String = "{}") -> ServerError {
            DoddyServerClient.error(from: ServerResponse(status: status, body: json(body)))
        }
        XCTAssertEqual(map(400, #"{"error":"wrong_code"}"#), .wrongCode)
        XCTAssertEqual(map(400, #"{"error":"code_expired"}"#), .codeExpired)
        XCTAssertEqual(map(400, #"{"error":"invalid_request","fields":["phone"]}"#), .invalidRequest(fields: ["phone"]))
        XCTAssertEqual(map(409, #"{"error":"sms_not_enabled"}"#), .notEnabled("sms_not_enabled"))
        XCTAssertEqual(map(404, #"{"error":"no_verified_phone"}"#), .notEnabled("no_verified_phone"))
        XCTAssertEqual(map(503, #"{"error":"push_not_configured"}"#), .notConfigured("push_not_configured"))
        XCTAssertEqual(map(429), .rateLimited)
        XCTAssertEqual(map(502), .providerUnavailable)
        XCTAssertEqual(map(500), .unexpected(status: 500))
    }

    func testTransportFailureIsOffline() async {
        let client = DoddyServerClient(transport: ScriptedTransport([]), credentials: MemoryCredentials(token: "t"))
        do {
            _ = try await client.phoneStatus()
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? ServerError, .offline)
        }
    }

    func testPhoneNormalisation() {
        XCTAssertEqual(PhoneNumberInput.normalize("500 100 200"), "+48500100200")
        XCTAssertEqual(PhoneNumberInput.normalize("+48 500-100-200"), "+48500100200")
        XCTAssertEqual(PhoneNumberInput.normalize("0044 7700 900123"), "+447700900123")
        XCTAssertNil(PhoneNumberInput.normalize("12"))
        XCTAssertNil(PhoneNumberInput.normalize("+48 abc"))
        XCTAssertNil(PhoneNumberInput.normalize("+0123456789"))
    }

    func testUpdateStatusCopyNeverOverclaims() {
        let id = UUID()
        XCTAssertEqual(UpdateStatus(id: id, channel: .push, state: "sent").userFacingText, "Handed to Apple. Check your notifications")
        XCTAssertEqual(UpdateStatus(id: id, channel: .sms, state: "sent").userFacingText, "Handed to Twilio for delivery")
        XCTAssertEqual(UpdateStatus(id: id, channel: .sms, state: "sent", deliveryStatus: "delivered").userFacingText, "Delivered")
        XCTAssertTrue(UpdateStatus(id: id, channel: .push, state: "unknown").userFacingText.contains("won't resend"))
    }

    func testUpdatesAreOnlyAvailableWithAServer() {
        XCTAssertEqual(CapabilityCatalog.s1Updates(serverConfigured: false).status(of: .pushUpdates), .needsSetup("Doddy server not connected"))
        XCTAssertTrue(CapabilityCatalog.s1Updates(serverConfigured: true).isAvailable(.textUpdates))
        XCTAssertTrue(CapabilityCatalog.s1Updates(serverConfigured: true).isAvailable(.voiceInput))
    }
}

private func json(_ s: String) -> Data { Data(s.utf8) }

private actor ScriptedTransport: ServerTransport {
    private var responses: [ServerResponse]
    private(set) var sent: [ServerRequest] = []

    init(_ responses: [ServerResponse]) { self.responses = responses }

    func send(_ request: ServerRequest) async throws -> ServerResponse {
        sent.append(request)
        guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
        return responses.removeFirst()
    }
}

private final class MemoryCredentials: DeviceCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    init(token: String? = nil) { self.token = token }

    func load() throws -> String? { lock.withLock { token } }
    func save(_ token: String) throws { lock.withLock { self.token = token } }
    func delete() throws { lock.withLock { token = nil } }
}
