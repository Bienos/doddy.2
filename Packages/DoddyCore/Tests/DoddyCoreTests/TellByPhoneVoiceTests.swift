import XCTest
@testable import DoddyCore

/// Phoning a contact to pass on a message, by voice (decision 2026-11-27-voice-first-doddy, step 4, second part): the
/// model names the person and writes the message, the app reads a callable number from Contacts, the server builds the
/// card, and a tap or the user's own "tak, dzwoń" starts the call.
final class TellByPhoneVoiceTests: XCTestCase {
    private func parse(_ args: [String: Any]) -> VoiceToolRequest {
        let data = try! JSONSerialization.data(withJSONObject: args)
        return VoiceToolRequest.parse(name: VoiceToolName.tellByPhone, parametersJSON: data)
    }

    func testTheModelGivesANameAndAMessageNeverANumber() {
        XCTAssertEqual(parse(["name": "Marek", "message": "Spóźnię się o godzinę"]),
                       .tellByPhone(name: "Marek", message: "Spóźnię się o godzinę"))
        // A number the model adds (from an email, a page, the screen) goes nowhere: the request has no place for it.
        XCTAssertEqual(parse(["name": "Marek", "message": "Cześć, już jadę", "phone": "+48600111222", "number": "600111222"]),
                       .tellByPhone(name: "Marek", message: "Cześć, już jadę"))
        for bad: [String: Any] in [["message": "Cześć, już jadę", "phone": "600111222"], ["name": "  ", "message": "Cześć, już jadę"],
                                   ["name": "Marek"], ["name": "Marek", "message": "ok"]] {
            guard case .invalid = parse(bad) else { return XCTFail("\(bad)") }
        }
    }

    func testTheMessageIsShortCleanAndTextOnly() {
        guard case .invalid = parse(["name": "Marek", "message": String(repeating: "a", count: TellByPhoneVoice.messageMax + 1)]) else {
            return XCTFail("one breath on the phone: too long is refused, never cut")
        }
        XCTAssertEqual(parse(["name": "Marek", "message": String(repeating: "a", count: TellByPhoneVoice.messageMax)]),
                       .tellByPhone(name: "Marek", message: String(repeating: "a", count: TellByPhoneVoice.messageMax)))
        guard case .invalid = parse(["name": "Marek", "message": "Hej\u{202E} jadę"]) else { return XCTFail("a hidden character") }
        guard case .invalid = parse(["name": "Marek", "message": "Powiedz {{doddy_principal}} cześć"]) else { return XCTFail("braces") }
    }

    func testOnlyANumberDoddyMayCallIsPicked() throws {
        let place = try XCTUnwrap(TellByPhoneVoice.place(name: "Marek", phoneNumbers: ["+49 170 1234567", "112", "600 123 456", "22 123 45 67"]))
        XCTAssertEqual(place, CallTaskPlace(name: "Marek", phone: "600 123 456"), "the first Polish number that is allowed")
        XCTAssertNil(TellByPhoneVoice.place(name: "Marek", phoneNumbers: ["+49 170 1234567", "112", "701 234 567"]), "foreign, emergency, premium")
        XCTAssertNil(TellByPhoneVoice.place(name: "Marek", phoneNumbers: []))
        XCTAssertNil(TellByPhoneVoice.place(name: " ", phoneNumbers: ["600123456"]))
        XCTAssertEqual(TellByPhoneVoice.place(name: "Ma{rek}", phoneNumbers: ["600123456"])?.name, "Marek", "no braces reach the server")
    }

    func testTheRequestIsATellCallToOnePersonFromContacts() throws {
        let place = try XCTUnwrap(TellByPhoneVoice.place(name: "Marek", phoneNumbers: ["600 123 456"]))
        let draft = TellByPhoneVoice.draft(place: place, message: "Spóźnię się o godzinę")
        XCTAssertEqual(draft.message, "Spóźnię się o godzinę")
        XCTAssertFalse(draft.textResult, "no text to the user unless asked")
        XCTAssertLessThanOrEqual(draft.goal.count, CallTaskLimits.goalLength)
        // Even with the default source, a message call names Contacts as where the number came from.
        let body = draft.body(principalName: "Anna", source: .places)
        XCTAssertEqual(body.kind, "tell")
        XCTAssertNil(body.question, "the server builds the question")
        XCTAssertNil(body.booking); XCTAssertNil(body.order)
        XCTAssertEqual(body.places.count, 1)
        XCTAssertEqual(body.places[0].source, .contacts)
        XCTAssertEqual(body.places[0].sourceLabel, "Kontakty: Marek")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any]
        XCTAssertEqual(json?["kind"] as? String, "tell")
        XCTAssertEqual(json?["message"] as? String, "Spóźnię się o godzinę")
        XCTAssertNil(json?["question"])
        XCTAssertEqual(json?["textResult"] as? Bool, false)
        // The other kinds are as they were.
        let ask = CallTaskDraft(places: [place], question: "Czy macie stolik?", goal: "stolik", textResult: false).body(principalName: "Anna")
        XCTAssertEqual(ask.kind, "ask")
        XCTAssertNil(ask.message)
        XCTAssertEqual(ask.places[0].source, .places)
    }

    func testTheCallAsksForTheStrongPhraseAndAfterOutsideTextATap() {
        XCTAssertEqual(ConfirmationTiers.tier(for: VoiceToolName.tellByPhone), .strongSpokenYes)
        XCTAssertEqual(ConfirmationTiers.tier(for: VoiceToolName.tellByPhone, outsideContentSeen: true), .tapOnly)
        XCTAssertEqual(ConfirmationTiers.specAsk(for: VoiceToolName.tellByPhone), .strongYesOrTap)
        let request = VoiceToolRequest.tellByPhone(name: "Marek", message: "Spóźnię się o godzinę")
        XCTAssertEqual(ConfirmationTiers.strongAction(for: request, toolName: VoiceToolName.tellByPhone), .call)
        let shown = Date(timeIntervalSince1970: 1_000)
        func runs(_ said: String) -> Bool {
            SpokenConfirmation.runs(said, tier: .strongSpokenYes, cardShownAt: shown, now: shown + 5, action: .call)
        }
        XCTAssertTrue(runs("tak, dzwoń"))
        for said in ["tak", "ok", "tak, zarezerwuj", "tak, zamów", "dzwoń, ale jutro", "nie dzwoń", "dzwoń do Anny"] {
            XCTAssertFalse(runs(said), said)
        }
    }

    func testItAlwaysShowsACardAndIsNeverPlannedDrivenOrLogged() throws {
        let request = VoiceToolRequest.tellByPhone(name: "Marek", message: "Spóźnię się o godzinę")
        XCTAssertEqual(AskFirst.need(for: request), .ownPayloadCard)
        XCTAssertFalse(AskFirst.runsAtOnce(VoiceToolName.tellByPhone))
        let tool = try XCTUnwrap(ToolCatalog.descriptor(VoiceToolName.tellByPhone))
        XCTAssertEqual(tool.effect, .placeCall)
        XCTAssertEqual(tool.approval, .card)
        XCTAssertFalse(tool.planEligible)
        XCTAssertEqual(VoiceConnection.serving(VoiceToolName.tellByPhone), .contacts)
        XCTAssertTrue(ConnectionPause.applies(to: request))
        guard case .refuse = CarProfile.decision(for: request) else { return XCTFail("the card is checked on the iPhone, not while driving") }
        let row = ActivityRequest.describe(request, calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(row?.detail, "to Marek")
        XCTAssertFalse(String(describing: row).contains("godzinę"), "the log keeps who, never what was said")
        // A direct-request grant is for an inquiry to a place only; a message call never gets one.
        var session = RequestedWorkSession()
        session.userSaid("Zadzwoń do Marka i powiedz, że spóźnię się o godzinę", at: Date())
        XCTAssertNil(session.grant(for: request, at: Date()))
    }

    /// One place of a preview as the server sends it; `extra` is what a message call adds.
    private func previewJSON(kind: String, extra: String) -> String {
        """
        {"language":"pl","taskId":"6f1c2c1e-3b6c-4c55-9a39-0d6a1e9f1a10","kind":"\(kind)","digest":"ab","approvableUntil":"2026-11-27T10:00:00Z",
         "textResult":false,"callableNow":true,"places":[{"caseId":"6f1c2c1e-3b6c-4c55-9a39-0d6a1e9f1a11","digest":"cd","approvableUntil":"2026-11-27T10:00:00Z",
         "callee":{"name":"Marek","phone":"600 123 456","destinationKind":"mobile","source":"contacts","sourceLabel":"Kontakty: Marek"},
         "principal":{"name":"Anna","genitive":"Anny"},"goal":"Przekazać wiadomość: Marek","openingLine":"Dzień dobry, tu Doddy.",
         "question":"Mam krótką wiadomość od Anny, mogę przekazać?","facts":[],"forbidden":["Przekazuje tylko tę wiadomość, słowo w słowo, i nic więcej od siebie."],
         "callbackLine":"Sprawdzę to u Anny i oddzwonię.","maxDurationSecs":240,"notice":"off","recordsAudio":false\(extra)}]}
        """
    }

    func testWhatTheServerSendsBackIsDecoded() throws {
        let tell = previewJSON(kind: "tell", extra: ",\"message\":\"Spóźnię się o godzinę\",\"messageLine\":\"Wiadomość od Anny: „Spóźnię się o godzinę.”\"")
        let decoded = try JSONDecoder().decode(CallTaskPreview.self, from: Data(tell.utf8))
        XCTAssertTrue(decoded.isMessage)
        XCTAssertFalse(decoded.isBooking); XCTAssertFalse(decoded.isOrder)
        XCTAssertEqual(decoded.places.first?.message, "Spóźnię się o godzinę")
        XCTAssertEqual(decoded.places.first?.messageLine, "Wiadomość od Anny: „Spóźnię się o godzinę.”")
        XCTAssertEqual(decoded.places.first?.callee.source, .contacts)
        // A preview of any other kind, or from an older server, has no message.
        let plain = try JSONDecoder().decode(CallTaskPreview.self, from: Data(previewJSON(kind: "ask", extra: "").utf8))
        XCTAssertFalse(plain.isMessage)
        XCTAssertNil(plain.places.first?.message)
        let availability = try JSONDecoder().decode(CallCaseAvailability.self, from: Data("""
        {"available":true,"configured":true,"killSwitch":false,"phoneVerified":true,"recordingNotice":"off","recordsAudio":false,
         "maxDurationSecs":300,"agentProblems":[],"booking":true,"order":false,"tell":true}
        """.utf8))
        XCTAssertEqual(availability.tell, true)
        let older = try JSONDecoder().decode(CallCaseAvailability.self, from: Data("""
        {"available":true,"configured":true,"killSwitch":false,"phoneVerified":true,"recordingNotice":"off","recordsAudio":false,
         "maxDurationSecs":300,"agentProblems":[]}
        """.utf8))
        XCTAssertNil(older.tell, "an older server doesn't know message calls")
    }

    func testRepliesNeverClaimMoreThanIsKnown() {
        XCTAssertTrue(VoiceToolReply.callTaskStarted(first: "Marek", count: 1, textResult: false, message: true).hasPrefix("started:"))
        XCTAssertTrue(VoiceToolReply.callTaskStarted(first: "Marek", count: 1, textResult: false, message: true).contains("don't say the message was passed on"))
        XCTAssertTrue(TellByPhoneVoice.off.hasPrefix("not available:"))
        XCTAssertEqual(VoiceToolReply.callTaskRefused(CallCaseError.tellNotConfigured), TellByPhoneVoice.off)
        XCTAssertTrue(TellByPhoneVoice.notFound("Marek").hasPrefix("not found:"))
        XCTAssertTrue(TellByPhoneVoice.noNumber("Marek").contains("don't ask the user for a number"))
        XCTAssertTrue(TellByPhoneVoice.severalContacts(["Marek Nowak", "Marek Kowalski"], query: "Marek").hasPrefix("needs detail:"))
        XCTAssertTrue(TellByPhoneVoice.declined.hasPrefix("declined:"))
    }
}
