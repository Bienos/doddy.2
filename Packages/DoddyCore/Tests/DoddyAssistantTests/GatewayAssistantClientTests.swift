import DoddyCore
import Foundation
import XCTest
@testable import DoddyAssistant

/// Scripted transport: returns queued steps in order and records every request.
actor ScriptedTransport: HTTPTransport {
    enum Step {
        case response(Int, String)
        case failure(any Error)
    }

    private var steps: [Step]
    private var requests: [HTTPRequest] = []

    init(_ steps: [Step]) { self.steps = steps }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !steps.isEmpty else { throw TransportError.offline }
        switch steps.removeFirst() {
        case let .response(status, body): return HTTPResponse(status: status, body: Data(body.utf8))
        case let .failure(error): throw error
        }
    }

    func recorded() -> [HTTPRequest] { requests }
}

final class GatewayAssistantClientTests: XCTestCase {
    private let base = URL(string: "https://gateway.example/functions/v1/assistant")!
    private let session = UUID()

    private func client(_ steps: [ScriptedTransport.Step], token: String? = "tok") -> (GatewayAssistantClient, ScriptedTransport, InMemoryDeviceTokenStore) {
        let transport = ScriptedTransport(steps)
        let store = InMemoryDeviceTokenStore(token: token)
        let client = GatewayAssistantClient(
            configuration: GatewayConfiguration(baseURL: base, locale: "pl"),
            transport: transport, tokenStore: store)
        return (client, transport, store)
    }

    private func memory(_ text: String = "Charger is in the kitchen drawer.", source: MemorySource = .explicitText) throws -> MemoryCandidate {
        let record = try MemoryRecord(id: UUID(), rawText: text, source: source, capturedAt: source == .importedLegacyUnknown ? nil : Date(timeIntervalSince1970: 0))
        return MemoryCandidate(record: record, matchedTerms: ["charger"])
    }

    private func okReply(_ text: String = "Hi.", cited: [UUID] = [], flag: Bool = false) -> ScriptedTransport.Step {
        let ids = cited.map { "\"\($0.uuidString)\"" }.joined(separator: ",")
        return .response(200, "{\"text\":\"\(text)\",\"citedMemoryIds\":[\(ids)],\"invalidCitations\":\(flag)}")
    }

    func testSendsBearerTokenAndDocumentedBody() async throws {
        let m = try memory()
        let (client, transport, _) = client([okReply(cited: [m.memoryID])])
        let reply = try await client.respond(AssistantRequest(sessionID: session, userText: "Where is my charger?", groundingMemories: [m]))
        XCTAssertEqual(reply.text, "Hi.")
        XCTAssertEqual(reply.citedMemoryIDs, [m.memoryID])

        let sent = await transport.recorded()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].url.absoluteString, "https://gateway.example/functions/v1/assistant/chat")
        XCTAssertEqual(sent[0].headers["authorization"], "Bearer tok")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent[0].body)) as? [String: Any])
        XCTAssertEqual(json["taskType"] as? String, "recall")
        XCTAssertEqual(json["locale"] as? String, "pl")
        XCTAssertEqual(json["sessionId"] as? String, session.uuidString)
        let memories = try XCTUnwrap(json["memories"] as? [[String: Any]])
        XCTAssertEqual(memories.first?["id"] as? String, m.memoryID.uuidString)
        XCTAssertEqual(memories.first?["currentText"] as? String, "Charger is in the kitchen drawer.")
    }

    func testRegistersOnceWhenNoTokenThenStoresIt() async throws {
        let (client, transport, store) = client(
            [.response(200, "{\"deviceToken\":\"fresh\",\"dailyLimit\":60}"), okReply()], token: nil)
        _ = try await client.respond(AssistantRequest(sessionID: session, userText: "hi"))
        let stored = await store.token()
        XCTAssertEqual(stored, "fresh")
        let sent = await transport.recorded()
        XCTAssertEqual(sent.map(\.url.lastPathComponent), ["register", "chat"])
        XCTAssertEqual(sent[1].headers["authorization"], "Bearer fresh")
    }

    func testRetriesOnceAfter401ByReRegistering() async throws {
        let (client, transport, store) = client([
            .response(401, "{\"error\":\"notAuthorized\"}"),
            .response(200, "{\"deviceToken\":\"new\",\"dailyLimit\":60}"),
            okReply(),
        ])
        _ = try await client.respond(AssistantRequest(sessionID: session, userText: "hi"))
        let stored = await store.token()
        XCTAssertEqual(stored, "new")
        let sent = await transport.recorded()
        XCTAssertEqual(sent.map(\.url.lastPathComponent), ["chat", "register", "chat"])
    }

    func testSecond401IsNotRetriedAgain() async throws {
        let (client, transport, _) = client([
            .response(401, "{\"error\":\"notAuthorized\"}"),
            .response(200, "{\"deviceToken\":\"new\",\"dailyLimit\":60}"),
            .response(401, "{\"error\":\"notAuthorized\"}"),
        ])
        await assertThrows(.notAuthorized) { _ = try await client.respond(AssistantRequest(sessionID: self.session, userText: "hi")) }
        let count = await transport.recorded().count
        XCTAssertEqual(count, 3)
    }

    func testFailureMapping() async throws {
        let cases: [(ScriptedTransport.Step, AssistantError)] = [
            (.response(429, "{\"error\":\"rateLimited\"}"), .rateLimited),
            (.response(502, "{\"error\":\"providerUnavailable\"}"), .providerUnavailable),
            (.response(504, "{\"error\":\"timeout\"}"), .timeout),
            (.response(400, "{\"error\":\"invalidRequest\"}"), .invalidRequest),
            (.response(500, "not json"), .providerUnavailable),
            (.failure(TransportError.offline), .offline),
            (.failure(TransportError.timedOut), .timeout),
            (.failure(CancellationError()), .cancelled),
        ]
        for (step, expected) in cases {
            let (client, _, _) = client([step])
            await assertThrows(expected) { _ = try await client.respond(AssistantRequest(sessionID: self.session, userText: "hi")) }
        }
    }

    func testCitationOfUnsentMemoryIsRejected() async throws {
        let (client, _, _) = client([okReply(cited: [UUID()])])
        await assertThrows(.invalidCitations) { _ = try await client.respond(AssistantRequest(sessionID: self.session, userText: "hi")) }
    }

    func testGatewayInvalidCitationsFlagIsRejected() async throws {
        let m = try memory()
        let (client, _, _) = client([okReply(cited: [m.memoryID], flag: true)])
        await assertThrows(.invalidCitations) {
            _ = try await client.respond(AssistantRequest(sessionID: self.session, userText: "hi", groundingMemories: [m]))
        }
    }

    func testMalformedSuccessBodyIsReported() async throws {
        let (client, _, _) = client([.response(200, "{\"nope\":1}")])
        await assertThrows(.malformedResponse) { _ = try await client.respond(AssistantRequest(sessionID: self.session, userText: "hi")) }
    }

    func testInvalidRequestsNeverReachTheNetwork() async throws {
        let tooMany = try (0..<6).map { _ in try memory() }
        let inputs: [AssistantRequest] = [
            AssistantRequest(sessionID: session, userText: "   "),
            AssistantRequest(sessionID: session, userText: String(repeating: "a", count: 5_001)),
            AssistantRequest(sessionID: session, userText: "hi", groundingMemories: tooMany),
        ]
        for input in inputs {
            let (client, transport, _) = client([okReply()])
            await assertThrows(.invalidRequest) { _ = try await client.respond(input) }
            let count = await transport.recorded().count
            XCTAssertEqual(count, 0)
        }
    }

    func testSampleFixturesAreNeverSent() async throws {
        let fixture = try memory(source: .sampleFixture)
        let (client, transport, _) = client([okReply()])
        _ = try await client.respond(AssistantRequest(sessionID: session, userText: "hi", groundingMemories: [fixture]))
        let sent = await transport.recorded()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent[0].body)) as? [String: Any])
        XCTAssertEqual((json["memories"] as? [Any])?.count, 0)
        XCTAssertEqual(json["taskType"] as? String, "chat")
    }

    private func assertThrows(_ expected: AssistantError, file: StaticString = #filePath, line: UInt = #line, _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as AssistantError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}
