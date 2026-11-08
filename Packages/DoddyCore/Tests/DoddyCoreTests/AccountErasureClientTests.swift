import Foundation
import XCTest
@testable import DoddyCore

/// ADR-674: deleting the account on Doddy's server, and what the app may say about it.
private final class OneReplyTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    let status: Int
    let body: Data
    let fails: Bool

    init(status: Int = 200, body: String = "", fails: Bool = false) {
        self.status = status
        self.body = Data(body.utf8)
        self.fails = fails
    }

    var requests: [HTTPRequest] { lock.withLock { recorded } }

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        lock.withLock { recorded.append(request) }
        if fails { throw URLError(.networkConnectionLost) }
        return (status, body)
    }
}

private func receipt(complete: Bool = true, remaining: Int = 0, removed: [String] = ["gmail"], pending: [String] = []) -> String {
    let list = { (items: [String]) in "[" + items.map { "\"\($0)\"" }.joined(separator: ",") + "]" }
    return """
    {"complete":\(complete),"remaining":\(remaining),"onlineAccounts":{"removed":\(list(removed)),"pending":\(list(pending))},
     "deleted":{"connections":1,"memory_notes":3,"users":1},"kept":["…"],"erasedAt":"2026-11-01T10:00:00.000Z"}
    """
}

final class AccountErasureClientTests: XCTestCase {
    private let server = URL(string: "https://doddy.example.com")!

    private func erase(_ transport: OneReplyTransport, token: String? = "ds1.a.b") async -> Result<AccountErasureReceipt, AccountErasureError> {
        let client = BackendAccountClient(baseURL: server, sessionToken: { token }, transport: transport)!
        do { return .success(try await client.eraseAccount()) } catch { return .failure(error) }
    }

    func testSendsOneDeleteWithTheSessionAndNoBody() async throws {
        let transport = OneReplyTransport(body: receipt())
        let result = await erase(transport)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(request.method, "DELETE")
        XCTAssertEqual(request.url.absoluteString, "https://doddy.example.com/v1/account")
        XCTAssertEqual(request.headers["authorization"], "Bearer ds1.a.b")
        XCTAssertNil(request.body)
        XCTAssertEqual(try result.get().deleted["memory_notes"], 3)
        XCTAssertEqual(AccountErasureOutcome.from(result), .complete)
    }

    func testAPendingOnlineAccountIsNeverReportedAsDone() async {
        let result = await erase(OneReplyTransport(body: receipt(complete: false, removed: [], pending: ["gmail"])))
        XCTAssertEqual(AccountErasureOutcome.from(result), .onlineAccountsPending(["gmail"]))
        XCTAssertTrue(AccountErasureOutcome.from(result).mayDeleteVoiceAccount, "the rows are gone; the server keeps trying the removal")
    }

    func testRowsLeftOrAnUnreadableReplyIsAFailure() async {
        let left = await erase(OneReplyTransport(body: receipt(complete: false, remaining: 2)))
        XCTAssertEqual(AccountErasureOutcome.from(left), .failed)
        let garbled = await erase(OneReplyTransport(body: "{\"ok\":true}"))
        XCTAssertEqual(garbled, .failure(.unreadable))
        XCTAssertEqual(AccountErasureOutcome.from(garbled), .failed)
        XCTAssertFalse(AccountErasureOutcome.failed.mayDeleteVoiceAccount, "a failed deletion stops before the voice account, so it can be tried again")
    }

    func testNoAnswerIsAFailureNotADeletion() async {
        let result = await erase(OneReplyTransport(fails: true))
        XCTAssertEqual(result, .failure(.transport))
        XCTAssertEqual(AccountErasureOutcome.from(result), .failed)
    }

    func testNoSessionOrAnOlderServer() async {
        let none = await erase(OneReplyTransport(body: receipt()), token: nil)
        XCTAssertEqual(none, .failure(.notConfigured))
        XCTAssertEqual(AccountErasureOutcome.from(none), .nothingThere)
        let old = await erase(OneReplyTransport(status: 404, body: #"{"error":{"code":"not_found","message":"Not found."}}"#))
        XCTAssertEqual(old, .failure(.notAvailable))
        XCTAssertEqual(AccountErasureOutcome.from(old), .notAvailable)
        XCTAssertFalse(AccountErasureOutcome.notAvailable.mayDeleteVoiceAccount,
                       "a server that can't delete yet keeps the voice account, and with it the button to try again")
        XCTAssertTrue(AccountErasureOutcome.nothingThere.mayDeleteVoiceAccount, "nothing on the server: the voice account may go")
        XCTAssertTrue(AccountErasureOutcome.complete.mayDeleteVoiceAccount)
        let expired = await erase(OneReplyTransport(status: 401))
        XCTAssertEqual(expired, .failure(.unauthenticated))
    }

    func testOnlyHTTPSOrLoopback() {
        XCTAssertNil(BackendAccountClient(baseURL: URL(string: "http://doddy.example.com")!, sessionToken: { "t" }, transport: OneReplyTransport()))
    }
}
