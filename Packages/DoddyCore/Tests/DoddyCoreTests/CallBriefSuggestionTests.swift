@testable import DoddyCore
import XCTest

/// "Who and why" in one field (decision 2026-11-13-calls-one-field-brief): what the iPhone does with the server's
/// suggestion. The number is the picked contact's or one in the user's words; details only if the user wrote them;
/// a PESEL or an address stays unticked.
final class CallBriefSuggestionTests: XCTestCase {
    private let sentence = "Zadzwoń do fryzjera Anna na Długiej, 600 100 200, i zapytaj, czy mają wolne w sobotę"

    private func suggestion(phone: String? = "+48600100200", facts: [CallBriefSuggestion.Fact] = []) -> CallBriefSuggestion {
        CallBriefSuggestion(callee: .init(name: "Fryzjer Anna na Długiej", phone: phone),
                            goal: "Sprawdzić wolny termin w sobotę.", question: "Czy mają Państwo wolny termin w sobotę?", facts: facts)
    }

    func testTheSuggestionFillsTheEditorWithTheNumberFromTheWords() {
        let draft = CallBriefDraft.drafted(from: suggestion(), text: sentence, contact: nil, principalName: "Anna")
        XCTAssertEqual(draft.calleeName, "Fryzjer Anna na Długiej")
        XCTAssertEqual(draft.phone, "+48600100200")
        XCTAssertEqual(draft.source, .typed)
        XCTAssertEqual(draft.question, "Czy mają Państwo wolny termin w sobotę?")
        XCTAssertEqual(draft.principalGenitive, "Anny")
        XCTAssertTrue(draft.problems.isEmpty, "\(draft.problems)")
    }

    func testANumberNotInTheUsersWordsIsNeverUsed() {
        let draft = CallBriefDraft.drafted(from: suggestion(phone: "+48601999888"), text: sentence, contact: nil, principalName: "Anna")
        XCTAssertEqual(draft.phone, "")
        XCTAssertTrue(draft.problems.contains(.numberNotAllowed(.notANumber)))
    }

    func testThePickedContactsNumberWins() {
        let contact = CallBriefContact(name: "Anna Fryzjer", number: "22 123 45 67")
        let draft = CallBriefDraft.drafted(from: suggestion(), text: sentence, contact: contact, principalName: "Anna")
        XCTAssertEqual(draft.phone, "22 123 45 67")
        XCTAssertEqual(draft.source, .contacts)
        XCTAssertEqual(draft.sourceLabel, "Anna Fryzjer")
        // No name in the suggestion: the contact's.
        let noName = CallBriefSuggestion(callee: .init(name: nil, phone: nil), goal: nil, question: nil)
        XCTAssertEqual(CallBriefDraft.drafted(from: noName, text: "Zapytaj, czy jutro pracuje", contact: contact, principalName: "Anna").calleeName,
                       "Anna Fryzjer")
    }

    func testDetailsOnlyFromTheWordsAndSensitiveOnesUnticked() {
        let text = "Zapytaj serwis Bajt o laptop ze zlecenia 12345, odbiór ul. Polna 3, mój PESEL 44051401359"
        let facts: [CallBriefSuggestion.Fact] = [
            .init(kind: .reference, text: "zlecenia 12345"),
            .init(kind: .address, text: "ul. Polna 3"),
            .init(kind: .general, text: "klient VIP"),
            .init(kind: .reference, text: "PESEL 44051401359"),
            .init(kind: .reference, text: "Zlecenia  12345"),
        ]
        let draft = CallBriefDraft.drafted(from: suggestion(phone: nil, facts: facts), text: text, contact: nil, principalName: "Anna")
        XCTAssertEqual(draft.facts.map(\.text), ["zlecenia 12345", "ul. Polna 3", "PESEL 44051401359"])
        XCTAssertEqual(draft.facts.map(\.kind), [.reference, .address, .pesel])
        XCTAssertEqual(draft.facts.map(\.ticked), [true, false, false])
        XCTAssertEqual(draft.requestBody().facts.map(\.text), ["zlecenia 12345"], "only the ticked fact would leave the iPhone")
    }

    func testOwnWordsWhenNoSuggestionCame() {
        let draft = CallBriefDraft.ownWords("  \(sentence) ", contact: nil, principalName: "Anna")
        XCTAssertEqual(draft.goal, sentence)
        XCTAssertEqual(draft.phone, "")
        XCTAssertEqual(draft.question, "")
        XCTAssertEqual(CallBriefDraft.ownWords(String(repeating: "a", count: 161), contact: nil, principalName: "Anna").goal, "")
    }

    func testOneFieldLength() {
        XCTAssertFalse(CallBriefDraft.oneFieldReady("  hej  "))
        XCTAssertTrue(CallBriefDraft.oneFieldReady(sentence))
        XCTAssertFalse(CallBriefDraft.oneFieldReady(String(repeating: "a", count: 401)))
    }

    func testDraftSendsTheWordsAndTheContactsNameOnly() async throws {
        let json = """
        {"callee":{"name":"Fryzjer Anna","phone":"+48600100200","source":"typed"},"goal":"Sprawdzić termin.",
         "question":"Czy mają Państwo wolne w sobotę?","facts":[{"kind":"date","text":"w sobotę"}],
         "missing":[],"dropped":[{"field":"facts.1","reason":"not_from_text"}]}
        """
        let transport = Scripted([ServerResponse(status: 200, body: Data(json.utf8))])
        let client = DoddyServerClient(transport: transport, credentials: Credentials(token: "t"))
        let got = try await client.draftCallBrief(text: " \(sentence) ", contactName: "Anna Fryzjer")
        XCTAssertEqual(got.callee.phone, "+48600100200")
        XCTAssertEqual(got.facts, [.init(kind: .date, text: "w sobotę")])
        XCTAssertEqual(got.dropped, [.init(field: "facts.1", reason: "not_from_text")])
        let sent = await transport.sent
        XCTAssertEqual(sent.first?.path, "/v1/call-cases/draft")
        let body = try JSONSerialization.jsonObject(with: sent.first?.body ?? Data()) as? [String: String]
        XCTAssertEqual(body, ["text": sentence, "contactName": "Anna Fryzjer"])
    }

    func testRefusedWordsKeepTheirReason() async {
        let transport = Scripted([ServerResponse(status: 400, body: Data(#"{"error":"brief_refused","field":"text","reason":"pesel_not_ticked"}"#.utf8))])
        let client = DoddyServerClient(transport: transport, credentials: Credentials(token: "t"))
        do {
            _ = try await client.draftCallBrief(text: sentence, contactName: nil)
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? CallCaseError, .briefRefused(field: "text", reason: "pesel_not_ticked"))
        }
        let sent = await transport.sent
        XCTAssertEqual(try JSONSerialization.jsonObject(with: sent.first?.body ?? Data()) as? [String: String], ["text": sentence],
                       "no contact: no contactName key")
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

private final class Credentials: ServerCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    init(token: String?) { self.token = token }
    func load() throws -> String? { lock.withLock { token } }
    func save(_ token: String) throws { lock.withLock { self.token = token } }
    func delete() throws { lock.withLock { token = nil } }
}
