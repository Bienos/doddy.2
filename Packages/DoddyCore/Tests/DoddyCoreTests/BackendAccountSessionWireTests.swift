import Foundation
import XCTest
@testable import DoddyCore

/// The two requests of the backend's account session, and what each answer proves (decision
/// 2026-11-12-one-token-per-server; `backend/src/accountSession.ts`, `docs/decisions/2026-11-14-backend-account-session.md`):
/// the exchange (`POST /v1/session/account`) and the sign-out (`DELETE /v1/web/devices/:id`). No answer is read as more
/// than it says: "ended" is only ever the server's own 200 saying `revoked: true`, and anything that is not an answer is
/// `.unavailable`, which no caller treats as success (DOD-08).
///
/// Platforms: iPhone. The Watch and Mac apps are paused.

private final class OneAnswer: HTTPTransport, @unchecked Sendable {
    struct Offline: Error {}
    private let lock = NSLock()
    private var kept: [HTTPRequest] = []
    private let answer: (status: Int, body: String)?
    init(_ status: Int, _ body: String = "{}") { answer = (status, body) }
    init(offline: Bool) { answer = nil }
    var requests: [HTTPRequest] { lock.withLock { kept } }
    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        lock.withLock { kept.append(request) }
        guard let answer else { throw Offline() }
        return (answer.status, Data(answer.body.utf8))
    }
}

final class BackendAccountSessionWireTests: XCTestCase {
    private let row = "00000000-0000-4000-8000-000000000001"
    private var token: String { fakeBackendToken(sub: "account-1", dev: row, acc: true) }
    private var grant: String {
        #"{"token":"\#(token)","expiresAt":"2026-12-14T10:00:00.000Z","access":"full","deviceListId":"\#(row)"}"#
    }
    private func exchange(_ transport: OneAnswer, deviceID: String = backendTestDeviceID) async -> BackendAccountSessionWire.Exchange {
        await BackendAccountSessionWire.exchange(
            server: backendTestServer, accountID: "account-1", accountToken: "supabase-1-not-real", deviceID: deviceID, transport: transport)
    }

    // MARK: The exchange

    func testTheExchangeSendsTheAccountTokenInTheHeaderAndTheDeviceIdAsTheWholeBody() async throws {
        let transport = OneAnswer(200, grant)
        _ = await exchange(transport, deviceID: backendTestDeviceID.uppercased())
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.absoluteString, "https://backend.example.com/v1/session/account")
        XCTAssertEqual(request.headers["authorization"], "Bearer supabase-1-not-real")
        XCTAssertEqual(request.headers["content-type"], "application/json")
        XCTAssertEqual(String(data: try XCTUnwrap(request.body), encoding: .utf8), #"{"deviceId":"\#(backendTestDeviceID)"}"#, "lowercase, nothing else")
    }

    func testAnAnswerThatIsAnAccountSessionForThisAccountIsMinted() async throws {
        let answer = await exchange(OneAnswer(200, grant))
        let expected = BackendSessionGrant(token: token, expiresAt: Date(timeIntervalSince1970: 1_797_242_400), deviceListID: row)
        XCTAssertEqual(answer, .minted(expected), "the expiry is the server's own, read from `expiresAt`")
        // An expiry without fractional seconds is read too.
        let plain = grant.replacingOccurrences(of: "10:00:00.000Z", with: "10:00:00Z")
        let again = await exchange(OneAnswer(200, plain))
        XCTAssertEqual(again, .minted(expected))
    }

    func testEachStatusIsReadForWhatItIs() async {
        let cases: [(Int, String, BackendAccountSessionWire.Exchange)] = [
            (401, #"{"error":{"code":"unauthenticated"}}"#, .accountRefused),
            (429, #"{"error":{"code":"rate_limited"}}"#, .rateLimited),
            (429, #"{"error":{"code":"quota_exceeded"}}"#, .rateLimited),
            (404, #"{"error":{"code":"not_found"}}"#, .unavailable),
            (503, #"{"error":{"code":"not_configured"}}"#, .unavailable),
            (502, "{}", .unavailable), (500, "{}", .unavailable), (400, "{}", .unavailable),
            (200, "not json", .unavailable), (200, "{}", .unavailable),
        ]
        for (status, body, expected) in cases {
            let answer = await exchange(OneAnswer(status, body))
            XCTAssertEqual(answer, expected, "\(status) \(body)")
        }
        let offline = await exchange(OneAnswer(offline: true))
        XCTAssertEqual(offline, .unavailable)
    }

    func testADeviceIdThatIsNotAnIdIsNeverSent() async {
        let transport = OneAnswer(200, grant)
        let answer = await exchange(transport, deviceID: "../v1/account")
        XCTAssertEqual(answer, .unavailable)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testASessionForAnotherAccountOrOfAnotherKindIsNotMinted() async {
        let other = #"{"token":"\#(fakeBackendToken(sub: "account-2", dev: row, acc: true))","expiresAt":"2026-12-14T10:00:00.000Z","access":"full","deviceListId":"\#(row)"}"#
        let device = #"{"token":"\#(fakeBackendToken(sub: "account-1", dev: row, acc: false))","expiresAt":"2026-12-14T10:00:00.000Z","access":"full","deviceListId":"\#(row)"}"#
        let upper = #"{"token":"\#(fakeBackendToken(sub: "ACCOUNT-1", dev: row, acc: true))","expiresAt":"2026-12-14T10:00:00.000Z","access":"full","deviceListId":"\#(row)"}"#
        let answers = [await exchange(OneAnswer(200, other)), await exchange(OneAnswer(200, device)), await exchange(OneAnswer(200, upper))]
        XCTAssertEqual(answers[0], .unavailable, "another account's: never kept (cross-user isolation)")
        XCTAssertEqual(answers[1], .unavailable, "a device session is not an account session")
        guard case .minted = answers[2] else { return XCTFail("the same account, written in capitals, is the same account") }
    }

    // MARK: The sign-out

    func testTheSignOutIsADeleteOfTheRowWithTheSessionAsTheBearer() async throws {
        let transport = OneAnswer(200, #"{"revoked":true,"revokedAt":"2026-12-14T10:00:00.000Z"}"#)
        let answer = await BackendAccountSessionWire.signOut(server: backendTestServer, token: token, deviceListID: row.uppercased(), transport: transport)
        XCTAssertEqual(answer, .ended)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "DELETE")
        XCTAssertEqual(request.url.absoluteString, "https://backend.example.com/v1/web/devices/\(row)")
        XCTAssertEqual(request.headers["authorization"], "Bearer \(token)")
        XCTAssertNil(request.body)
    }

    func testOnlyTheServersOwnRevokedTrueCountsAsEnded() async {
        let cases: [(Int, String, BackendAccountSessionWire.SignOut)] = [
            (200, #"{"revoked":true,"revokedAt":"2026-12-14T10:00:00.000Z"}"#, .ended),
            (200, #"{"revoked":false}"#, .unavailable),
            (200, "{}", .unavailable), (200, "not json", .unavailable), (204, "", .unavailable),
            (401, #"{"error":{"code":"unauthenticated"}}"#, .alreadyGone),
            (404, #"{"error":{"code":"not_found"}}"#, .unavailable),
            (429, "{}", .unavailable), (500, "{}", .unavailable), (502, "{}", .unavailable), (503, "{}", .unavailable),
        ]
        for (status, body, expected) in cases {
            let answer = await BackendAccountSessionWire.signOut(server: backendTestServer, token: token, deviceListID: row, transport: OneAnswer(status, body))
            XCTAssertEqual(answer, expected, "\(status) \(body)")
        }
        let offline = await BackendAccountSessionWire.signOut(server: backendTestServer, token: token, deviceListID: row, transport: OneAnswer(offline: true))
        XCTAssertEqual(offline, .unavailable)
    }

    func testARowIdThatIsNotAnIdIsNeverPutInAPath() async {
        let transport = OneAnswer(200, #"{"revoked":true}"#)
        let answer = await BackendAccountSessionWire.signOut(server: backendTestServer, token: token, deviceListID: "../../v1/account", transport: transport)
        XCTAssertEqual(answer, .unavailable)
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
