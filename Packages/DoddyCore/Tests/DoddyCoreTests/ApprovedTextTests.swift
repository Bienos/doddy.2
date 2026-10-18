import Foundation
import XCTest
@testable import DoddyCore

/// Texts from Doddy's number to the user's own number, approved on a card (ADR-490 unit U2).
final class ApprovedTextTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    // MARK: The approval hash

    private struct Vectors: Decodable {
        struct Vector: Decodable { let description: String; let fields: [String]; let sha256: String }
        let format: String
        let vectors: [Vector]
    }

    func testTheHashMatchesEveryVectorTheServerAlsoChecks() throws {
        // The same file is checked by server/messaging (test/unit.test.ts), so the iPhone and the
        // server agree on every byte, Polish letters and decomposed accents included.
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("contracts/phone/approval-vectors.json"))
        let file = try JSONDecoder().decode(Vectors.self, from: data)
        XCTAssertEqual(file.format, "doddy-approval-vectors/1")
        XCTAssertGreaterThanOrEqual(file.vectors.count, 8)
        for vector in file.vectors {
            XCTAssertEqual(ApprovalHash.hex(vector.fields), vector.sha256, vector.description)
        }
    }

    func testATextApprovalIsTheVersionTheKindTheNumberAndTheText() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("contracts/phone/approval-vectors.json"))
        let first = try XCTUnwrap(try JSONDecoder().decode(Vectors.self, from: data).vectors.first)
        XCTAssertEqual(first.fields[0], ApprovalHash.version)
        XCTAssertEqual(first.fields[1], "text")
        XCTAssertEqual(ApprovalHash.text(to: first.fields[2], body: first.fields[3]), first.sha256)
    }

    func testNothingIsTrimmedOrNormalised() {
        let to = "+48500100200"
        XCTAssertNotEqual(ApprovalHash.text(to: to, body: "Call mum"), ApprovalHash.text(to: to, body: "Call mum "))
        XCTAssertNotEqual(ApprovalHash.text(to: to, body: "Caf\u{E9}"), ApprovalHash.text(to: to, body: "Cafe\u{301}"))
        XCTAssertNotEqual(ApprovalHash.text(to: to, body: "Hi"), ApprovalHash.text(to: "+48500100201", body: "Hi"))
        // Moving a character between fields changes the hash: the length prefixes keep them apart.
        XCTAssertNotEqual(ApprovalHash.hex(["ab", "c"]), ApprovalHash.hex(["a", "bc"]))
        XCTAssertEqual(ApprovalHash.text(to: to, body: "x").count, 64)
    }

    func testTheDraftHashesExactlyWhatTheCardShows() {
        let draft = ApprovedTextDraft(body: "Kup mleko ", to: "+48500100200")
        XCTAssertEqual(draft.approvalHash, ApprovalHash.text(to: "+48500100200", body: "Kup mleko "))
        XCTAssertEqual(draft.recipientEnding, "200")
    }

    // MARK: Parsing text_me

    private func parse(_ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: VoiceToolName.textMe, parametersJSON: Data(json.utf8))
    }

    func testTheBodyIsKeptExactly() {
        XCTAssertEqual(parse(#"{"body": "  Parcel code 4417\n📦 "}"#), .textMe(body: "  Parcel code 4417\n📦 "))
    }

    func testAMissingOrBlankBodyIsRefused() {
        for json in [#"{}"#, #"{"body": ""}"#, #"{"body": "   \n"}"#, #"{"body": 5}"#] {
            guard case .invalid(let name, _) = parse(json) else { return XCTFail(json) }
            XCTAssertEqual(name, VoiceToolName.textMe)
        }
    }

    func testHiddenCharactersAreRefused() throws {
        // A right-to-left override, a zero-width space, a bell: the card couldn't show them.
        for hidden in ["Pay \u{202E}001\u{202C} zl", "Code\u{200B}4417", "Hi\u{7}", "a\u{FEFF}b", "x\u{2066}y"] {
            guard case .invalid(_, let reason) = parse(try json(hidden)) else { return XCTFail(hidden.debugDescription) }
            XCTAssertTrue(reason.contains("hidden character"), reason)
        }
        // New lines and tabs are layout; joiners and tags build emoji; all are kept as they are.
        for visible in ["Line one\nLine two\tend", "👨‍👩‍👧 family", "🏴󠁧󠁢󠁳󠁣󠁴󠁿 flag", "Zażółć ❤️"] {
            XCTAssertEqual(parse(try json(visible)), .textMe(body: visible), visible)
        }
    }

    func testTooLongIsRefusedNeverCut() throws {
        let limit = ApprovedTextLimits.maxLength
        let fits = String(repeating: "a", count: limit)
        XCTAssertEqual(parse(try json(fits)), .textMe(body: fits))
        guard case .invalid(_, let reason) = parse(try json(fits + "a")) else { return XCTFail("one over the limit") }
        XCTAssertTrue(reason.contains("\(limit)"), reason)
        // Counted as the server counts: an emoji is two UTF-16 units.
        let emoji = String(repeating: "📦", count: limit / 2)
        XCTAssertEqual(parse(try json(emoji)), .textMe(body: emoji))
        guard case .invalid = parse(try json(emoji + "a")) else { return XCTFail("emoji over the limit") }
    }

    private func json(_ body: String) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["body": body]), as: UTF8.self)
    }

    func testTheLimitMatchesTheRulesFile() throws {
        // docs/trust/config/doddy_rules.yaml is the written rule; the server's test checks the
        // same lines against its own constants.
        let rules = try String(contentsOf: repoRoot.appendingPathComponent("docs/trust/config/doddy_rules.yaml"), encoding: .utf8)
        XCTAssertTrue(rules.contains("text_max_length: \(ApprovedTextLimits.maxLength)"))
        XCTAssertTrue(rules.contains("approved_texts_per_day: \(ContactCaps.approvedTextsPerDay)"))
    }

    // MARK: Where it runs

    func testItNeedsACardAndIsNeverAPlanStep() throws {
        let tool = try XCTUnwrap(ToolCatalog.descriptor(VoiceToolName.textMe))
        XCTAssertEqual(tool.effect, .sendText)
        XCTAssertEqual(tool.approval, .card)
        XCTAssertEqual(tool.runsOn, .phone)
        XCTAssertFalse(tool.planEligible, "a plan card doesn't show the exact text with its own approval")
        XCTAssertFalse(tool.isCloud)
        XCTAssertEqual(ToolCatalog.all.filter { $0.effect == .sendText }.map(\.name), [VoiceToolName.textMe])
    }

    func testNotWhileDrivingNotWhilePausedNotInTranslatorMode() {
        let request = VoiceToolRequest.textMe(body: "Hi")
        guard case .refuse = CarProfile.decision(for: request) else { return XCTFail("car") }
        XCTAssertTrue(ConnectionPause.applies(to: request))
        XCTAssertEqual(
            ToolGate.decide(toolName: VoiceToolName.textMe, request: request, translatorOn: false, pauseAll: true, isOn: { _ in true }),
            .paused)
        XCTAssertEqual(
            ToolGate.decide(toolName: VoiceToolName.textMe, request: request, translatorOn: true, pauseAll: false, isOn: { _ in true }),
            .translatorRefused)
    }

    // MARK: Readiness

    func testOnlyAVerifiedConsentingNumberIsReady() {
        XCTAssertEqual(TextReadiness(PhoneStatus(phone: "+48500100200", smsEnabled: true, optedOut: false)), .ready(to: "+48500100200"))
        XCTAssertEqual(TextReadiness(.none), .noPhone)
        XCTAssertEqual(TextReadiness(PhoneStatus(phone: "+48500100200", smsEnabled: false, optedOut: false)), .textsOff)
        XCTAssertEqual(TextReadiness(PhoneStatus(phone: "+48500100200", smsEnabled: true, optedOut: true)), .optedOut)
        for readiness in [TextReadiness.noPhone, .textsOff, .optedOut] {
            let reply = VoiceToolReply.textNotReady(readiness)
            XCTAssertTrue(reply.hasPrefix("failed:") && reply.hasSuffix("Nothing was sent."), reply)
        }
    }

    // MARK: Replies

    private func status(_ state: String, delivery: String? = nil, error: String? = nil, lookup: String? = nil) -> UpdateStatus {
        UpdateStatus(id: UUID(), channel: .sms, state: state, deliveryStatus: delivery, errorCode: error, lookup: lookup)
    }

    func testOnlyACarrierReportCountsAsDone() {
        let delivered = VoiceToolReply.textResult(status("sent", delivery: "delivered"))
        XCTAssertTrue(delivered.hasPrefix("delivered:"))
        XCTAssertEqual(ActivityEntry.outcome(of: delivered, isLookup: false).0, .done)

        for reply in [
            VoiceToolReply.textResult(status("sent")),
            VoiceToolReply.textResult(status("sent", delivery: "sent")),
            VoiceToolReply.textResult(status("queued")),
            VoiceToolReply.textResult(status("sending")),
            VoiceToolReply.textResult(nil),
            VoiceToolReply.textResult(status("unknown")),
            VoiceToolReply.textUnknown,
        ] {
            XCTAssertEqual(ActivityEntry.outcome(of: reply, isLookup: false).0, .notSure, reply)
            // Everything that reads results as done (the plan summary, the agent's rules) agrees.
            XCTAssertFalse(VoiceToolReply.donePrefixes.contains { reply.hasPrefix($0) }, reply)
            XCTAssertTrue(reply.contains("Don't say it") || reply.contains("don't say it"), reply)
        }
    }

    func testFailuresSayNothingWasSent() {
        for reply in [
            VoiceToolReply.textResult(status("failed", error: "twilio_21610")),
            VoiceToolReply.textResult(status("failed", error: "approval_mismatch")),
            VoiceToolReply.textResult(status("failed")),
            VoiceToolReply.textResult(status("cancelled")),
            VoiceToolReply.textRefused("approval_mismatch"),
            VoiceToolReply.textRefused("daily_limit"),
            VoiceToolReply.textRefused("something_new"),
            VoiceToolReply.textNoServer,
            VoiceToolReply.textOffline,
        ] {
            XCTAssertTrue(reply.hasPrefix("failed:"), reply)
            XCTAssertEqual(ActivityEntry.outcome(of: reply, isLookup: false).0, .notDone, reply)
        }
        XCTAssertTrue(VoiceToolReply.textResult(status("failed", error: "twilio_21610")).contains("STOP"))
        XCTAssertTrue(VoiceToolReply.textRefused("daily_limit").contains("\(ContactCaps.approvedTextsPerDay)"))
        // Twilio took it but the carrier didn't deliver: not "nothing was sent", but not done either.
        let undelivered = VoiceToolReply.textResult(status("sent", delivery: "undelivered"))
        XCTAssertEqual(ActivityEntry.outcome(of: undelivered, isLookup: false).0, .notDone)
    }

    func testDecliningSendsNothing() {
        XCTAssertEqual(ActivityEntry.outcome(of: VoiceToolReply.textDeclined, isLookup: false).0, .declined)
    }

    func testTheLogKeepsNoneOfTheText() throws {
        let request = try XCTUnwrap(ActivityRequest.describe(.textMe(body: "Kod do paczkomatu 4417"), calendar: .current))
        XCTAssertEqual(request.app, .messages)
        XCTAssertNil(request.detail)
        XCTAssertNil(request.logDetail)
        XCTAssertFalse(request.isLookup)
    }

    // MARK: Status wording

    func testAnUnknownTextSaysWhatTheLookupFound() {
        XCTAssertTrue(status("unknown").userFacingText.contains("checking Twilio"))
        XCTAssertTrue(status("unknown", lookup: "not_found").userFacingText.contains("most likely wasn't sent"))
        XCTAssertTrue(status("unknown", lookup: "failed").userFacingText.contains("couldn't check"))
        for text in [status("unknown").userFacingText, status("unknown", lookup: "not_found").userFacingText] {
            XCTAssertTrue(text.contains("won't resend"), text)
        }
    }

    func testTheStatusReadsTheLookupField() throws {
        let json = #"{"id":"6f1c2c1e-3b6c-4c55-9a39-0d6a1e9f1a10","channel":"sms","state":"unknown","sendAt":"2026-10-18T10:00:00.000Z","deliveryStatus":null,"errorCode":"twilio_500","lookup":"not_found"}"#
        let decoded = try JSONDecoder().decode(UpdateStatus.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.lookup, "not_found")
        let older = #"{"id":"6f1c2c1e-3b6c-4c55-9a39-0d6a1e9f1a10","channel":"sms","state":"sent"}"#
        XCTAssertNil(try JSONDecoder().decode(UpdateStatus.self, from: Data(older.utf8)).lookup)
    }

    // MARK: Segments

    func testSegments() {
        XCTAssertEqual(SMSSegments.encoding("Buy milk"), .gsm7)
        XCTAssertEqual(SMSSegments.count(String(repeating: "a", count: 160)), 1)
        XCTAssertEqual(SMSSegments.count(String(repeating: "a", count: 161)), 2)
        XCTAssertEqual(SMSSegments.count(String(repeating: "a", count: 306)), 2)
        XCTAssertEqual(SMSSegments.count(String(repeating: "a", count: 307)), 3)
        // An extension character takes two places.
        XCTAssertEqual(SMSSegments.count(String(repeating: "€", count: 80)), 1)
        XCTAssertEqual(SMSSegments.count(String(repeating: "€", count: 81)), 2)
        // Polish letters aren't GSM-7, and Smart Encoding is off, so the whole text is UCS-2.
        XCTAssertEqual(SMSSegments.encoding("Zażółć"), .ucs2)
        XCTAssertEqual(SMSSegments.count(String(repeating: "ż", count: 70)), 1)
        XCTAssertEqual(SMSSegments.count(String(repeating: "ż", count: 71)), 2)
        XCTAssertEqual(SMSSegments.count(String(repeating: "ż", count: 134)), 2)
        XCTAssertEqual(SMSSegments.count(String(repeating: "ż", count: 135)), 3)
        XCTAssertEqual(SMSSegments.count("📦"), 1)
    }

    // MARK: Sending

    private func reply(_ status: Int, _ json: String = "") -> Result<ServerResponse, any Error> {
        .success(ServerResponse(status: status, body: Data(json.utf8)))
    }

    private struct SentText: Decodable { let body: String; let approvalHash: String; let idempotencyKey: String }

    private func sentTexts(_ transport: StepTransport) async throws -> [SentText] {
        try await transport.sent.compactMap { request in
            try request.body.map { try JSONDecoder().decode(SentText.self, from: $0) }
        }
    }

    private let queued = #"{"messages":[{"id":"6f1c2c1e-3b6c-4c55-9a39-0d6a1e9f1a10","channel":"sms","state":"queued"}]}"#

    func testAnApprovedTextIsPostedWithItsHash() async throws {
        let transport = StepTransport([reply(202, queued)])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        let draft = ApprovedTextDraft(body: "Kup mleko", to: "+48500100200")
        let outcome = try await client.sendApprovedText(draft.body, approvalHash: draft.approvalHash)
        guard case .queued(let text) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(text.state, "queued")
        let sent = await transport.sent
        XCTAssertEqual(sent.map(\.path), ["/v1/texts"])
        XCTAssertEqual(sent.first?.method, .post)
        let body = try await sentTexts(transport)
        XCTAssertEqual(body.first?.body, "Kup mleko")
        XCTAssertEqual(body.first?.approvalHash, draft.approvalHash)
    }

    func testAnUnansweredTextIsUnknownAndATryAgainReusesItsKey() async throws {
        // The first request may have reached the server. Trying the same approval again sends the
        // same key, so the server answers with the first text instead of queueing a second.
        let transport = StepTransport([.failure(URLError(.timedOut)), reply(202, queued)])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        let hash = ApprovalHash.text(to: "+48500100200", body: "Hi")
        let first = try await client.sendApprovedText("Hi", approvalHash: hash)
        XCTAssertEqual(first, .unknown)
        _ = try await client.sendApprovedText("Hi", approvalHash: hash)
        let keys = try await sentTexts(transport).map(\.idempotencyKey)
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys[0], keys[1])
    }

    func testTheAppsOwnOfflineErrorIsUnknownToo() async throws {
        // The app's transport reports every URLSession failure as `.offline`, timeouts included.
        let transport = StepTransport([.failure(ServerError.offline)])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        let outcome = try await client.sendApprovedText("Hi", approvalHash: ApprovalHash.text(to: "+48500100200", body: "Hi"))
        XCTAssertEqual(outcome, .unknown)
    }

    func testAfterAnAnswerTheSameWordsApprovedAgainAreANewText() async throws {
        let transport = StepTransport([reply(202, queued), reply(202, queued)])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        let hash = ApprovalHash.text(to: "+48500100200", body: "Water the plants")
        _ = try await client.sendApprovedText("Water the plants", approvalHash: hash)
        _ = try await client.sendApprovedText("Water the plants", approvalHash: hash)
        let keys = try await sentTexts(transport).map(\.idempotencyKey)
        XCTAssertNotEqual(keys[0], keys[1])
    }

    func testARefusalAfterAnUnknownTryKeepsTheKey() async throws {
        // The hourly limit and "texts off" are answered before the server looks for a repeat of
        // the key, so after them the first, unanswered try may still be queued: same key again.
        let transport = StepTransport([
            .failure(URLError(.timedOut)), reply(429, #"{"statusCode":429}"#), reply(409, #"{"error":"sms_not_enabled"}"#), reply(202, queued),
        ])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        let hash = ApprovalHash.text(to: "+48500100200", body: "Hi")
        var outcomes: [ApprovedTextOutcome] = []
        for _ in 0..<4 { outcomes.append(try await client.sendApprovedText("Hi", approvalHash: hash)) }
        XCTAssertEqual(outcomes.prefix(3), [.unknown, .refused("rate_limited"), .refused("sms_not_enabled")])
        let keys = try await sentTexts(transport).map(\.idempotencyKey)
        XCTAssertEqual(keys.count, 4)
        XCTAssertEqual(Set(keys).count, 1)
    }

    func testRefusalsCarryTheServersReason() async throws {
        let transport = StepTransport([
            reply(409, #"{"error":"approval_mismatch"}"#),
            reply(409, #"{"error":"sms_not_enabled"}"#),
            reply(429, #"{"error":"daily_limit"}"#),
            reply(429, #"{"statusCode":429,"message":"Rate limit exceeded"}"#),
            reply(503, #"{"error":"sms_not_configured"}"#),
            reply(400, #"{"error":"invalid_request","fields":["body"]}"#),
        ])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        var outcomes: [ApprovedTextOutcome] = []
        for _ in 0..<6 {
            outcomes.append(try await client.sendApprovedText("Hi", approvalHash: ApprovalHash.text(to: "+48500100200", body: "Hi")))
        }
        XCTAssertEqual(outcomes, [
            .refused("approval_mismatch"), .refused("sms_not_enabled"), .refused("daily_limit"),
            .refused("rate_limited"), .refused("sms_not_configured"), .refused("invalid"),
        ])
    }

    func testAServerErrorIsUnknownAndKeepsTheKey() async throws {
        // A 500 from the server, or the hosting proxy's 502, 503 or 504, can come after the text
        // was queued, so none of them is "not sent".
        let transport = StepTransport([
            reply(500), reply(502, "<html>Bad gateway</html>"), reply(503, "Service Unavailable"), reply(504), reply(202, queued),
        ])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        let hash = ApprovalHash.text(to: "+48500100200", body: "Hi")
        for _ in 0..<4 {
            let outcome = try await client.sendApprovedText("Hi", approvalHash: hash)
            XCTAssertEqual(outcome, .unknown)
        }
        _ = try await client.sendApprovedText("Hi", approvalHash: hash)
        let keys = try await sentTexts(transport).map(\.idempotencyKey)
        XCTAssertEqual(keys.count, 5)
        XCTAssertEqual(Set(keys).count, 1)
    }

    func testAnAnswerTheServerNeverGivesIsAnError() async {
        let transport = StepTransport([reply(404, #"{"error":"not_found"}"#)])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        do {
            _ = try await client.sendApprovedText("Hi", approvalHash: ApprovalHash.text(to: "+48500100200", body: "Hi"))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ServerError, .unexpected(status: 404))
            XCTAssertTrue(VoiceToolReply.textNotSent(error as? ServerError).hasSuffix("Nothing was sent."))
        }
        XCTAssertEqual(VoiceToolReply.textNotSent(.offline), VoiceToolReply.textOffline)
        XCTAssertEqual(VoiceToolReply.textCheckFailed(.offline), VoiceToolReply.textOffline)
        XCTAssertEqual(VoiceToolReply.textCheckFailed(.accountMissing), VoiceToolReply.textNotReady(.noPhone))
    }
}
