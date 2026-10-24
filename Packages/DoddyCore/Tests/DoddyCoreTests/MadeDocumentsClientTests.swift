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

private final class OneReplyTransport: HTTPTransport, @unchecked Sendable {
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

/// The Files sheet's list of what Doddy made (ADR-607), read from the server's own fixtures.
final class MadeDocumentsClientTests: XCTestCase {
    private let server = URL(string: "https://doddy.example.com")!

    private func client(_ transport: OneReplyTransport, token: String? = "ds1.a.b") -> BackendMadeDocumentsClient {
        BackendMadeDocumentsClient(baseURL: server, sessionToken: { token }, transport: transport)!
    }

    private func document(id: String = "1EXCE-KDiKUmQQv5JB97R7js", status: MadeDocument.Status = .ready) -> MadeDocument {
        MadeDocument(id: id, name: "Notes.md", kind: .text, status: status,
                     createdAt: Date(timeIntervalSince1970: 0), deleteAfter: Date(timeIntervalSince1970: 7 * 86_400), sizeBytes: 31)
    }

    func testTheListIsReadWithThePhonesSessionFromTheWebRoute() async throws {
        let transport = OneReplyTransport(body: try fixture("documents-ready"))
        let list = try await client(transport).documents()
        XCTAssertEqual(list.keptDays, 7)
        XCTAssertFalse(list.documents.isEmpty)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.absoluteString, "https://doddy.example.com/v1/web/documents")
        XCTAssertEqual(request.headers["authorization"], "Bearer ds1.a.b")
    }

    func testEachStatusIsKeptAsTheServerSaidIt() async throws {
        let interrupted = try await client(OneReplyTransport(body: try fixture("documents-interrupted"))).documents()
        XCTAssertTrue(interrupted.documents.contains { $0.status == .interrupted && !$0.canOpen && $0.sizeBytes == nil })
        let working = try await client(OneReplyTransport(body: try fixture("documents-working"))).documents()
        XCTAssertTrue(working.documents.contains { $0.status == .working && !$0.canOpen })
        let ready = try await client(OneReplyTransport(body: try fixture("documents-ready"))).documents()
        XCTAssertTrue(ready.documents.contains { $0.status == .ready && $0.canOpen })
    }

    func testAnEmptyListIsEmptyNotAnError() async throws {
        let list = try await client(OneReplyTransport(body: try fixture("documents-empty"))).documents()
        XCTAssertEqual(list.documents, [])
        XCTAssertEqual(list.keptDays, 7)
    }

    func testAnUnknownKindOrBadIDIsUnreadableRatherThanGuessed() async {
        let badKind = Data(#"{"documents":[{"id":"1EXCE-KDiKUmQQv5JB97R7js","name":"a","kind":"movie","status":"ready","createdAt":"2026-10-22T10:01:00.000Z","deleteAfter":"2026-10-29T10:01:00.000Z","sizeBytes":1}],"keptDays":7}"#.utf8)
        await assertThrows(.unreadable) { _ = try await self.client(OneReplyTransport(body: badKind)).documents() }
        let badID = Data(#"{"documents":[{"id":"../../etc","name":"a","kind":"text","status":"ready","createdAt":"2026-10-22T10:01:00.000Z","deleteAfter":"2026-10-29T10:01:00.000Z","sizeBytes":1}],"keptDays":7}"#.utf8)
        await assertThrows(.unreadable) { _ = try await self.client(OneReplyTransport(body: badID)).documents() }
    }

    func testNoSessionMeansNotConfiguredAndNothingIsSent() async {
        let transport = OneReplyTransport(body: Data())
        await assertThrows(.notConfigured) { _ = try await self.client(transport, token: nil).documents() }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testSignedOutAndOfflineAreTold() async throws {
        await assertThrows(.unauthenticated) {
            _ = try await self.client(OneReplyTransport(status: 401, body: try fixture("error-signed-out"))).documents()
        }
        await assertThrows(.transport) { _ = try await self.client(OneReplyTransport(fails: true)).documents() }
    }

    func testAFileIsFetchedOnlyByItsIDAndReturnsTheBytes() async throws {
        let bytes = Data("# Barcelona".utf8)
        let transport = OneReplyTransport(body: bytes)
        let data = try await client(transport).file(of: document())
        XCTAssertEqual(data, bytes)
        XCTAssertEqual(transport.requests.first?.url.absoluteString, "https://doddy.example.com/v1/web/documents/1EXCE-KDiKUmQQv5JB97R7js/file")
    }

    func testAFileNoLongerKeptIsNotFound() async {
        let body = Data(#"{"error":{"code":"not_found","message":"Documents are kept for a week.","correlationId":"c1"}}"#.utf8)
        await assertThrows(.notFound) { _ = try await self.client(OneReplyTransport(status: 404, body: body)).file(of: self.document()) }
    }

    func testAnIDThatIsNotTheServersShapeIsNeverPutInAPath() async {
        let transport = OneReplyTransport(body: Data("x".utf8))
        await assertThrows(.notFound) { _ = try await self.client(transport).file(of: self.document(id: "../sessions")) }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testSafeFileNames() {
        XCTAssertEqual(MadeDocument.safeFileName("Trip/plan:v2.pdf"), "Trip_plan_v2.pdf")
        XCTAssertEqual(MadeDocument.safeFileName("..hidden.md"), "hidden.md")
        XCTAssertEqual(MadeDocument.safeFileName("   "), "Document")
        XCTAssertEqual(MadeDocument.safeFileName("a\nb.txt"), "a_b.txt")
        let long = String(repeating: "x", count: 300) + ".pptx"
        let safe = MadeDocument.safeFileName(long)
        XCTAssertEqual(safe.count, 120)
        XCTAssertTrue(safe.hasSuffix(".pptx"))
    }

    private func assertThrows(_ expected: WebLinkError, _ body: @escaping () async throws -> Void, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("expected \(expected)", line: line)
        } catch let error as WebLinkError {
            XCTAssertEqual(error, expected, line: line)
        } catch {
            XCTFail("unexpected \(error)", line: line)
        }
    }
}
