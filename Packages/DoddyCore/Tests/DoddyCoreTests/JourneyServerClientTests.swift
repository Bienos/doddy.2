import Foundation
import XCTest
@testable import DoddyCore

private actor JourneyTransport: ServerTransport {
    private(set) var requests: [ServerRequest] = []
    var result: ServerResponse

    init(status: Int = 200, data: String) {
        self.result = ServerResponse(status: status, body: Data(data.utf8))
    }

    func send(_ request: ServerRequest) async throws -> ServerResponse {
        requests.append(request)
        return result
    }

    func recorded() -> [ServerRequest] { requests }
}

private final class JourneyCredentials: ServerCredentialStore, @unchecked Sendable {
    func load() throws -> String? { "test-device-token" }
    func save(_ token: String) throws {}
    func delete() throws {}
}

final class JourneyServerClientTests: XCTestCase {
    private let routeJSON = """
    {
      "source":"Jakdojade", "fetchedAt":"2026-11-20T07:55:00Z", "realtime":false, "tickets":false,
      "routes":[{
        "source":"Jakdojade", "startLocal":"20.11.26 08:05", "finishLocal":"20.11.26 08:43",
        "segments":[{"line":"M2","vehicleType":"subway","direction":"Bródno",
          "stops":[{"name":"Rondo ONZ","departure":"08:10","arrival":null},{"name":"Świętokrzyska","arrival":"08:13","departure":"08:14"}]
        }]
      }]
    }
    """

    func testOnlySignedInRouteRequestWithSanitizedCoordinates() async throws {
        let transport = JourneyTransport(data: routeJSON)
        let client = DoddyServerClient(transport: transport, credentials: JourneyCredentials())
        let start = JourneyCoordinate(latitude: 52.23232, longitude: 21.01599)
        let end = JourneyCoordinate(latitude: 52.26289, longitude: 20.98983)
        let result = try await client.journeyRoutes(JourneyRouteQuery(
            from: start, to: end, day: "20.11.26", hour: "08:50",
            arriving: true, mode: "convenient", avoidBuses: true))
        XCTAssertEqual(result.routes.count, 1)
        XCTAssertEqual(result.routes.first?.segments.first?.line, "M2")
        XCTAssertEqual(result.realtime, false)
        XCTAssertEqual(result.tickets, false)
        let sent = await transport.recorded()
        let call = try XCTUnwrap(sent.first)
        XCTAssertEqual(call.path, "/v1/journeys/routes")
        XCTAssertEqual(call.method, .post)
        XCTAssertEqual(call.bearerToken, "test-device-token")
        let payload = try XCTUnwrap(call.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let coords = try XCTUnwrap(json["from"] as? [String: Double])
        XCTAssertEqual(coords["latitude"], 52.23232)
    }

    func testNoInvalidCoordinatesOrDatesReachTheServer() async throws {
        let transport = JourneyTransport(data: routeJSON)
        let client = DoddyServerClient(transport: transport, credentials: JourneyCredentials())
        let invalid = JourneyRouteQuery(
            from: JourneyCoordinate(latitude: 111, longitude: 18),
            to: JourneyCoordinate(latitude: 52.23, longitude: 21.05),
            hour: "25:99", mode: "unknown")
        do {
            _ = try await client.journeyRoutes(invalid)
            XCTFail("Invalid journey should never be sent")
        } catch JourneyBackendError.invalid { }
        let sent = await transport.recorded()
        XCTAssertEqual(sent.count, 0)
    }

    func testPartnerDisabledDoesNotReturnDemoRoutes() async throws {
        let transport = JourneyTransport(status: 503, data: #"{"error":"jakdojade_not_configured"}"#)
        let client = DoddyServerClient(transport: transport, credentials: JourneyCredentials())
        do {
            _ = try await client.journeyRoutes(JourneyRouteQuery(
                from: JourneyCoordinate(latitude: 52.23, longitude: 21),
                to: JourneyCoordinate(latitude: 52.24, longitude: 21.02)))
            XCTFail("Disabled provider cannot return routes")
        } catch JourneyBackendError.server(.notConfigured(let code)) {
            XCTAssertEqual(code, "jakdojade_not_configured")
        }
    }

    func testSourceDatesAreLocalNotUTCAndImpossibleDatesAreRejected() throws {
        let result = try JSONDecoder().decode(JourneyPartnerRoutes.self, from: Data(routeJSON.utf8))
        let route = try XCTUnwrap(result.routes.first?.normalized())
        XCTAssertEqual(route.source, "Jakdojade")
        XCTAssertEqual(ServerDates.format(route.departs), "2026-11-20T07:05:00Z")
        XCTAssertEqual(route.segments.first?.from, "Rondo ONZ")
        XCTAssertEqual(route.segments.first?.to, "Świętokrzyska")
        let corrupted = """
        {"source":"Jakdojade","startLocal":"20.11.26 08:43","finishLocal":"20.11.26 08:05","segments":[{"line":"M2","vehicleType":"subway","direction":null,"stops":[]}]}
        """
        let impossible = try JSONDecoder().decode(JourneyPartnerRoute.self, from: Data(corrupted.utf8))
        XCTAssertNil(impossible.normalized())
    }

    func testProviderStatusIsReadOnly() async throws {
        let transport = JourneyTransport(data: """
        {"provider":"jakdojade","available":false,"capabilities":[],"tickets":false,"realtime":false}
        """)
        let client = DoddyServerClient(transport: transport, credentials: JourneyCredentials())
        let status = try await client.journeyProviderStatus()
        XCTAssertFalse(status.available)
        let requests = await transport.recorded()
        XCTAssertEqual(requests.first?.path, "/v1/journeys/provider")
    }
}
