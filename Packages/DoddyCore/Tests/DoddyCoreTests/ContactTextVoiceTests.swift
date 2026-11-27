import XCTest
@testable import DoddyCore

/// Texting a contact by voice (decision 2026-11-27-voice-first-doddy, step 4; decision 2026-11-09-texts-to-contacts):
/// the model names the person and writes the text, the app reads the number from Contacts, and a card with the number
/// and exactly the text takes a tap or the user's own yes.
final class ContactTextVoiceTests: XCTestCase {
    private func parse(_ args: [String: Any]) -> VoiceToolRequest {
        let data = try! JSONSerialization.data(withJSONObject: args)
        return VoiceToolRequest.parse(name: VoiceToolName.textContact, parametersJSON: data)
    }

    func testTheModelGivesANameAndTheTextNeverANumber() {
        XCTAssertEqual(parse(["name": "Ania", "text": "Spóźnię się 10 minut"]), .textContact(name: "Ania", body: "Spóźnię się 10 minut"))
        // A number the model adds (from an email, a page, the screen) goes nowhere: the request has no place for it.
        XCTAssertEqual(parse(["name": "Ania", "text": "Hej", "phone": "+48600111222", "number": "600111222"]),
                       .textContact(name: "Ania", body: "Hej"))
        guard case .invalid = parse(["text": "Hej", "phone": "+48600111222"]) else { return XCTFail("a number alone is no contact") }
        guard case .invalid = parse(["name": "  ", "text": "Hej"]) else { return XCTFail("no name") }
        guard case .invalid = parse(["name": "Ania"]) else { return XCTFail("no text") }
    }

    func testTheTextIsSentExactlyAsWrittenOrRefused() {
        // Nothing trimmed: the card shows it and the approval covers it.
        XCTAssertEqual(parse(["name": "Ania", "text": " Hej "]), .textContact(name: "Ania", body: " Hej "))
        guard case .invalid = parse(["name": "Ania", "text": String(repeating: "a", count: ApprovedTextLimits.maxLength + 1)]) else {
            return XCTFail("too long is refused, never cut")
        }
        guard case .invalid = parse(["name": "Ania", "text": "Hej\u{202E}"]) else { return XCTFail("a hidden character would be sent unseen") }
        guard case .invalid = parse(["name": "Ania", "text": " \n"]) else { return XCTFail("empty") }
    }

    func testTheNumberComesFromTheContactCard() throws {
        let number = try XCTUnwrap(ContactTextVoice.number(name: "Ania", phoneNumbers: ["*100#", "600 123 456", "+48 500 100 200"]))
        XCTAssertEqual(number.e164, "+48600123456", "the first number that can take a text")
        XCTAssertEqual(number.name, "Ania")
        XCTAssertNil(ContactTextVoice.number(name: "Ania", phoneNumbers: ["*100#", "112"]))
        XCTAssertNil(ContactTextVoice.number(name: "Ania", phoneNumbers: []))
    }

    func testTheCardShowsWhoTheNumberAndExactlyTheText() throws {
        let number = try XCTUnwrap(ContactText.ContactNumber(contactName: "Ania", raw: "600 123 456"))
        let card = ContactTextVoice.card(to: number, body: "Spóźnię się 10 minut", polish: true)
        XCTAssertEqual(card.title, "Wysłać SMS do: Ania?")
        XCTAssertEqual(card.lines.first, "+48600123456")
        XCTAssertTrue(card.lines.contains("„Spóźnię się 10 minut”"))
        XCTAssertTrue(card.lines.contains { $0.contains("nie dotrze") }, "a reply won't reach the user")
        XCTAssertEqual(card.confirmLabel, "Wyślij")
        XCTAssertEqual(ContactTextVoice.card(to: number, body: "Hi", polish: false).title, "Text Ania?")
    }

    func testItAlwaysShowsACardAndAYesOrATapSendsIt() {
        let request = VoiceToolRequest.textContact(name: "Ania", body: "Hej")
        XCTAssertEqual(AskFirst.need(for: request), .ownPayloadCard)
        XCTAssertFalse(AskFirst.runsAtOnce(VoiceToolName.textContact))
        XCTAssertEqual(ConfirmationTiers.tier(for: VoiceToolName.textContact), .spokenYes)
        XCTAssertEqual(ConfirmationTiers.specAsk(for: VoiceToolName.textContact), .yesOrTap)
        let tool = ToolCatalog.descriptor(VoiceToolName.textContact)
        XCTAssertEqual(tool?.effect, .sendText)
        XCTAssertEqual(tool?.approval, .card)
        XCTAssertEqual(tool?.planEligible, false, "a plan card doesn't show the number and the exact text")
        XCTAssertEqual(VoiceConnection.serving(VoiceToolName.textContact), .contacts)
        XCTAssertTrue(ConnectionPause.applies(to: request))
        guard case .refuse = CarProfile.decision(for: request) else { return XCTFail("the card is checked on the iPhone, not while driving") }
    }

    func testTheLogKeepsWhoNeverTheTextOrNumber() {
        let row = ActivityRequest.describe(.textContact(name: "Ania", body: "Kod do drzwi 4417"), calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(row?.detail, "to Ania")
        XCTAssertFalse(String(describing: row).contains("4417"))
    }

    func testRepliesNeverClaimMoreThanIsKnown() {
        XCTAssertTrue(ContactTextVoice.result(nil, to: "Ania").hasPrefix("queued:"))
        XCTAssertTrue(ContactTextVoice.unknown.hasPrefix("unknown:"))
        XCTAssertTrue(ContactTextVoice.notFound("Ania").hasPrefix("not found:"))
        XCTAssertTrue(ContactTextVoice.sentMomentsAgo.hasPrefix("failed:"))
        XCTAssertTrue(ContactTextVoice.noNumber("Ania").contains("don't ask the user for a number"))
        XCTAssertTrue(ContactTextVoice.refused("contact_texts_off").hasPrefix("not available:"))
        XCTAssertTrue(ContactTextVoice.refused("contact_texts_off").contains("draft_message"))
        for code in ["phone_not_verified", "contact_opted_out", "approval_mismatch", "daily_limit", "something_new"] {
            XCTAssertTrue(ContactTextVoice.refused(code).hasPrefix("failed: nothing was sent"), code)
        }
        XCTAssertTrue(ContactTextVoice.severalContacts(["Anna Nowak", "Anna Kowalska"], query: "Anna").hasPrefix("needs detail:"))
    }

    // MARK: The server route

    private func reply(_ status: Int, _ json: String = "") -> Result<ServerResponse, any Error> {
        .success(ServerResponse(status: status, body: Data(json.utf8)))
    }

    private struct Sent: Decodable { let body: String; let approvalHash: String; let idempotencyKey: String; let to: String? }

    private let queued = #"{"messages":[{"id":"6f1c2c1e-3b6c-4c55-9a39-0d6a1e9f1a10","channel":"sms","state":"queued"}]}"#

    func testATextToAContactGoesToItsOwnRouteWithTheNumberTheCardShowed() async throws {
        let transport = StepTransport([reply(202, queued), reply(202, queued)])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        let number = try XCTUnwrap(ContactText.ContactNumber(contactName: "Ania", raw: "600 123 456"))
        let hash = ContactText.approvalHash(to: number, body: "Spóźnię się")
        let outcome = try await client.sendApprovedText("Spóźnię się", approvalHash: hash, to: number.e164)
        guard case .queued = outcome else { return XCTFail("\(outcome)") }
        _ = try await client.sendApprovedText("Kup mleko", approvalHash: ApprovalHash.text(to: "+48500100200", body: "Kup mleko"))
        let requests = await transport.sent
        XCTAssertEqual(requests.map(\.path), ["/v1/texts/contact", "/v1/texts"])
        let bodies = try requests.compactMap { try $0.body.map { try JSONDecoder().decode(Sent.self, from: $0) } }
        XCTAssertEqual(bodies.first?.to, "+48600123456")
        XCTAssertEqual(bodies.first?.approvalHash, hash)
        XCTAssertNil(bodies.last?.to, "a text to the user's own number names no recipient")
    }

    func testTextsToContactsSwitchedOffOnTheServerSendNothing() async throws {
        let transport = StepTransport([reply(503, #"{"error":"contact_texts_off"}"#), reply(409, #"{"error":"contact_opted_out"}"#)])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        let hash = ApprovalHash.text(to: "+48600123456", body: "Hej")
        let off = try await client.sendApprovedText("Hej", approvalHash: hash, to: "+48600123456")
        XCTAssertEqual(off, .refused("contact_texts_off"))
        let stop = try await client.sendApprovedText("Hej", approvalHash: hash, to: "+48600123456")
        XCTAssertEqual(stop, .refused("contact_opted_out"))
    }
}
