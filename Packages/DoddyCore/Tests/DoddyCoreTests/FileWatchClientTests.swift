import XCTest

@testable import DoddyCore

final class FileWatchClientTests: XCTestCase {
    private final class Recording: ServerTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var sent: [ServerRequest] = []
        let status: Int
        init(status: Int) { self.status = status }
        var requests: [ServerRequest] { lock.withLock { sent } }
        func send(_ request: ServerRequest) async throws -> ServerResponse {
            lock.withLock { sent.append(request) }
            return ServerResponse(status: status, body: Data(#"{"id":"x"}"#.utf8))
        }
    }

    private final class Credentials: ServerCredentialStore, @unchecked Sendable {
        func load() throws -> String? { "token" }
        func save(_ token: String) throws {}
        func delete() throws {}
    }

    private let link = URL(string: "https://doddy.example/v1/documents/aaaaaaaaaaaaaaaaaaaaaaaa?exp=1900000000&sig=abc")!

    func testTheLinkAndLanguageAreSentOnTheDeviceSessionAndWatchingIsReported() async throws {
        let transport = Recording(status: 201)
        let outcome = try await DoddyServerClient(transport: transport, credentials: Credentials()).watchFile(link: link, language: "pl")
        XCTAssertEqual(outcome, .watching)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/v1/file-watches")
        XCTAssertEqual(request.bearerToken, "token")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: String])
        XCTAssertEqual(json, ["url": link.absoluteString, "language": "pl"])
    }

    func testAnyOtherLanguageIsEnglish() async throws {
        let transport = Recording(status: 201)
        _ = try await DoddyServerClient(transport: transport, credentials: Credentials()).watchFile(link: link, language: "de")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(transport.requests.first?.body)) as? [String: String])
        XCTAssertEqual(json["language"], "en")
    }

    func testEveryAnswerIsNamedAndNoneIsCalledWatchingExceptA201() async throws {
        for (status, expected) in [(503, FileWatchOutcome.notAvailable), (400, .refused), (409, .refused), (500, .unknown(status: 500)), (200, .unknown(status: 200))] {
            let outcome = try await DoddyServerClient(transport: Recording(status: status), credentials: Credentials()).watchFile(link: link, language: "en")
            XCTAssertEqual(outcome, expected, "status \(status)")
        }
    }
}
