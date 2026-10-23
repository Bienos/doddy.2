import Foundation
import XCTest
@testable import DoddyCore

/// Fixtures written by the backend from its own replies (`npm run fixtures:web`, ADR-600); the web
/// app's tests read the same files.
private func fixture(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("contracts/web/\(name).json"))
}

private final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    let status: Int
    let body: Data
    let fails: Bool

    init(status: Int = 200, body: Data = Data(), fails: Bool = false) {
        self.status = status
        self.body = body
        self.fails = fails
    }

    var requests: [HTTPRequest] { lock.withLock { recorded } }

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        lock.withLock { recorded.append(request) }
        if fails { throw URLError(.notConnectedToInternet) }
        return (status, body)
    }
}

final class WebLinkClientTests: XCTestCase {
    private let server = URL(string: "https://doddy.example.com")!

    private func client(_ transport: ScriptedTransport, token: String? = "ds1.a.b") -> BackendWebLinkClient {
        BackendWebLinkClient(baseURL: server, sessionToken: { token }, transport: transport)!
    }

    func testNewCodeAsksWithThePhonesSessionAndReadsTheServersReply() async throws {
        let transport = ScriptedTransport(body: try fixture("link-code"))
        let code = try await client(transport).newCode()
        XCTAssertEqual(code.code.count, 9)
        XCTAssertTrue(BackendWebLinkClient.isCode(code.code))
        XCTAssertEqual(code.expiresAt, ISO8601DateFormatter().date(from: "2026-10-22T10:05:00Z"))
        XCTAssertEqual(code.webOrigin.absoluteString, "https://app.doddy.test")
        XCTAssertEqual(code.displayAddress, "app.doddy.test", "the phone shows the address without https://")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.absoluteString, "https://doddy.example.com/v1/web/link-codes")
        XCTAssertEqual(request.headers["authorization"], "Bearer ds1.a.b")
        XCTAssertEqual(request.headers["content-type"], "application/json")
    }

    func testTheCodeCountsDownAndNeverBelowZero() throws {
        let code = WebLinkCode(code: "ABCD-EFGH", expiresAt: Date(timeIntervalSince1970: 300), webOrigin: URL(string: "http://127.0.0.1:5173")!)
        XCTAssertEqual(code.secondsLeft(at: Date(timeIntervalSince1970: 0)), 300)
        XCTAssertEqual(code.secondsLeft(at: Date(timeIntervalSince1970: 299.5)), 0)
        XCTAssertEqual(code.secondsLeft(at: Date(timeIntervalSince1970: 400)), 0)
        XCTAssertEqual(code.displayAddress, "http://127.0.0.1:5173", "development addresses keep their scheme")
    }

    func testAnOddCodeOrAddressIsRefusedNotShown() async {
        for body in [
            #"{"code":"ABCD-EFG0","expiresAt":"2026-10-22T10:05:00.000Z","webOrigin":"https://app.doddy.lol"}"#,
            #"{"code":"ABCD-EFGH","expiresAt":"soon","webOrigin":"https://app.doddy.lol"}"#,
            #"{"code":"ABCD-EFGH","expiresAt":"2026-10-22T10:05:00.000Z","webOrigin":"http://evil.example"}"#,
            #"{"code":"ABCD-EFGH","expiresAt":"2026-10-22T10:05:00.000Z","webOrigin":"https://app.doddy.lol/login?next=x"}"#,
        ] {
            do {
                _ = try await client(ScriptedTransport(body: Data(body.utf8))).newCode()
                XCTFail("accepted \(body)")
            } catch {
                XCTAssertEqual(error, .unreadable, body)
            }
        }
    }

    func testBrowsersAreReadFromTheServersList() async throws {
        let transport = ScriptedTransport(body: try fixture("sessions-phone"))
        let browsers = try await client(transport).browsers()
        XCTAssertEqual(browsers.count, 1)
        XCTAssertEqual(browsers.first?.browser, .chrome)
        XCTAssertEqual(browsers.first?.system, .macos)
        XCTAssertEqual(transport.requests.first?.method, "GET")
        XCTAssertEqual(transport.requests.first?.url.path, "/v1/web/sessions")
        XCTAssertNil(transport.requests.first?.body)
    }

    func testANewerServersBrowserNamesFallBackToOther() async throws {
        let body = #"{"sessions":[{"id":"9b2f6a1e-4c3d-4e5f-8a7b-1c2d3e4f5a6b","browser":"arc","os":"visionos","createdAt":"2026-10-22T10:00:00.000Z","lastSeenAt":"2026-10-22T10:00:00.000Z","expiresAt":"2026-11-05T10:00:00.000Z","current":false}]}"#
        let browsers = try await client(ScriptedTransport(body: Data(body.utf8))).browsers()
        XCTAssertEqual(browsers.first?.browser, .other)
        XCTAssertEqual(browsers.first?.system, .other)
    }

    func testSigningABrowserOutSendsItsIdLowercased() async throws {
        let transport = ScriptedTransport(body: Data(#"{"signedOut":true}"#.utf8))
        let id = UUID(uuidString: "9B2F6A1E-4C3D-4E5F-8A7B-1C2D3E4F5A6B")!
        try await client(transport).signOut(browser: id)
        XCTAssertEqual(transport.requests.first?.method, "DELETE")
        XCTAssertEqual(transport.requests.first?.url.path, "/v1/web/sessions/9b2f6a1e-4c3d-4e5f-8a7b-1c2d3e4f5a6b")
    }

    func testErrorsAreTyped() async {
        func error(_ transport: ScriptedTransport, token: String? = "ds1.a.b") async -> WebLinkError? {
            do { _ = try await client(transport, token: token).newCode(); return nil } catch { return error }
        }
        let signedOut = try! fixture("error-signed-out")
        let noToken = await error(ScriptedTransport(), token: nil)
        XCTAssertEqual(noToken, .notConfigured)
        let unauthenticated = await error(ScriptedTransport(status: 401, body: signedOut))
        XCTAssertEqual(unauthenticated, .unauthenticated)
        let limited = await error(ScriptedTransport(status: 429, body: Data(#"{"error":{"code":"rate_limited","message":"Too many","correlationId":"c","retryAfterSeconds":600}}"#.utf8)))
        XCTAssertEqual(limited, .rateLimited(retryAfterSeconds: 600))
        let gone = await error(ScriptedTransport(status: 404, body: Data()))
        XCTAssertEqual(gone, .notFound)
        let offline = await error(ScriptedTransport(fails: true))
        XCTAssertEqual(offline, .transport)
        let html = await error(ScriptedTransport(status: 502, body: Data("<html>".utf8)))
        XCTAssertEqual(html, .unreadable)
        let server = await error(ScriptedTransport(status: 500, body: Data(#"{"error":{"code":"internal","message":"Something went wrong.","correlationId":"c"}}"#.utf8)))
        XCTAssertEqual(server, .server(message: "Something went wrong."))
    }

    func testOnlyHttpsOrThisDevicesLoopbackServers() {
        XCTAssertNil(BackendWebLinkClient(baseURL: URL(string: "http://doddy.example.com")!, sessionToken: { "t" }, transport: ScriptedTransport()))
        XCTAssertNotNil(BackendWebLinkClient(baseURL: server, sessionToken: { "t" }, transport: ScriptedTransport()))
    }

    func testTheTokenGoesOnlyToTheServerThatIssuedIt() async {
        let elsewhere = BoundSessionToken(token: "ds1.a.b", issuedBy: URL(string: "https://other.example.com")!)!
        let transport = ScriptedTransport(body: Data(#"{"signedOut":true}"#.utf8))
        let client = BackendWebLinkClient(baseURL: server, boundToken: { elsewhere }, transport: transport)!
        do {
            try await client.signOut(browser: UUID())
            XCTFail("sent a token to the wrong server")
        } catch {
            XCTAssertEqual(error, .notConfigured)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
