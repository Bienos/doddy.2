import Foundation
import XCTest
@testable import DoddyCore

private final class RecordingTransport: HTTPTransport, @unchecked Sendable {
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
        if fails { throw URLError(.notConnectedToInternet) }
        return (status, body)
    }
}

/// Messages on the web (28 Oct 2026): what the iPhone sends, and that "deleted" is said only on the server's word.
final class ThreadSyncTests: XCTestCase {
    private let server = URL(string: "https://doddy.example.com")!
    private let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    func testTheSnapshotIsTheNewestMessagesOldestFirstWithNoPhotoAndNoLink() throws {
        let link = URL(string: "https://doddy.example.com/v1/documents/abcdefghijklmnopqrstuvwx?exp=1&sig=s")!
        let messages = [
            ThreadMessage(id: UUID(), sender: .doddy, text: "Plan bety", createdAt: t0.addingTimeInterval(3), delivery: .sent,
                          basis: .general, document: ThreadDocument(url: link, name: "Plan bety", kind: "deck")),
            ThreadMessage(id: UUID(), sender: .user, text: "Co to?", createdAt: t0.addingTimeInterval(2), delivery: .failed, hasPhoto: true),
            ThreadMessage(id: UUID(), sender: .user, text: "Cześć", createdAt: t0, delivery: .sent),
        ]
        let snapshot = ThreadSync.snapshot(of: messages)
        XCTAssertEqual(snapshot.messages.map(\.text), ["Cześć", "Co to?", "Plan bety"])
        XCTAssertEqual(snapshot.messages[1].hasPhoto, true)
        XCTAssertEqual(snapshot.messages[1].delivery, "failed")
        XCTAssertNil(snapshot.messages[2].delivery, "Doddy's messages have no delivery")
        XCTAssertEqual(snapshot.messages[2].file, .init(name: "Plan bety", kind: "deck"))
        XCTAssertEqual(snapshot.messages[0].createdAt, "2026-10-14T17:46:40.000Z")
        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(json.contains("doddy.example.com"), "a file's link never goes to the web copy")
        XCTAssertFalse(json.contains("\"hasPhoto\":false"))
    }

    func testOnlyTheNewestTwoHundredGoAndLongTextIsCut() {
        let many = (0..<250).map { ThreadMessage(id: UUID(), sender: .user, text: "m\($0)", createdAt: t0.addingTimeInterval(Double($0)), delivery: .sent) }
        let snapshot = ThreadSync.snapshot(of: many)
        XCTAssertEqual(snapshot.messages.count, 200)
        XCTAssertEqual(snapshot.messages.first?.text, "m50")
        let long = ThreadMessage(id: UUID(), sender: .doddy, text: String(repeating: "ą", count: 12_000), createdAt: t0, delivery: .sent, basis: .general)
        XCTAssertEqual(ThreadSync.snapshot(of: [long]).messages[0].text.unicodeScalars.count, ThreadSync.maxText)
    }

    func testSendingPutsTheSnapshotWithTheSessionAndChecksTheCount() async throws {
        let transport = RecordingTransport(body: #"{"stored":true,"count":1}"#)
        let client = try XCTUnwrap(BackendThreadSyncClient(baseURL: server, sessionToken: { "ds1.a.b" }, transport: transport))
        let snapshot = ThreadSync.snapshot(of: [ThreadMessage(id: UUID(), sender: .user, text: "Cześć", createdAt: t0, delivery: .sent)])
        try await client.send(snapshot)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.url.absoluteString, "https://doddy.example.com/v1/web/messages")
        XCTAssertEqual(request.headers["authorization"], "Bearer ds1.a.b")

        let wrongCount = RecordingTransport(body: #"{"stored":true,"count":0}"#)
        let other = try XCTUnwrap(BackendThreadSyncClient(baseURL: server, sessionToken: { "ds1.a.b" }, transport: wrongCount))
        do { try await other.send(snapshot); XCTFail("a count that doesn't match is not called stored") } catch { XCTAssertEqual(error, .unreadable) }
    }

    func testDeleteIsConfirmedOnlyByTheServer() async throws {
        let ok = RecordingTransport(body: #"{"deleted":true}"#)
        try await XCTUnwrap(BackendThreadSyncClient(baseURL: server, sessionToken: { "t" }, transport: ok)).deleteAll()
        XCTAssertEqual(ok.requests.first?.method, "DELETE")

        let offline = RecordingTransport(fails: true)
        do {
            try await XCTUnwrap(BackendThreadSyncClient(baseURL: server, sessionToken: { "t" }, transport: offline)).deleteAll()
            XCTFail("offline is not deleted")
        } catch let error as WebLinkError {
            XCTAssertEqual(error, .transport)
        }
        let noSession = RecordingTransport()
        do {
            try await XCTUnwrap(BackendThreadSyncClient(baseURL: server, sessionToken: { nil }, transport: noSession)).deleteAll()
            XCTFail("no session is not deleted")
        } catch let error as WebLinkError {
            XCTAssertEqual(error, .notConfigured)
            XCTAssertTrue(noSession.requests.isEmpty)
        }
    }

    func testOnlyHttpsServers() {
        XCTAssertNil(BackendThreadSyncClient(baseURL: URL(string: "http://doddy.example.com")!, sessionToken: { "t" }, transport: RecordingTransport()))
    }
}
