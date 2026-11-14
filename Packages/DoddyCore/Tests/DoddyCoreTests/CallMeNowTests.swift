import Foundation
import XCTest
@testable import DoddyCore

/// "Doddy, call me": the same call as Settings, Phone calls, Call me now, approved on a card
/// (decision 2026-11-10-call-me-now-by-voice).
final class CallMeNowTests: XCTestCase {
    private func parse(_ json: String = "{}") -> VoiceToolRequest {
        VoiceToolRequest.parse(name: VoiceToolName.callMeNow, parametersJSON: Data(json.utf8), now: Date(), calendar: .current)
    }

    func testTheToolNeedsNoParametersAndIgnoresAnyItIsGiven() {
        XCTAssertEqual(parse(), .callMeNow)
        // Nothing the model writes can change who is called: the server calls only the verified number.
        XCTAssertEqual(parse(#"{"to":"+48600000000"}"#), .callMeNow)
    }

    func testItNeedsACardIsNeverAPlanStepAndWaitsWhileDrivingOrPaused() throws {
        let tool = try XCTUnwrap(ToolCatalog.descriptor(VoiceToolName.callMeNow))
        XCTAssertEqual(tool.effect, .placeCall)
        XCTAssertEqual(tool.approval, .card)
        XCTAssertEqual(tool.runsOn, .phone)
        XCTAssertFalse(tool.planEligible)
        XCTAssertEqual(AskFirst.need(for: .callMeNow, polish: false), .ownPayloadCard)
        guard case .refuse(let reason) = CarProfile.decision(for: .callMeNow) else { return XCTFail("car") }
        XCTAssertTrue(reason.contains("driving"))
        XCTAssertTrue(ConnectionPause.applies(to: .callMeNow), "it leaves the iPhone through Doddy's server and Twilio")
        XCTAssertEqual(
            ToolGate.decide(toolName: VoiceToolName.callMeNow, request: .callMeNow, translatorOn: false, pauseAll: true, isOn: { _ in true }),
            .paused)
        XCTAssertEqual(
            ToolGate.decide(toolName: VoiceToolName.callMeNow, request: .callMeNow, translatorOn: true, pauseAll: false, isOn: { _ in true }),
            .translatorRefused)
    }

    func testItIsPartOfPhoneCallsAndShownWithThem() {
        XCTAssertTrue(Feature.phoneCalls.tools.contains(VoiceToolName.callMeNow))
        XCTAssertTrue(ReleaseScope.shipping.shows(.phoneCalls), "phone calls are shown since 10 Nov 2026, and the tool with them")
        XCTAssertTrue(ReleaseScope(hidden: [.phoneCalls]).hiddenTools.contains(VoiceToolName.callMeNow), "a scope that hides them takes the tool too")
    }

    func testTheLogSaysACallWasAskedForAndNothingElse() throws {
        let row = try XCTUnwrap(ActivityRequest.describe(.callMeNow, calendar: .current))
        XCTAssertEqual(row.title, "Call you now from Doddy's number")
        XCTAssertNil(row.detail)
        XCTAssertNil(row.logDetail)
        XCTAssertEqual(row.app, .messages)
        XCTAssertFalse(row.isLookup)
    }

    // MARK: What the agent hears

    func testOnlyRequestedSaysThePhoneRingsAndNothingClaimsTheCallConnected() {
        XCTAssertEqual(CallNowOutcome(CallRequest(callId: UUID(), status: "requested")), .requested)
        XCTAssertEqual(CallNowOutcome(CallRequest(callId: nil, status: "unknown")), .unknown)
        XCTAssertEqual(CallNowOutcome(CallRequest(callId: UUID(), status: "something_new")), .unknown, "only requested counts")

        let requested = VoiceToolReply.callNow(.requested)
        XCTAssertTrue(requested.hasPrefix("requested:"))
        XCTAssertTrue(requested.contains("Don't say the call connected"))
        let unknown = VoiceToolReply.callNow(.unknown)
        XCTAssertTrue(unknown.hasPrefix("unknown:"))
        XCTAssertTrue(unknown.contains("don't call call_me_now again on your own"))
        for error: ServerError in [.providerUnavailable, .offline, .rateLimited, .notConfigured("not_configured"),
                                   .notEnabled("outbound_not_enabled"), .notEnabled("no_verified_phone"),
                                   .notEnabled("phone_not_allowed"), .accountMissing, .unexpected(status: 418)] {
            let text = VoiceToolReply.callNow(.refused(error))
            XCTAssertTrue(text.hasPrefix("failed: "), "\(error)")
            XCTAssertTrue(text.hasSuffix("No call was placed."), "\(error)")
        }
        XCTAssertTrue(VoiceToolReply.callNow(.refused(.notEnabled("outbound_not_enabled"))).contains("Doddy may call me"))
        XCTAssertTrue(VoiceToolReply.callNow(.refused(.rateLimited)).contains("\(ContactCaps.callsPerHour) times an hour"))
    }

    func testBeforeTheCardTheReasonsSayNoCallWasPlaced() {
        for readiness: CallReadiness in [.noPhone, .callsOff, .notSetUp] {
            let text = VoiceToolReply.callNowNotReady(readiness)
            XCTAssertTrue(text.hasPrefix("failed: "))
            XCTAssertTrue(text.hasSuffix("No call was placed."), text)
            XCTAssertFalse(text.contains("booked"), text)
        }
        for error: ServerError? in [.offline, .accountMissing, .rateLimited, nil] {
            let text = VoiceToolReply.callNowCheckFailed(error)
            XCTAssertTrue(text.hasPrefix("failed: "))
            XCTAssertFalse(text.contains("booked"), text)
        }
        XCTAssertFalse(VoiceToolReply.callNowDeclined.contains("booked"))
    }

    // MARK: The request

    private func reply(_ status: Int, _ json: String = "") -> Result<ServerResponse, any Error> {
        .success(ServerResponse(status: status, body: Data(json.utf8)))
    }

    func testTheServersOwnRefusalIsNotPlacedButAGatewayErrorIsStillUnknown() async throws {
        // Doddy's messaging server: Twilio turned the call down, the call row is failed.
        let refused = StepTransport([reply(502, #"{"error":"provider_unavailable","callId":"6f1c2c1e-3b6c-4c55-9a39-0d6a1e9f1a10"}"#)])
        let client = DoddyServerClient(transport: refused, credentials: FixedCredentials(token: "t"))
        do {
            _ = try await client.callMeNow()
            XCTFail("expected providerUnavailable")
        } catch {
            XCTAssertEqual(error as? ServerError, .providerUnavailable)
        }
        // A proxy's 502, or one without the call's id, may come after the call started (ADR-672).
        for body in ["", "<html>Bad gateway</html>", #"{"error":"provider_unavailable"}"#, #"{"error":"upstream_unavailable","callId":"6f1c2c1e-3b6c-4c55-9a39-0d6a1e9f1a10"}"#] {
            let transport = StepTransport([reply(502, body)])
            let request = try await DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t")).callMeNow()
            XCTAssertEqual(request.status, "unknown", body)
            let sent = await transport.sent
            XCTAssertEqual(sent.count, 1, "never sent twice")
        }
    }

    func testOtherRefusalsKeepTheirReason() async throws {
        let cases: [(Int, String, ServerError)] = [
            (409, #"{"error":"outbound_not_enabled"}"#, .notEnabled("outbound_not_enabled")),
            (409, #"{"error":"no_verified_phone"}"#, .notEnabled("no_verified_phone")),
            (429, #"{"error":"daily_limit"}"#, .rateLimited),
            (503, #"{"error":"not_configured"}"#, .notConfigured("not_configured")),
        ]
        for (status, body, expected) in cases {
            let client = DoddyServerClient(transport: StepTransport([reply(status, body)]), credentials: FixedCredentials(token: "t"))
            do {
                _ = try await client.callMeNow()
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? ServerError, expected, body)
            }
        }
    }

    // MARK: The written spec

    func testTheVoiceAgentSpecHasTheToolWithNoParametersAndATapCard() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("voice-agent/tools.json"))
        let spec = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tools = try XCTUnwrap(spec["tools"] as? [[String: Any]])
        let tool = try XCTUnwrap(tools.first { $0["name"] as? String == VoiceToolName.callMeNow })
        let parameters = try XCTUnwrap(tool["parameters"] as? [String: Any])
        XCTAssertEqual((parameters["properties"] as? [String: Any])?.count, 0)
        let x = try XCTUnwrap(tool["x_doddy"] as? [String: Any])
        XCTAssertEqual(x["ask"] as? String, "tap")
        XCTAssertEqual(x["confirm_on_screen"] as? Bool, true)
        let later = try XCTUnwrap(tools.first { $0["name"] as? String == VoiceToolName.callMeLater })
        XCTAssertTrue((later["description"] as? String ?? "").contains("use call_me_now"))
    }
}
