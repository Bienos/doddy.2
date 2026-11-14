@testable import DoddyCore
import XCTest

/// The app's side of the deal watches (decision 2026-11-14-price-alerts-screen): four requests with the device token,
/// the contract's refusals mapped to their outcomes, a request outside the limits never sent, and a try whose answer
/// never came back unknown, not saved and not sent again (DOD-08).
final class DealWatchesClientTests: XCTestCase {
    private let watchID = "0b1c8f4e-3d1a-4f7e-9a55-2c6f1e8a7b10"

    private func fixture(_ key: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: try XCTUnwrap(try Fixtures.json("deal_watch_v1.json")[key]))
    }

    private func refusal(_ name: String) throws -> ServerResponse {
        let errors = try XCTUnwrap(try Fixtures.json("deal_watch_v1.json")["errors"] as? [String: [String: Any]])
        let entry = try XCTUnwrap(errors[name])
        return ServerResponse(status: try XCTUnwrap(entry["status"] as? Int),
                              body: try JSONSerialization.data(withJSONObject: try XCTUnwrap(entry["body"])))
    }

    private func client(_ steps: [Result<ServerResponse, any Error>]) -> (DoddyServerClient, StepTransport) {
        let transport = StepTransport(steps)
        return (DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t")), transport)
    }

    private let request = DealWatchRequest(item: "masło", maxPriceMinor: 500, chains: [.biedronka, .lidl], language: "pl")

    // MARK: The four requests

    func testTheListIsOneGetWithTheDeviceTokenAndDecodesTheFixture() async throws {
        let (client, transport) = client([.success(ServerResponse(status: 200, body: try fixture("list")))])
        let list = try await client.dealWatches()
        XCTAssertFalse(list.watches.isEmpty)
        let sent = await transport.sent
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].method, .get)
        XCTAssertEqual(sent[0].path, "/v1/deal-watches")
        XCTAssertEqual(sent[0].bearerToken, "t")
        XCTAssertNil(sent[0].body)
    }

    func testMakingAWatchSendsExactlyTheRequestsFieldsOnceAndReturnsWhatTheServerSaid() async throws {
        let (client, transport) = client([.success(ServerResponse(status: 201, body: try fixture("created")))])
        let created = try await client.createDealWatch(request)
        XCTAssertFalse(created.watch.id.isEmpty)
        let sent = await transport.sent
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].method, .post)
        XCTAssertEqual(sent[0].path, "/v1/deal-watches")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(sent[0].body)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["item", "maxPriceMinor", "chains", "language"])
        XCTAssertEqual(body["item"] as? String, "masło")
        XCTAssertEqual(body["maxPriceMinor"] as? Int, 500)
        XCTAssertEqual(body["chains"] as? [String], ["biedronka", "lidl"])
        XCTAssertEqual(body["language"] as? String, "pl")
    }

    func testAnAlertWithoutAPriceOrShopsSendsOnlyWhatWasSet() async throws {
        let (client, transport) = client([.success(ServerResponse(status: 201, body: try fixture("created")))])
        _ = try await client.createDealWatch(DealWatchRequest(item: "kawa", language: "en"))
        let sent = await transport.sent
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(sent[0].body)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["item", "language"], "the server's body is strict: the optional fields only when set")
    }

    func testMatchesAndDeleteUseTheIdInThePath() async throws {
        let (client, transport) = client([
            .success(ServerResponse(status: 200, body: try fixture("offers"))),
            .success(ServerResponse(status: 204)),
        ])
        let matches = try await client.dealWatchMatches(id: watchID)
        XCTAssertFalse(matches.offers.contains(where: \.isSimilarOnly))
        try await client.deleteDealWatch(id: watchID)
        let sent = await transport.sent
        XCTAssertEqual(sent.map(\.path), ["/v1/deal-watches/\(watchID)/offers", "/v1/deal-watches/\(watchID)"])
        XCTAssertEqual(sent.map(\.method), [.get, .delete])
    }

    func testDeletingAWatchThatIsAlreadyGoneIsDeleted() async throws {
        let (client, _) = client([.success(try refusal("notFound"))])
        try await client.deleteDealWatch(id: watchID)
    }

    // MARK: Nothing out of bounds leaves the phone

    func testARequestOutsideTheLimitsIsNeverSent() async throws {
        let (client, transport) = client([.success(ServerResponse(status: 201, body: try fixture("created")))])
        do {
            _ = try await client.createDealWatch(DealWatchRequest(item: "", maxPriceMinor: 0))
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? DealWatchesError, .invalid(fields: ["item", "maxPriceMinor"]))
        }
        let sent = await transport.sent
        XCTAssertEqual(sent.count, 0)
    }

    func testAnIdThatIsNotAUUIDIsNeverPutInAPath() async throws {
        let (client, transport) = client([])
        for id in ["../account", "", "1; drop", watchID + "/offers"] {
            do { _ = try await client.dealWatchMatches(id: id); XCTFail("expected a refusal for \(id)") } catch {
                XCTAssertEqual(error as? DealWatchesError, .invalid(fields: ["id"]), id)
            }
            do { try await client.deleteDealWatch(id: id); XCTFail("expected a refusal for \(id)") } catch {
                XCTAssertEqual(error as? DealWatchesError, .invalid(fields: ["id"]), id)
            }
        }
        let sent = await transport.sent
        XCTAssertEqual(sent.count, 0)
    }

    // MARK: Refusals

    func testRefusalsMapToTheirOutcomes() throws {
        XCTAssertEqual(DoddyServerClient.dealWatchError(from: try refusal("invalid")), .invalid(fields: ["chains.0"]))
        XCTAssertEqual(DoddyServerClient.dealWatchError(from: try refusal("notFound")), .notFound)
        XCTAssertEqual(DoddyServerClient.dealWatchError(from: try refusal("tooMany")), .tooManyWatches)
        XCTAssertEqual(DoddyServerClient.dealWatchError(from: try refusal("serverFull")), .serverFull)
        XCTAssertEqual(DoddyServerClient.dealWatchError(from: try refusal("disabled")), .disabled)
        let other: [(ServerResponse, DealWatchesError)] = [
            (ServerResponse(status: 429, body: Data(#"{"error":"slow_down"}"#.utf8)), .server(.rateLimited)),
            (ServerResponse(status: 503, body: Data(#"{"error":"maintenance"}"#.utf8)), .server(.notConfigured("maintenance"))),
            (ServerResponse(status: 500), .server(.unexpected(status: 500))),
            (ServerResponse(status: 502), .server(.providerUnavailable)),
        ]
        for (response, expected) in other { XCTAssertEqual(DoddyServerClient.dealWatchError(from: response), expected, "\(response.status)") }
    }

    func testAnUnreadableListIsAnErrorAndARevokedTokenIsTheAccountMissing() async throws {
        let (garbled, _) = client([.success(ServerResponse(status: 200, body: Data("<html>".utf8)))])
        do { _ = try await garbled.dealWatches(); XCTFail("expected an error") } catch {
            XCTAssertEqual(error as? DealWatchesError, .server(.unexpected(status: 200)))
        }
        let (revoked, _) = client([.success(ServerResponse(status: 401))])
        do { _ = try await revoked.dealWatches(); XCTFail("expected an error") } catch {
            XCTAssertEqual(error as? DealWatchesError, .server(.accountMissing))
        }
    }

    // MARK: A try whose answer never came back (DOD-08)

    func testMakingAWatchWhoseAnswerNeverCameBackIsUnknownAndIsNotSentAgain() async throws {
        let (client, transport) = client([.failure(URLError(.timedOut))])
        do { _ = try await client.createDealWatch(request); XCTFail("expected unknown") } catch {
            XCTAssertEqual(error as? DealWatchesError, .outcomeUnknown)
        }
        let sent = await transport.sent
        XCTAssertEqual(sent.count, 1, "never retried by itself")
    }

    func testMakingAWatchWithNoNetworkIsOfflineBecauseNothingLeftThePhone() async throws {
        let (client, transport) = client([.failure(URLError(.notConnectedToInternet))])
        do { _ = try await client.createDealWatch(request); XCTFail("expected offline") } catch {
            XCTAssertEqual(error as? DealWatchesError, .server(.offline))
        }
        let sent = await transport.sent
        XCTAssertEqual(sent.count, 1)
    }

    func testACreatedAnswerThatCantBeReadIsUnknownNotSavedAndNotAnError() async throws {
        let (client, transport) = client([.success(ServerResponse(status: 201, body: Data("<html>".utf8)))])
        do { _ = try await client.createDealWatch(request); XCTFail("expected unknown") } catch {
            XCTAssertEqual(error as? DealWatchesError, .outcomeUnknown, "the watch exists; the app can't show it and must not make it twice")
        }
        let sent = await transport.sent
        XCTAssertEqual(sent.count, 1)
    }

    func testReadingNeverStartsAnythingSoALostAnswerIsJustOffline() async throws {
        let (client, _) = client([.failure(URLError(.timedOut))])
        do { _ = try await client.dealWatches(); XCTFail("expected offline") } catch {
            XCTAssertEqual(error as? DealWatchesError, .server(.offline))
        }
    }
}
