import Foundation
import XCTest
@testable import DoddyCore

/// Flights (decision 2026-11-11-flights-kiwi-search-duffel-booking): how the app routes and words the four tools.
/// The server's half is backend/test/flights.test.ts.
final class FlightToolsTests: XCTestCase {
    private func receipt(_ status: ReceiptStatus, errorCode: String?) -> OnlineToolReceipt {
        OnlineToolReceipt(
            operationId: UUID(), operation: .write, toolkit: "flights", tool: CloudToolName.bookFlight, timestamp: "2026-10-10T10:00:00.000Z",
            mode: .live, status: status, summary: "x", errorCode: errorCode, providerReference: nil)
    }

    func testSearchesAndTheCheckRunAtOnceAndBookingWaitsForATap() {
        for name in [CloudToolName.findFlights, CloudToolName.findBookableFlights, CloudToolName.checkFlightBooking] {
            XCTAssertTrue(CloudToolName.all.contains(name), name)
            XCTAssertFalse(CloudToolName.isWrite(name), name)
            XCTAssertTrue(AskFirst.runsAtOnce(name), name)
            XCTAssertEqual(AskFirst.need(for: .cloudTool(CloudToolCall(name: name, arguments: [:]))), .runsNow, name)
        }
        XCTAssertTrue(CloudToolName.isWrite(CloudToolName.bookFlight))
        XCTAssertFalse(AskFirst.runsAtOnce(CloudToolName.bookFlight))
        let need = AskFirst.need(for: .cloudTool(CloudToolCall(name: CloudToolName.bookFlight, arguments: [:])))
        XCTAssertEqual(need, .serverCard(isWrite: true))
        XCTAssertTrue(AskFirst.needsTap(need))
        for name in CloudToolName.flightTools { XCTAssertFalse(CloudToolName.needsAccount(name), name) }
    }

    func testFlightToolsBelongToTheFlightsFeatureOnly() {
        XCTAssertEqual(Feature.flights.tools, CloudToolName.flightTools)
        XCTAssertTrue(Feature.onlineAccounts.tools.isDisjoint(with: CloudToolName.flightTools))
        XCTAssertNil(ReleaseScope.shipping.hiddenFeature(forTool: CloudToolName.bookFlight))
    }

    func testARefusedBookingSaysNothingWasBookedAndAnUnsureOneSaysUnknown() {
        let refused = VoiceToolReply.cloudFailed(
            .server(code: "not_found", message: "That offer is gone or expired. Search again.", retryAfterSeconds: nil, receipt: receipt(.blocked, errorCode: "offer_gone")),
            tool: CloudToolName.bookFlight)
        XCTAssertTrue(refused.hasPrefix("failed: "), refused)
        XCTAssertTrue(refused.hasSuffix("Nothing was booked."), refused)

        let unsure = VoiceToolReply.cloudFailed(
            .server(code: "capability_disabled", message: "x", retryAfterSeconds: nil, receipt: receipt(.outcomeUnknown, errorCode: "earlier_outcome_unknown")),
            tool: CloudToolName.bookFlight)
        XCTAssertTrue(unsure.hasPrefix("unknown:"), unsure)

        // No receipt and no answer: it may have reached Duffel, so never "failed".
        XCTAssertTrue(VoiceToolReply.cloudFailed(.transport("timeout"), tool: CloudToolName.bookFlight).hasPrefix("unknown:"))
    }

    func testTheServersBookingWordsReachTheAgentAndTheLog() throws {
        let booked = try decodeRun(text: "booked: Duffel confirmed the booking. Airline booking reference RZPNX8.")
        XCTAssertTrue(VoiceToolReply.cloudResult(booked).hasPrefix("booked: "))
        let notBooked = try decodeRun(text: "failed: The offer expired. Search again. Duffel said nothing was booked.")
        XCTAssertTrue(VoiceToolReply.cloudResult(notBooked).hasPrefix("failed: "))
        XCTAssertEqual(ActivityLog.outcome(of: VoiceToolReply.cloudResult(booked), isLookup: false).0, .done)
        XCTAssertEqual(ActivityLog.outcome(of: VoiceToolReply.cloudResult(notBooked), isLookup: false).0, .notDone)
    }

    func testOnlyKiwiPagesBecomeButtons() throws {
        let result = try decodeRun(text: "Flights", tool: CloudToolName.findFlights, links: [
            ["title": "183 PLN, WMI → BCN", "url": "https://kiwi.com/u/4gyym5w"],
            ["title": "elsewhere", "url": "https://evil.example/x"],
            ["title": "plain http", "url": "http://www.kiwi.com/x"],
        ])
        XCTAssertEqual(result.links?.filter(\.isKiwi).map(\.title), ["183 PLN, WMI → BCN"])
        // An answer with no links still decodes (every other tool).
        XCTAssertNil(try decodeRun(text: "x").links)
    }

    private func decodeRun(text: String, tool: String = CloudToolName.bookFlight, links: [[String: String]]? = nil) throws -> RunResult {
        var json: [String: Any] = [
            "mode": "live", "tool": tool, "text": text, "count": 1, "truncated": false,
            "receipt": [
                "operationId": UUID().uuidString, "operation": "write", "toolkit": "flights", "tool": tool,
                "timestamp": "2026-10-10T10:00:00.000Z", "mode": "live", "status": "succeeded", "summary": "x",
                "errorCode": NSNull(), "providerReference": NSNull(),
            ],
        ]
        if let links { json["links"] = links }
        return try JSONDecoder().decode(RunResult.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
