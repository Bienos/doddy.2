@testable import DoddyCore
import XCTest

final class CallCaseTests: XCTestCase {
    private let pesel = "44051401359"

    // MARK: Brief

    func testOnlyTickedFactsLeaveThePhone() throws {
        var draft = CallBriefDraft(calleeName: "Serwis Laptop", phone: "22 123 45 67", source: .contacts, sourceLabel: "Serwis",
                                   principalName: "Anna", goal: "Sprawdzić laptop.", question: "Czy laptop jest gotowy?")
        draft.facts = [
            CallFactDraft(kind: .reference, text: "Zlecenie 12345", ticked: true),
            CallFactDraft(kind: .pesel, text: pesel, ticked: false),
            CallFactDraft(kind: .address, text: "ul. Prosta 1", ticked: false),
        ]
        let body = draft.requestBody()
        XCTAssertEqual(body.facts, [.init(kind: .reference, text: "Zlecenie 12345")])
        let json = String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
        XCTAssertFalse(json.contains(pesel))
        XCTAssertFalse(json.contains("Prosta"))
        XCTAssertTrue(json.contains("\"kind\":\"ask\""))
        XCTAssertEqual(body.principal.genitive, "Anny")
        XCTAssertEqual(draft.problems, [])
    }

    func testSensitiveFactsAreRecognisedAndLeftUnticked() {
        XCTAssertEqual(CallFactDraft.suggested("PESEL \(pesel)").kind, .pesel)
        XCTAssertFalse(CallFactDraft.suggested("PESEL \(pesel)").ticked)
        XCTAssertEqual(CallFactDraft.suggested("Odbiór: ul. Prosta 1, 00-950 Warszawa").kind, .address)
        XCTAssertTrue(CallFactDraft.suggested("Zlecenie 12345").ticked)

        var draft = CallBriefDraft(calleeName: "S", phone: "600 100 200", principalName: "Jan", goal: "Cel rozmowy", question: "Czy jest gotowe?")
        let wrongKind = CallFactDraft(kind: .general, text: "PESEL \(pesel)", ticked: true)
        draft.facts = [wrongKind]
        XCTAssertEqual(draft.problems, [.sensitiveFactKind(wrongKind.id)])
        let badPesel = CallFactDraft(kind: .pesel, text: "12345", ticked: true)
        draft.facts = [badPesel]
        XCTAssertEqual(draft.problems, [.peselFactInvalid(badPesel.id)])
    }

    func testBriefProblems() {
        let draft = CallBriefDraft(calleeName: " ", phone: "112", principalName: "", goal: "", question: "Hm {x}")
        let problems = draft.problems
        XCTAssertTrue(problems.contains(.missingCalleeName))
        XCTAssertTrue(problems.contains(.numberNotAllowed(.shortNumber)))
        XCTAssertTrue(problems.contains(.missingPrincipal))
        XCTAssertTrue(problems.contains(.braces))
    }

    // MARK: Rules mirrored from the server

    func testNumbersMatchTheServerAllowlist() {
        XCTAssertEqual(PolishNumber.classify("+48 600 100 200"), .allowed(e164: "+48600100200", kind: .mobile))
        XCTAssertEqual(PolishNumber.classify("22 123 45 67"), .allowed(e164: "+48221234567", kind: .geographic))
        XCTAssertEqual(PolishNumber.classify("800 123 456"), .allowed(e164: "+48800123456", kind: .freephone))
        for n in ["112", "+48 112", "997", "999", "116111", "118913", "0112"] { XCTAssertEqual(PolishNumber.classify(n), .refused(.shortNumber), n) }
        XCTAssertEqual(PolishNumber.classify("700 123 456"), .refused(.premium))
        XCTAssertEqual(PolishNumber.classify("801 123 456"), .refused(.sharedCost))
        XCTAssertEqual(PolishNumber.classify("+44 20 7946 0000"), .refused(.foreign))
        XCTAssertEqual(PolishNumber.classify("391234567"), .refused(.special))
        XCTAssertEqual(PolishNumber.classify("abc"), .refused(.notANumber))
        for p in 10...99 {
            let allowed = PolishNumber.mobilePrefixes.contains("\(p)") || PolishNumber.geographicPrefixes.contains("\(p)")
            if case .allowed = PolishNumber.classify("+48\(p)1234567") { XCTAssertTrue(allowed, "\(p)") } else { XCTAssertFalse(allowed, "\(p)") }
        }
    }

    func testPESELChecksum() {
        XCTAssertTrue(CallFactRules.isPESEL(pesel))
        XCTAssertFalse(CallFactRules.isPESEL("44051401358"))
        XCTAssertTrue(CallFactRules.containsPESEL("nr \(pesel)."))
        XCTAssertEqual(CallFactRules.digitGroups("4111 1111-1111 1111 i 12"), ["4111111111111111", "12"])
    }

    func testGenitiveSuggestions() {
        let cases = ["Anna": "Anny", "Maria": "Marii", "Maja": "Mai", "Monika": "Moniki", "Olga": "Olgi", "Patryk": "Patryka",
                     "Marek": "Marka", "Paweł": "Pawła", "Antoni": "Antoniego", "Jerzy": "Jerzego", "Jan": "Jana", "Anna Nowak": "Anny"]
        for (name, genitive) in cases { XCTAssertEqual(PolishGenitive.suggest(name), genitive, name) }
    }

    func testCallingHoursAcrossTheChangeToWinterTime() {
        let iso = ISO8601DateFormatter()
        XCTAssertFalse(CallHours.fits(iso.date(from: "2026-10-24T05:59:59Z")!, maxDurationSecs: 240))
        XCTAssertTrue(CallHours.fits(iso.date(from: "2026-10-24T06:00:00Z")!, maxDurationSecs: 240))
        XCTAssertFalse(CallHours.fits(iso.date(from: "2026-10-25T06:30:00Z")!, maxDurationSecs: 240))
        XCTAssertTrue(CallHours.fits(iso.date(from: "2026-10-25T07:00:00Z")!, maxDurationSecs: 240))
        XCTAssertTrue(CallHours.fits(iso.date(from: "2026-10-24T17:55:15Z")!, maxDurationSecs: 240))
        XCTAssertFalse(CallHours.fits(iso.date(from: "2026-10-24T17:55:16Z")!, maxDurationSecs: 240))
    }

    func testRetrySuggestionsAllFitTheHours() {
        let now = ISO8601DateFormatter().date(from: "2026-10-19T17:30:00Z")! // 19:30 Warsaw
        let slots = CallHours.retrySuggestions(after: now, maxDurationSecs: 240)
        XCTAssertEqual(slots.count, 4)
        XCTAssertTrue(slots.allSatisfy { CallHours.fits($0, maxDurationSecs: 240) && $0 > now })
        XCTAssertEqual(slots, slots.sorted())
        let hour = CallHours.warsaw.component(.hour, from: slots[0])
        XCTAssertEqual(hour, 9, "too late today, so the first is tomorrow 9:00")
    }

    // MARK: Server types and client

    static let previewJSON = """
    {"caseId":"3ff77017-4163-417c-ae47-958d3dfdf213","digest":"\(String(repeating: "a", count: 64))","approvableUntil":"2026-10-19T09:30:00.000Z",
     "callee":{"name":"Serwis Laptop","phone":"22 123 45 67","destinationKind":"geographic","source":"contacts","sourceLabel":"Serwis"},
     "principal":{"name":"Anna","genitive":"Anny"},"goal":"Sprawdzić laptop.",
     "openingLine":"Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu Anny. Chciałbym zapytać: Czy laptop jest gotowy?",
     "question":"Czy laptop jest gotowy?","facts":[{"kind":"reference","text":"Zlecenie 12345"}],
     "forbidden":["Nie płaci i nie podaje danych do płatności."],"callbackLine":"Sprawdzę to u Anny i oddzwonię.",
     "maxDurationSecs":240,"notice":"off","recordsAudio":false,"callableNow":true}
    """

    func testCreateSendsTheBodyAndDecodesThePreview() async throws {
        let transport = Scripted([ServerResponse(status: 201, body: Data(Self.previewJSON.utf8))])
        let client = DoddyServerClient(transport: transport, credentials: Credentials(token: "t"))
        let draft = CallBriefDraft(calleeName: "Serwis Laptop", phone: "22 123 45 67", principalName: "Anna", goal: "Sprawdzić laptop.",
                                   question: "Czy laptop jest gotowy?", facts: [CallFactDraft(text: "tajne", ticked: false)])
        let preview = try await client.createCallCase(draft)
        XCTAssertEqual(preview.openingLine.prefix(44), "Dzień dobry, mówi Doddy, asystent AI, dzwoni")
        XCTAssertEqual(preview.callableNow, true)
        let sent = await transport.sent
        XCTAssertEqual(sent.first?.path, "/v1/call-cases")
        XCTAssertFalse(String(decoding: sent.first?.body ?? Data(), as: UTF8.self).contains("tajne"))
    }

    func testRefusalsKeepTheirDetails() async throws {
        let replies = [
            ServerResponse(status: 400, body: Data(#"{"error":"brief_refused","field":"goal","reason":"pesel_not_ticked"}"#.utf8)),
            ServerResponse(status: 400, body: Data(#"{"error":"destination_refused","reason":"short_number"}"#.utf8)),
            ServerResponse(status: 409, body: Data(#"{"error":"gate_refused","gate":"limit_destination_gap"}"#.utf8)),
            ServerResponse(status: 409, body: Data(#"{"error":"digest_mismatch"}"#.utf8)),
            ServerResponse(status: 503, body: Data(#"{"error":"calls_disabled"}"#.utf8)),
        ]
        let expected: [CallCaseError] = [
            .briefRefused(field: "goal", reason: "pesel_not_ticked"), .destinationRefused(reason: "short_number"),
            .gateRefused(gate: "limit_destination_gap"), .notApprovable("digest_mismatch"), .callsDisabled,
        ]
        for (reply, want) in zip(replies, expected) {
            XCTAssertEqual(DoddyServerClient.callCaseError(from: reply), want)
        }
    }

    func testApprovalWithoutAnAnswerIsUnknownNotOffline() async throws {
        let transport = Failing()
        let client = DoddyServerClient(transport: transport, credentials: Credentials(token: "t"))
        let approval = try await client.approveCallCase(UUID(), digest: String(repeating: "a", count: 64))
        XCTAssertEqual(approval, CallApproval(attemptId: nil, state: "unknown"))
    }

    func testApproveSendsOnlyTheDigestAndTime() async throws {
        let attempt = UUID()
        let transport = Scripted([ServerResponse(status: 202, body: Data(#"{"attemptId":"\#(attempt.uuidString.lowercased())","state":"scheduled"}"#.utf8))])
        let client = DoddyServerClient(transport: transport, credentials: Credentials(token: "t"))
        let at = ISO8601DateFormatter().date(from: "2026-10-19T11:00:00Z")!
        let approval = try await client.approveCallCase(UUID(), digest: "ab", at: at)
        XCTAssertEqual(approval, CallApproval(attemptId: attempt, state: "scheduled"))
        let body = try JSONSerialization.jsonObject(with: await transport.sent[0].body!) as! [String: String]
        XCTAssertEqual(Set(body.keys), ["digest", "at"])
    }

    func testSnapshotDecodesTheAnswerCard() throws {
        let json = """
        {"caseId":"3ff77017-4163-417c-ae47-958d3dfdf213","state":"finished","approvableUntil":"2026-10-19T09:30:00.000Z","preview":null,
         "attempts":[{"id":"e4f0895b-f673-43c1-aad2-96e59880892a","attemptNo":1,"state":"ended","phase":"ended","endReason":"completed"}],
         "results":[{"attemptId":"e4f0895b-f673-43c1-aad2-96e59880892a","state":"ready","outcome":"answered","confidence":"high",
           "resultDigest":"\(String(repeating: "b", count: 64))","result":{"format":1,"outcome":"answered","source":"elevenlabs",
           "confidence":"high","confidenceReasons":[],"summary":"Odpowiedź: „Tak.”","summaryBy":"rules","quote":{"text":"Tak.","line":1},
           "transcript":[{"speaker":"doddy","text":"Dzień dobry","atSecs":0},{"speaker":"callee","text":"Tak.","atSecs":null}],
           "nextStep":{"kind":"save_note","text":"Zapisz odpowiedź w notatkach."},"warnings":[],"callbackPromised":false,
           "takenOverAtSecs":null,"durationSecs":35}}],
         "cost":{"currency":"USD","totalMicros":117000,"complete":false,"approximate":true,"pending":true,"unknownParts":[],
           "items":[{"attemptId":"x","component":"elevenlabs_voice","ref":"","status":"estimated","amountMicros":90000,"currency":"USD","quantity":900,"unit":"credit"}]},
         "deletions":[{"item":"call_input","location":"doddy_server","reason":"processed","result":"deleted","requestedAt":"2026-10-19T09:31:00.000Z","settledAt":"2026-10-19T09:31:00.000Z","rows":1}]}
        """
        let snap = try JSONDecoder().decode(CallCaseSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snap.readyResult?.result?.quote?.text, "Tak.")
        XCTAssertEqual(snap.readyResult?.outcome, .answered)
        XCTAssertEqual(snap.cost.amountText, "≈ 0.1170 USD")
        XCTAssertTrue(snap.deletions[0].isConfirmed)
    }

    func testUnknownPhasesAndOutcomesDecodeSafely() throws {
        XCTAssertEqual(try JSONDecoder().decode(CallPhase.self, from: Data(#""something_new""#.utf8)), .unknown)
        XCTAssertEqual(try JSONDecoder().decode(CallOutcome.self, from: Data(#""no_answer""#.utf8)), .noAnswer)
        XCTAssertTrue(CallOutcome.noAnswer.isRetryable)
        // The owner's list of failed calls that can be tried again (server: RETRYABLE_OUTCOMES).
        for outcome: CallOutcome in [.voicemail, .ivr, .wrongNumber, .busy, .voiceUnavailable] { XCTAssertTrue(outcome.isRetryable, "\(outcome)") }
        for outcome: CallOutcome in [.answered, .takenOver, .noConversation, .stopped] { XCTAssertFalse(outcome.isRetryable, "\(outcome)") }
        XCTAssertTrue(CallPhase.talking.canTakeOver)
        XCTAssertFalse(CallPhase.ringing.canTakeOver)
    }

    // MARK: Rehearsal and self-call script

    func testRehearsalIsToolLessAndFilledFromThePreview() throws {
        let preview = try JSONDecoder().decode(CallPreview.self, from: Data(Self.previewJSON.utf8))
        let text = try CallRehearsal.instructions(from: preview)
        XCTAssertTrue(text.contains("Serwis Laptop"))
        XCTAssertTrue(text.contains("Czy laptop jest gotowy?"))
        XCTAssertFalse(text.contains("{{"))
        XCTAssertTrue(text.contains("You are an AI, not a person"))
        let tools = try JSONSerialization.jsonObject(with: CallRehearsal.toolsJSON) as! [String: [Any]]
        XCTAssertEqual(tools["tools"]?.count, 0)
    }

    func testSelfCallScript() throws {
        let preview = try JSONDecoder().decode(CallPreview.self, from: Data(Self.previewJSON.utf8))
        let steps = SelfCallScript.steps(from: preview)
        XCTAssertEqual(steps.first?.text, "Dzień dobry, nazywam się Anna.")
        XCTAssertEqual(steps[1].text, "Mam pytanie: Czy laptop jest gotowy?")
        XCTAssertTrue(steps.contains(SelfCallScript.Step(label: "Jeśli zapytają", text: "Zlecenie 12345")))
        XCTAssertEqual(SelfCallScript.dialString(from: preview), "+48221234567")
    }

    // MARK: Cost per outcome

    func testCostPerOutcomeNeverAveragesUnknownAsZero() throws {
        let card = try JSONDecoder().decode(CallResultCard.self, from: Data("""
        {"outcome":"answered","source":"elevenlabs","confidence":"high","confidenceReasons":[],"summary":"s","summaryBy":"rules",
         "quote":null,"transcript":[],"nextStep":{"kind":"none","text":""},"warnings":[],"callbackPromised":false}
        """.utf8))
        func cost(_ micros: Int64, complete: Bool) -> CaseCost {
            CaseCost(currency: "USD", totalMicros: micros, complete: complete, approximate: false, pending: false, unknownParts: complete ? [] : ["twilio_call"], items: [])
        }
        let a = StoredCallCase(id: UUID(), createdAt: Date(), state: "finished", brief: CallBriefDraft(), result: card, cost: cost(100_000, complete: true))
        let b = StoredCallCase(id: UUID(), createdAt: Date(), state: "finished", brief: CallBriefDraft(), result: card, cost: cost(50_000, complete: true))
        XCTAssertEqual(CostPerOutcome.summarize([a, b]).perAnsweredMicros, 75_000)
        let c = StoredCallCase(id: UUID(), createdAt: Date(), state: "finished", brief: CallBriefDraft(), cost: cost(10_000, complete: false))
        let s = CostPerOutcome.summarize([a, b, c])
        XCTAssertEqual(s.casesWithUnknownCost, 1)
        XCTAssertNil(s.perAnsweredMicros)
    }
}

private actor Scripted: ServerTransport {
    private var responses: [ServerResponse]
    private(set) var sent: [ServerRequest] = []
    init(_ responses: [ServerResponse]) { self.responses = responses }
    func send(_ request: ServerRequest) async throws -> ServerResponse {
        sent.append(request)
        guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
        return responses.removeFirst()
    }
}

/// The request may have reached the server: the connection dropped after sending.
private struct Failing: ServerTransport {
    func send(_ request: ServerRequest) async throws -> ServerResponse { throw URLError(.networkConnectionLost) }
}

private final class Credentials: ServerCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    init(token: String?) { self.token = token }
    func load() throws -> String? { lock.withLock { token } }
    func save(_ token: String) throws { lock.withLock { self.token = token } }
    func delete() throws { lock.withLock { token = nil } }
}
