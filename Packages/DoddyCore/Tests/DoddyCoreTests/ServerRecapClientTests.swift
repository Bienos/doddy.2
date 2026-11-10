import XCTest
@testable import DoddyCore

/// Recaps written on Doddy's server (decision 2026-11-09-conversation-recaps, step 3b): the request the app
/// sends, how answers and failures are read, and that a long conversation keeps its ends.
final class ServerRecapClientTests: XCTestCase {
    private let id = UUID(uuidString: "6f1c1f5e-3b0a-4c55-9d0e-0a1b2c3d4e51")!
    private let lines: [RecapModelIO.Line] = [
        .init(speaker: .person, text: "Spotkanie z Anną w czwartek o 18"),
        .init(speaker: .doddy, text: "Zapisałem."),
    ]

    private func client(_ steps: [Result<ServerResponse, any Error>]) -> (ServerRecapClient, StepTransport) {
        let transport = StepTransport(steps)
        return (ServerRecapClient(server: DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "tok"))), transport)
    }

    private func ok(_ body: String = #"{"schemaVersion":1,"requestId":"x","discussed":["Spotkanie z Anną"],"agreed":["Czwartek, 18:00"],"to_do":[],"usage":{"inputTokens":1,"outputTokens":1}}"#)
        -> Result<ServerResponse, any Error> { .success(ServerResponse(status: 200, body: Data(body.utf8))) }

    private func failure(_ status: Int, _ code: String) -> Result<ServerResponse, any Error> {
        .success(ServerResponse(status: status, body: Data(#"{"schemaVersion":1,"error":{"code":"\#(code)","message":"m"}}"#.utf8)))
    }

    private func error(_ client: ServerRecapClient, kind: ConversationRecapKind = .voiceConversation) async -> ServerRecapClient.Failure? {
        do { _ = try await client.write(kind: kind, lines: lines, languageCode: "pl", requestID: id); return nil } catch { return error }
    }

    func testTheRequestIsTheWireTheServerChecks() async throws {
        let (client, transport) = client([ok()])
        let data = try await client.write(kind: .voiceConversation, lines: lines, languageCode: "pl", requestID: id)
        let sent = await transport.sent
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].path, "/v1/recaps")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent[0].body)) as? [String: Any])
        XCTAssertEqual(body["schemaVersion"] as? Int, 1)
        XCTAssertEqual(body["requestId"] as? String, id.uuidString.lowercased())
        XCTAssertEqual(body["kind"] as? String, "voice_conversation")
        XCTAssertEqual(body["language"] as? String, "pl")
        XCTAssertEqual((body["lines"] as? [[String: String]])?.first, ["speaker": "person", "text": "Spotkanie z Anną w czwartek o 18"])
        XCTAssertEqual(Set(body.keys), ["schemaVersion", "requestId", "kind", "language", "lines"])

        // Only the three lists go on, and they still pass the recap rules.
        let recap = try RecapModelIO.read(data, kind: .voiceConversation, with: nil, endedAt: Date(), writtenBy: .server,
                                          conversation: RecapModelIO.plainText(lines))
        XCTAssertEqual(recap.discussed, ["Spotkanie z Anną"])
        XCTAssertEqual(recap.agreed, ["Czwartek, 18:00"])
    }

    func testOnlyConversationsAndRecordingsAreWrittenThere() async {
        XCTAssertTrue(ServerRecapClient.serves(.voiceConversation))
        XCTAssertTrue(ServerRecapClient.serves(.recording))
        XCTAssertFalse(ServerRecapClient.serves(.callForYou))
        XCTAssertFalse(ServerRecapClient.serves(.phoneLine))
        let (client, transport) = client([ok()])
        let failure = await error(client, kind: .callForYou)
        XCTAssertEqual(failure, .notConfigured)
        let sent = await transport.sent
        XCTAssertTrue(sent.isEmpty, "nothing sent")
        let none = await error(ServerRecapClient(server: nil))
        XCTAssertEqual(none, .notConfigured)
    }

    func testFailuresAreNamedAndAnUnknownOutcomeIsNotRetried() async {
        for (step, expected) in [
            (failure(429, "dailyLimitReached"), ServerRecapClient.Failure.dailyLimitReached),
            (failure(503, "notConfigured"), .notConfigured),
            (failure(422, "refused"), .refused),
            (failure(502, "providerUnavailable"), .unavailable),
            (ok(#"{"discussed":["a"],"agreed":[]}"#), .unavailable),
            (.failure(DoddyServerClient.OutcomeUnknown()), .outcomeUnknown),
        ] as [(Result<ServerResponse, any Error>, ServerRecapClient.Failure)] {
            let (client, transport) = client([step, ok()])
            let failure = await error(client)
            XCTAssertEqual(failure, expected)
            let sent = await transport.sent
            XCTAssertEqual(sent.count, 1, "\(expected) is not retried")
        }
    }

    func testALongConversationKeepsItsEndsAndFitsTheServersLimit() {
        let many = (0..<400).map { RecapModelIO.Line(speaker: .person, text: "linia \($0) " + String(repeating: "x", count: 100)) }
        let fitted = RecapModelIO.fitted(many)
        XCTAssertEqual(fitted.first, many.first)
        XCTAssertEqual(fitted.last, many.last)
        XCTAssertTrue(fitted.contains(RecapModelIO.Line(speaker: .other, text: "[…]")))
        XCTAssertLessThanOrEqual(fitted.reduce(0) { $0 + $1.text.unicodeScalars.count + 1 }, RecapModelIO.maxConversationLength)
        XCTAssertEqual(RecapModelIO.fitted(lines), lines, "a short one is sent as it is")
    }
}
