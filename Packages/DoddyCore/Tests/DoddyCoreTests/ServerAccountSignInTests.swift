import Foundation
import XCTest
@testable import DoddyCore

/// Decision 2026-11-08-required-account: with no messaging token, the iPhone signs in with its Doddy
/// account; an anonymous account is made only while the server isn't set up for Doddy accounts.

private final class Recorder: ServerTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [ServerRequest] = []
    var requests: [ServerRequest] { lock.withLock { sent } }
    func send(_ request: ServerRequest) async throws -> ServerResponse {
        lock.withLock { sent.append(request) }
        if request.path == "/v1/accounts" {
            return ServerResponse(status: 201, body: Data(#"{"accountId":"a","deviceToken":"anonymous-token"}"#.utf8))
        }
        return ServerResponse(status: 204)
    }
}

private final class Tokens: ServerCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    func load() throws -> String? { lock.withLock { token } }
    func save(_ token: String) throws { lock.withLock { self.token = token } }
    func delete() throws { lock.withLock { token = nil } }
}

final class ServerAccountSignInTests: XCTestCase {
    func testTheDoddyAccountGivesTheTokenAndNoAnonymousAccountIsMade() async throws {
        let transport = Recorder()
        let tokens = Tokens()
        let client = DoddyServerClient(transport: transport, credentials: tokens, accountSignIn: { "account-token" })
        let token = try await client.ensureAccount()
        XCTAssertEqual(token, "account-token")
        XCTAssertEqual(try tokens.load(), "account-token")
        XCTAssertFalse(transport.requests.contains { $0.path == "/v1/accounts" })
    }

    func testAServerNotSetUpForAccountsStillGetsAnAnonymousAccount() async throws {
        let transport = Recorder()
        let tokens = Tokens()
        let client = DoddyServerClient(transport: transport, credentials: tokens, accountSignIn: { nil })
        let token = try await client.ensureAccount()
        XCTAssertEqual(token, "anonymous-token")
        XCTAssertEqual(transport.requests.map(\.path), ["/v1/accounts"])
    }

    func testAFailedAccountSignInIsAnErrorNotAnAnonymousAccount() async {
        struct SignedOut: Error {}
        let transport = Recorder()
        let client = DoddyServerClient(transport: transport, credentials: Tokens(), accountSignIn: { throw SignedOut() })
        do { _ = try await client.ensureAccount(); XCTFail("signed out, yet a token") } catch {}
        XCTAssertTrue(transport.requests.isEmpty, "no anonymous account behind the person's back")
    }

    func testASavedTokenIsUsedWithoutAskingAgain() async throws {
        let tokens = Tokens()
        try tokens.save("saved-token")
        let asked = Recorder()
        let client = DoddyServerClient(transport: asked, credentials: tokens, accountSignIn: { XCTFail("asked again"); return nil })
        let token = try await client.ensureAccount()
        XCTAssertEqual(token, "saved-token")
    }
}
