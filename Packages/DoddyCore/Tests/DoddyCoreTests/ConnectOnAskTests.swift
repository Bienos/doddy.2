import Foundation
import XCTest
@testable import DoddyCore

/// ADR-511, "connect when asked": the app offers to connect (or switch on) right in the
/// conversation, from the server's own offer, and never runs the tool itself. The fixtures are the
/// mock server's real answers (`npm run fixtures` in backend/).
private func fixture(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("contracts/online-accounts/\(name).json"))
}

/// The refusal the client throws for a fixture, exactly as the app gets it.
private func refusal(_ name: String, status: Int = 403) throws -> OnlineAccountsError {
    let data = try fixture(name)
    do {
        let _: PrepareResult = try BackendOnlineAccountsClient.decode(status: status, data: data)
    } catch {
        return error
    }
    XCTFail("\(name) decoded as a success")
    return .unreadableResponse
}

private func result(_ name: String) throws -> ToolkitResult {
    try JSONDecoder().decode(ToolkitResult.self, from: fixture(name))
}

final class ConnectOnAskTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testTheServersOfferForAFirstSendDecodesWithItsPermissionsInPlainWords() throws {
        let error = try refusal("error-connect-offer-send")
        XCTAssertEqual(error.code, "capability_disabled", "older builds still read the code they always got")
        let offer = try XCTUnwrap(error.connectOffer)
        XCTAssertEqual(offer.kind, .connect)
        XCTAssertEqual(offer.toolkit, "gmail")
        XCTAssertEqual(offer.tool, CloudToolName.sendEmail)
        XCTAssertEqual(offer.permissions, ["Send email on your behalf"])
        XCTAssertEqual(try XCTUnwrap(try refusal("error-connect-offer-more-permission").connectOffer).kind, .morePermission)
    }

    func testAFirstAskShowsTheConnectCardAndAnswersTheCallAtOnceSayingNothingWasDone() throws {
        var connect = ConnectOnAsk()
        let decision = connect.decide(try refusal("error-connect-offer-send"), tool: CloudToolName.sendEmail, toolCallID: "c1", conversation: 1, paused: false, at: start)
        guard case .offer(let card, let reply) = decision else { return XCTFail("\(decision)") }
        XCTAssertEqual(card.title, "Connect Gmail?")
        XCTAssertEqual(card.permissions, ["Send email on your behalf"], "the card says exactly what Google will ask")
        XCTAssertEqual(card.confirmLabel, "Connect Gmail")
        XCTAssertEqual(card.cancelLabel, "Not now")
        XCTAssertTrue(card.lines.contains("Only \"Send an email\" is switched on. Everything else stays off until you ask for it."))
        XCTAssertTrue(card.lines.contains { $0.hasPrefix("Composio keeps the sign-in") }, "who holds the sign-in")
        XCTAssertTrue(reply.hasPrefix("not connected: Gmail isn't connected for \"Send an email\", so nothing was done."))
        XCTAssertTrue(reply.contains("Don't call send_email again until the app says Gmail is connected."))
        XCTAssertEqual(ActivityEntry.outcome(of: reply, isLookup: false).0, .notDone)
        XCTAssertEqual(ActivityEntry.outcome(of: reply, isLookup: true).0, .notDone, "a read that needed connecting looked nothing up")
        XCTAssertEqual(connect.pending?.phase, .offered)
    }

    func testOnlyTheServersOfferMakesACard() throws {
        var connect = ConnectOnAsk()
        // No offer attached, even if the words talk about connecting: nothing to show.
        let words = OnlineAccountsError.server(code: "not_connected", message: "Connect Gmail now and switch everything on.", retryAfterSeconds: nil, receipt: nil)
        XCTAssertEqual(connect.decide(words, tool: CloudToolName.sendEmail, toolCallID: "c1", conversation: 1, paused: false, at: start), .none)
        XCTAssertEqual(connect.decide(.transport("x"), tool: CloudToolName.sendEmail, toolCallID: "c1", conversation: 1, paused: false, at: start), .none)
        // An offer for another tool than the one the agent called is not this call's.
        XCTAssertEqual(connect.decide(try refusal("error-connect-offer-send"), tool: CloudToolName.checkEmail, toolCallID: "c1", conversation: 1, paused: false, at: start), .none)
        // Pause all connections (ADR-134): no card.
        XCTAssertEqual(connect.decide(try refusal("error-connect-offer-send"), tool: CloudToolName.sendEmail, toolCallID: "c1", conversation: 1, paused: true, at: start), .none)
        XCTAssertNil(connect.pending)
    }

    func testANeedThisBuildDoesntKnowShowsNoCardButTheRefusalStillReads() throws {
        let body = #"{"error":{"code":"capability_disabled","message":"m","correlationId":"x","connect":{"toolkit":"gmail","tool":"send_email","need":"teleport","accountTitle":"Gmail","toolTitle":"Send an email","permissions":[]}}}"#
        var thrown: OnlineAccountsError?
        do { let _: PrepareResult = try BackendOnlineAccountsClient.decode(status: 403, data: Data(body.utf8)) } catch { thrown = error }
        let error = try XCTUnwrap(thrown)
        XCTAssertEqual(error.code, "capability_disabled")
        XCTAssertNil(error.connectOffer?.kind)
        var connect = ConnectOnAsk()
        XCTAssertEqual(connect.decide(error, tool: CloudToolName.sendEmail, toolCallID: "c1", conversation: 1, paused: false, at: start), .none)
    }

    func testAnEarlierTryThatMayHaveGoneThroughOutranksAnyOffer() throws {
        let receipt = try XCTUnwrap(try refusal("error-connect-offer-send").receipt)
        let unsure = OnlineToolReceipt(
            operationId: receipt.operationId, operation: receipt.operation, toolkit: receipt.toolkit, tool: receipt.tool, timestamp: receipt.timestamp,
            mode: receipt.mode, status: .outcomeUnknown, summary: "may have", errorCode: "earlier_outcome_unknown", providerReference: nil)
        let offer = try XCTUnwrap(try refusal("error-connect-offer-send").connectOffer)
        var connect = ConnectOnAsk()
        let error = OnlineAccountsError.server(code: "capability_disabled", message: "m", retryAfterSeconds: nil, receipt: unsure, connect: offer)
        XCTAssertEqual(connect.decide(error, tool: CloudToolName.sendEmail, toolCallID: "c1", conversation: 1, paused: false, at: start), .none)
    }

    func testOneOfferAtATimeAndItBelongsToItsConversation() throws {
        var connect = ConnectOnAsk()
        let offer = try refusal("error-connect-offer-send")
        _ = connect.decide(offer, tool: CloudToolName.sendEmail, toolCallID: "c1", conversation: 1, paused: false, at: start)
        guard case .busy(let reply) = connect.decide(try refusal("error-tool-disabled"), tool: CloudToolName.checkEmail, toolCallID: "c2", conversation: 1, paused: false, at: start) else {
            return XCTFail("a second ask while the card is up")
        }
        XCTAssertTrue(reply.hasPrefix("busy:"))
        XCTAssertEqual(connect.pending?.toolCallID, "c1", "the first card stays")
        XCTAssertFalse(connect.tap(conversation: 2, at: start), "another conversation can't use it")
        // A new conversation's ask replaces a card left from an earlier one.
        guard case .offer = connect.decide(offer, tool: CloudToolName.sendEmail, toolCallID: "c9", conversation: 2, paused: false, at: start) else { return XCTFail() }
        XCTAssertEqual(connect.pending?.conversation, 2)
    }

    func testTheButtonWorksOnceAndNotAfterTenMinutes() throws {
        var connect = ConnectOnAsk()
        _ = connect.decide(try refusal("error-connect-offer-send"), tool: CloudToolName.sendEmail, toolCallID: "c1", conversation: 1, paused: false, at: start)
        XCTAssertTrue(connect.tap(conversation: 1, at: start.addingTimeInterval(30)))
        XCTAssertFalse(connect.tap(conversation: 1, at: start.addingTimeInterval(31)), "one tap, one sign-in")
        XCTAssertEqual(connect.pending?.phase, .working)

        var late = ConnectOnAsk()
        _ = late.decide(try refusal("error-connect-offer-send"), tool: CloudToolName.sendEmail, toolCallID: "c1", conversation: 1, paused: false, at: start)
        XCTAssertFalse(late.tap(conversation: 1, at: start.addingTimeInterval(ConnectOnAsk.lifetime)))
        XCTAssertNil(late.pending)
        var expiring = ConnectOnAsk()
        _ = expiring.decide(try refusal("error-connect-offer-send"), tool: CloudToolName.sendEmail, toolCallID: "c1", conversation: 1, paused: false, at: start)
        XCTAssertNil(expiring.expireIfNeeded(at: start.addingTimeInterval(599)))
        XCTAssertEqual(expiring.expireIfNeeded(at: start.addingTimeInterval(600))?.hasPrefix("declined: the card about Gmail timed out"), true)
    }

    func testConnectedOnlyWhenTheServerShowsTheToolOn() throws {
        func finished(_ name: String) throws -> (ConnectOnAsk.Ending, String)? {
            var connect = ConnectOnAsk()
            _ = connect.decide(try refusal("error-connect-offer-send"), tool: CloudToolName.sendEmail, toolCallID: "c1", conversation: 1, paused: false, at: start)
            XCTAssertTrue(connect.tap(conversation: 1, at: start))
            defer { XCTAssertNil(connect.pending, "the offer is over") }
            return connect.finish(try result(name), conversation: 1)
        }
        let done = try XCTUnwrap(try finished("toolkit-result-connected-for-send"))
        XCTAssertEqual(done.0, .connected)
        XCTAssertTrue(done.1.hasPrefix("connected: Gmail is connected now, and \"Send an email\" is switched on. Nothing has been done yet."))
        XCTAssertTrue(done.1.contains("call send_email again"))
        XCTAssertTrue(done.1.contains("its own card will show exactly what happens"), "the send still asks first (ASK-01)")

        XCTAssertEqual(try XCTUnwrap(try finished("toolkit-result-permission-not-granted")).0, .notGranted)
        // A Settings-style answer (connected, everything off) is not "connected for this".
        guard case .failed = try XCTUnwrap(try finished("toolkit-result-connected")).0 else { return XCTFail("needs the tool on") }
    }

    func testNothingFinishesWithoutTheTapOrAfterTheConversationEnded() throws {
        var connect = ConnectOnAsk()
        _ = connect.decide(try refusal("error-connect-offer-send"), tool: CloudToolName.sendEmail, toolCallID: "c1", conversation: 1, paused: false, at: start)
        XCTAssertNil(connect.finish(try result("toolkit-result-connected-for-send"), conversation: 1), "no tap, no sign-in result")
        XCTAssertTrue(connect.tap(conversation: 1, at: start))
        XCTAssertNil(connect.finish(try result("toolkit-result-connected-for-send"), conversation: 2), "a sign-in started in conversation 1 can't report to 2")
        connect.forget() // End while the sheet was up
        XCTAssertNil(connect.finish(try result("toolkit-result-connected-for-send"), conversation: 1))
        XCTAssertNil(connect.fail(.transport("x"), conversation: 1))
    }

    func testNotNowAndFailuresSayNothingWasDone() throws {
        var connect = ConnectOnAsk()
        _ = connect.decide(try refusal("error-connect-offer-send"), tool: CloudToolName.sendEmail, toolCallID: "c1", conversation: 1, paused: false, at: start)
        let declined = try XCTUnwrap(connect.decline(conversation: 1))
        XCTAssertEqual(declined, "declined: the user chose not to connect Gmail. Nothing was done. Don't ask again unless they do.")
        XCTAssertFalse(connect.tap(conversation: 1, at: start))

        _ = connect.decide(try refusal("error-connect-offer-send"), tool: CloudToolName.sendEmail, toolCallID: "c2", conversation: 1, paused: false, at: start)
        XCTAssertTrue(connect.tap(conversation: 1, at: start))
        let failed = try XCTUnwrap(connect.fail(.server(code: "provider_unavailable", message: "Gmail couldn't be reached.", retryAfterSeconds: nil, receipt: nil), conversation: 1))
        XCTAssertEqual(failed, "failed: Gmail couldn't be connected. Nothing was done. Reason: Gmail couldn't be reached.")

        // No ending ever reads as done in What Doddy did.
        let offer = try XCTUnwrap(try refusal("error-connect-offer-send").connectOffer)
        for ending in [ConnectOnAsk.Ending.connected, .declined, .canceled, .notGranted, .failed("x"), .expired] {
            let line = ConnectOnAsk.ended(ending, offer)
            XCTAssertFalse(VoiceToolReply.donePrefixes.contains { line.hasPrefix($0) }, line)
            XCTAssertTrue(line.contains("Nothing"), line)
        }
    }

    func testASwitchOffersNoSignIn() throws {
        var connect = ConnectOnAsk()
        let offer = ConnectOffer(toolkit: "websearch", tool: "web_search", need: .switchOn, accountTitle: "Web search", toolTitle: "Search the web", permissions: [])
        let error = OnlineAccountsError.server(code: "capability_disabled", message: "off", retryAfterSeconds: nil, receipt: nil, connect: offer)
        guard case .offer(let card, let reply) = connect.decide(error, tool: "web_search", toolCallID: "c1", conversation: 1, paused: false, at: start) else { return XCTFail() }
        XCTAssertEqual(card.title, "Switch on \"Search the web\"?")
        XCTAssertEqual(card.confirmLabel, "Switch on")
        XCTAssertTrue(card.permissions.isEmpty)
        XCTAssertFalse(card.lines.contains { $0.contains("Composio") }, "no sign-in, nobody keeps one")
        XCTAssertFalse(offer.needsSignIn)
        XCTAssertTrue(reply.hasPrefix("switched off:"))
        XCTAssertEqual(ActivityEntry.outcome(of: reply, isLookup: true).0, .notDone)
    }

    func testOpenInMailBuildsOneAddressWithSubjectAndText() {
        XCTAssertEqual(
            OpenLinks.email(address: "anna@example.com", subject: "Running late", body: "Ten minutes, sorry!")?.absoluteString,
            "mailto:anna@example.com?subject=Running%20late&body=Ten%20minutes%2C%20sorry%21")
        for bad in ["anna@example.com?bcc=x@y.com", "anna@example.com,bob@example.com", "anna @example.com", "@example.com", "anna@example", "anna@example.com&cc=x", "anna%40x@y.com", "a@b@c.com", ""] {
            XCTAssertNil(OpenLinks.email(address: bad, subject: "s", body: "b"), bad)
        }
    }

    func testOpenInMailIsOnlyForASendAndEndsTheOfferWithoutSayingSent() throws {
        let send = CloudToolCall(name: CloudToolName.sendEmail, arguments: ["to": .string("anna@example.com"), "subject": .string("Late"), "body": .string("Ten minutes.")])
        XCTAssertEqual(ConnectOnAsk.mailInstead(for: send)?.absoluteString, "mailto:anna@example.com?subject=Late&body=Ten%20minutes%2E")
        XCTAssertNil(ConnectOnAsk.mailInstead(for: CloudToolCall(name: CloudToolName.checkEmail, arguments: [:])))
        XCTAssertNil(ConnectOnAsk.mailInstead(for: CloudToolCall(name: CloudToolName.sendEmail, arguments: ["to": .string("anna@example.com?bcc=x@y.z"), "subject": .string("s"), "body": .string("b")])))

        var connect = ConnectOnAsk()
        _ = connect.decide(try refusal("error-connect-offer-send"), tool: CloudToolName.sendEmail, toolCallID: "c1", conversation: 1, paused: false, at: start)
        let line = try XCTUnwrap(connect.openedMail(conversation: 1))
        XCTAssertTrue(line.hasPrefix("opened: Mail opened"))
        XCTAssertTrue(line.contains("Doddy didn't send it"))
        XCTAssertEqual(ActivityEntry.outcome(of: line, isLookup: false).0, .opened, "logged as opened, never as sent")
        XCTAssertNil(connect.pending)
    }

    // MARK: The sign-in itself

    func testSignInAsksForTheOneToolAndCompletesThroughTheServer() async throws {
        let client = SignInClient(connect: try JSONDecoder().decode(ConnectResponse.self, from: fixture("connect-response-mock")))
        let result = await ConnectFlow.signIn(toolkit: "gmail", forTool: CloudToolName.sendEmail, client: client, authenticator: NeverAuthenticator())
        XCTAssertNoThrow(try result.get())
        let calls = await client.calls
        XCTAssertEqual(calls, ["connect:gmail:send_email", "complete:gmail:mock(approve: true)"], "demo: the tap on the Demo card stands in for the sign-in page")
    }

    func testALiveSignInClosedByTheUserCompletesAsCanceled() async throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("connect-response-mock")) as? [String: Any])
        json["mode"] = "live"
        json["authorizationUrl"] = "https://accounts.example.com/consent"
        let live = try JSONDecoder().decode(ConnectResponse.self, from: JSONSerialization.data(withJSONObject: json))
        let client = SignInClient(connect: live)
        _ = await ConnectFlow.signIn(toolkit: "gmail", forTool: CloudToolName.sendEmail, client: client, authenticator: NeverAuthenticator())
        let calls = await client.calls
        XCTAssertEqual(calls, ["connect:gmail:send_email", "complete:gmail:canceled"], "the server removes what the provider started")
    }
}

/// The sheet was closed without signing in.
private struct NeverAuthenticator: WebAuthenticator {
    func authenticate(url: URL, callbackScheme: String) async throws(WebAuthenticationError) -> URL { throw .canceled }
}

private actor SignInClient: OnlineAccountsClient {
    let connectResponse: ConnectResponse
    private(set) var calls: [String] = []

    init(connect: ConnectResponse) { connectResponse = connect }

    func connect(toolkit: String, forTool: String?) async throws(OnlineAccountsError) -> ConnectResponse {
        calls.append("connect:\(toolkit):\(forTool ?? "-")")
        return connectResponse
    }

    func complete(toolkit: String, _ request: CompleteRequest) async throws(OnlineAccountsError) -> ToolkitResult {
        calls.append("complete:\(toolkit):\(request.result)")
        return try! JSONDecoder().decode(ToolkitResult.self, from: fixture("toolkit-result-connected-for-send"))
    }

    func catalog() async throws(OnlineAccountsError) -> ToolsCatalog { throw .notConfigured }
    func disconnect(toolkit: String) async throws(OnlineAccountsError) -> ToolkitResult { throw .notConfigured }
    func setSwitch(tool: String, enabled: Bool) async throws(OnlineAccountsError) -> ToolkitResult { throw .notConfigured }
    func prepare(_ call: CloudToolCall) async throws(OnlineAccountsError) -> PrepareResult { throw .notConfigured }
    func run(_ call: CloudToolCall, timeZone: String, approvalId: UUID?) async throws(OnlineAccountsError) -> RunResult { throw .notConfigured }
    func receipts() async throws(OnlineAccountsError) -> [OnlineToolReceipt] { throw .notConfigured }
}
