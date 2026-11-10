import XCTest
@testable import DoddyCore

/// Phone-line recaps (decision 2026-11-09-conversation-recaps, step 5): how the iPhone reads what the server
/// made, and that a recap is deleted there only by the iPhone's own request.
final class PhoneRecapClientTests: XCTestCase {
    private let call = UUID(uuidString: "6f1c1f5e-3b0a-4c55-9d0e-0a1b2c3d4e51")!

    private func client(_ steps: [Result<ServerResponse, any Error>]) -> (PhoneRecapClient, StepTransport) {
        let transport = StepTransport(steps)
        return (PhoneRecapClient(server: DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "tok"))), transport)
    }

    private func ok(_ body: String, status: Int = 200) -> Result<ServerResponse, any Error> {
        .success(ServerResponse(status: status, body: Data(body.utf8)))
    }

    private var listBody: String {
        """
        {"schemaVersion":1,"enabled":true,"unreadable":["\(UUID().uuidString.lowercased())"],"recaps":[
          {"callId":"\(call.uuidString.lowercased())","discussed":["Spotkanie z Anną"],"agreed":["Czwartek"],"to_do":["Przypomnieć"],
           "endedAt":"2026-11-10T08:15:30.123Z","durationSecs":95,"direction":"inbound"},
          {"callId":"not-a-uuid","discussed":["x"],"agreed":[],"to_do":[],"endedAt":"2026-11-10T08:15:30.123Z","durationSecs":null,"direction":"inbound"},
          {"callId":"\(UUID().uuidString.lowercased())","discussed":["x"],"agreed":[],"to_do":[],"endedAt":"yesterday","durationSecs":null,"direction":"inbound"},
          {"callId":"\(UUID().uuidString.lowercased())","discussed":["x"],"agreed":[],"to_do":[],"endedAt":"2026-11-10T08:15:30Z","durationSecs":null,"direction":"sideways"}]}
        """
    }

    func testTheListingKeepsOnlyWellFormedRecapsAndNamesTheUnreadable() async throws {
        let (client, transport) = client([ok(listBody)])
        let listing = try await client.list()
        XCTAssertTrue(listing.enabled)
        XCTAssertEqual(listing.recaps.count, 1, "a recap with a bad id, date or direction is left out, never guessed")
        let recap = try XCTUnwrap(listing.recaps.first)
        XCTAssertEqual(recap.callId, call)
        XCTAssertEqual(recap.discussed, ["Spotkanie z Anną"])
        XCTAssertEqual(recap.toDo, ["Przypomnieć"])
        XCTAssertEqual(recap.direction, .inbound)
        XCTAssertEqual(recap.durationSecs, 95)
        XCTAssertEqual(listing.unreadable.count, 1)
        let sent = await transport.sent
        XCTAssertEqual(sent.first?.path, "/v1/calls/recaps")
        XCTAssertEqual(sent.first?.method, .get)
    }

    func testTurningItOnAndOffIsAPutOfOneBoolean() async throws {
        let (client, transport) = client([ok(#"{"schemaVersion":1,"enabled":true}"#), ok(#"{"schemaVersion":1,"enabled":false}"#)])
        try await client.setEnabled(true)
        try await client.setEnabled(false)
        let sent = await transport.sent
        XCTAssertEqual(sent.map(\.path), ["/v1/calls/recaps/settings", "/v1/calls/recaps/settings"])
        XCTAssertEqual(sent.map(\.method), [.put, .put])
        let first = try JSONSerialization.jsonObject(with: XCTUnwrap(sent[0].body)) as? [String: Bool]
        XCTAssertEqual(first, ["enabled": true])
    }

    func testDeletingIsByCallIdAndAlreadyGoneIsDone() async throws {
        let (client, transport) = client([ok("", status: 204), ok(#"{"error":"not_found"}"#, status: 404), ok("", status: 500)])
        try await client.delete(call)
        try await client.delete(call)
        do { try await client.delete(call); XCTFail("a server error is not 'deleted'") } catch { XCTAssertEqual(error as? PhoneRecapClient.Failure, .unavailable) }
        let sent = await transport.sent
        XCTAssertEqual(sent.first?.path, "/v1/calls/recaps/\(call.uuidString.lowercased())")
        XCTAssertEqual(sent.first?.method, .delete)
    }

    func testFailuresAreNamed() async {
        func failure(_ step: Result<ServerResponse, any Error>) async -> PhoneRecapClient.Failure? {
            let (client, _) = client([step])
            do { _ = try await client.list(); return nil } catch { return error as? PhoneRecapClient.Failure }
        }
        let missing = await failure(ok("{}", status: 404))
        XCTAssertEqual(missing, .notConfigured, "an older server without the route")
        let notSetUp = await failure(ok(#"{"error":"not_configured"}"#, status: 503))
        XCTAssertEqual(notSetUp, .notConfigured)
        let broken = await failure(ok("not json"))
        XCTAssertEqual(broken, .unavailable)
        let offline = await failure(.failure(ServerError.offline))
        XCTAssertEqual(offline, .offline)
        let none = PhoneRecapClient(server: nil)
        do { _ = try await none.list(); XCTFail() } catch { XCTAssertEqual(error as? PhoneRecapClient.Failure, .notConfigured) }
    }
}
