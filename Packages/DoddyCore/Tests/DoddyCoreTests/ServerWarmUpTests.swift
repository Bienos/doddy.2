import DoddyCore
import Foundation
import XCTest

private actor PingRecorder: HTTPTransport {
    private(set) var requests: [HTTPRequest] = []
    let fails: Bool
    init(fails: Bool = false) { self.fails = fails }
    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        requests.append(request)
        if fails { throw URLError(.timedOut) }
        return (200, Data("{\"ok\":true}".utf8))
    }
}

/// ADR-670: one health ping wakes the sleeping server before the first real request.
final class ServerWarmUpTests: XCTestCase {
    private let server = URL(string: "https://doddy.example")!
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testPingsHealthWithoutATokenAndAtMostOnceInFiveMinutes() async {
        let warmUp = ServerWarmUp()
        let transport = PingRecorder()
        let first = await warmUp.wake(server: server, transport: transport, now: start)
        let soon = await warmUp.wake(server: server, transport: transport, now: start.addingTimeInterval(60))
        let later = await warmUp.wake(server: server, transport: transport, now: start.addingTimeInterval(ServerWarmUp.minimumInterval + 1))
        XCTAssertTrue(first)
        XCTAssertFalse(soon)
        XCTAssertTrue(later)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.first?.method, "GET")
        XCTAssertEqual(requests.first?.url.absoluteString, "https://doddy.example/v1/health")
        XCTAssertEqual(requests.first?.headers, [:])
        XCTAssertNil(requests.first?.body)
    }

    func testAFailedPingIsIgnored() async {
        let warmUp = ServerWarmUp()
        let sent = await warmUp.wake(server: server, transport: PingRecorder(fails: true), now: start)
        XCTAssertTrue(sent)
    }

    func testOnlyHTTPSServers() async {
        let warmUp = ServerWarmUp()
        let transport = PingRecorder()
        let sent = await warmUp.wake(server: URL(string: "http://doddy.example")!, transport: transport, now: start)
        XCTAssertFalse(sent)
        let count = await transport.requests.count
        XCTAssertEqual(count, 0)
    }
}
