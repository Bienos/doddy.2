import Foundation
import XCTest
@testable import DoddyCore

/// Call tasks from a conversation (decision docs/decisions/2026-11-09-restaurant-calls-one-tap.md): up to
/// three places, one card, one tap. The server checks everything again; these are the phone's rules.
final class CallTaskTests: XCTestCase {
    private func parse(_ object: [String: Any]) throws -> VoiceToolRequest {
        VoiceToolRequest.parse(name: VoiceToolName.callPlaces, parametersJSON: try JSONSerialization.data(withJSONObject: object))
    }

    private func args(names: [String] = ["Trattoria Uno", "Osteria Due"], phones: [String] = ["22 123 45 67", "+48 600 100 200"],
                      question: String = "Czy mają Państwo wolny stolik dla dwóch osób dziś o 19:00",
                      goal: String = "Stolik na randkę dziś o 19.", extra: [String: Any] = [:]) -> [String: Any] {
        ["place_names": names, "place_phones": phones, "question": question, "goal": goal].merging(extra) { $1 }
    }

    private func reason(_ request: VoiceToolRequest) -> String? {
        if case .invalid(_, let reason) = request { return reason }
        return nil
    }

    // MARK: Parsing

    func testPlacesComeInOrderWithTheirNumbersAndTheTextChoiceDefaultsToOn() throws {
        guard case .callPlaces(let draft) = try parse(args()) else { return XCTFail("parsed") }
        XCTAssertEqual(draft.places, [CallTaskPlace(name: "Trattoria Uno", phone: "22 123 45 67"), CallTaskPlace(name: "Osteria Due", phone: "+48 600 100 200")])
        XCTAssertEqual(draft.question, "Czy mają Państwo wolny stolik dla dwóch osób dziś o 19:00")
        XCTAssertTrue(draft.textResult)
        guard case .callPlaces(let quiet) = try parse(args(extra: ["text_result": false])) else { return XCTFail("parsed") }
        XCTAssertFalse(quiet.textResult)
    }

    func testRefusalsTellTheAgentWhyAndCallNobody() throws {
        XCTAssertEqual(reason(try parse(args(names: ["A", "B", "C", "D"], phones: ["22 123 45 61", "22 123 45 62", "22 123 45 63", "22 123 45 64"]))),
                       "at most 3 places; pick the best 3")
        XCTAssertNotNil(reason(try parse(args(phones: ["22 123 45 67"]))), "a number for each name")
        XCTAssertNotNil(reason(try parse(args(names: [], phones: []))))
        XCTAssertNotNil(reason(try parse(args(names: ["A", "  "]))), "every place needs a name")
        XCTAssertNotNil(reason(try parse(args(phones: ["22 123 45 67", " "]))), "never a guessed or empty number")
        let premium = try XCTUnwrap(reason(try parse(args(phones: ["22 123 45 67", "700 123 456"]))))
        XCTAssertTrue(premium.contains("Osteria Due"), premium)
        XCTAssertNotNil(reason(try parse(args(phones: ["22 123 45 67", "+44 20 7946 0000"]))), "Polish numbers only")
        XCTAssertEqual(reason(try parse(args(phones: ["22 123 45 67", "+48 22 123 45 67"]))), "the same number is listed twice")
        XCTAssertNotNil(reason(try parse(args(question: "Hm?"))))
        XCTAssertNotNil(reason(try parse(args(question: String(repeating: "a", count: 201)))))
        XCTAssertNotNil(reason(try parse(args(goal: ""))))
        XCTAssertNotNil(reason(try parse(args(question: "Czy macie {{stolik}} wolny"))), "braces could reach the agent's variables")
    }

    // MARK: What is sent

    func testTheBodyMatchesTheServersSchema() throws {
        let draft = CallTaskDraft(places: [CallTaskPlace(name: "Trattoria Uno", phone: "22 123 45 67")],
                                  question: "Czy mają Państwo wolny stolik", goal: "Stolik na dziś.", textResult: false)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft.body(principalName: "Patryk"))) as? [String: Any])
        // server/messaging/src/taskCalls/tasks.ts taskSchema is strict: exactly these keys.
        XCTAssertEqual(Set(json.keys), ["kind", "places", "principal", "goal", "question", "facts", "maxDurationSecs", "textResult"])
        XCTAssertEqual(json["kind"] as? String, "ask")
        XCTAssertEqual(json["textResult"] as? Bool, false)
        XCTAssertEqual((json["facts"] as? [Any])?.count, 0, "no facts leave the iPhone from a conversation")
        let place = try XCTUnwrap((json["places"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(place.keys), ["name", "phone", "source"], "no empty sourceLabel")
        XCTAssertEqual(place["source"] as? String, "places", "the card says the number came from Doddy's place search")
        let principal = try XCTUnwrap(json["principal"] as? [String: String])
        XCTAssertEqual(principal["name"], "Patryk")
        XCTAssertEqual(principal["genitive"], PolishGenitive.suggest("Patryk"))
    }

    func testThePreviewDecodesAsTheServerSendsIt() throws {
        // The shape of createTask's answer in server/messaging/src/taskCalls/tasks.ts.
        let place = """
        {"caseId":"3ff77017-4163-417c-ae47-958d3dfdf213","digest":"\(String(repeating: "a", count: 64))","approvableUntil":"2026-11-09T10:30:00.000Z",
         "callee":{"name":"Trattoria Uno","phone":"22 123 45 67","destinationKind":"geographic","source":"places","sourceLabel":null},
         "principal":{"name":"Patryk","genitive":"Patryka"},"goal":"Stolik na dziś.",
         "openingLine":"Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu Patryka. Chciałbym zapytać: Czy mają Państwo wolny stolik?",
         "question":"Czy mają Państwo wolny stolik","facts":[],"forbidden":["Nie umawia, nie rezerwuje i nie zamawia."],
         "callbackLine":"Sprawdzę to u Patryka i oddzwonię.","maxDurationSecs":240,"notice":"off","recordsAudio":false}
        """
        let json = """
        {"taskId":"9a1c2b3d-4e5f-4a6b-8c7d-0e1f2a3b4c5d","digest":"\(String(repeating: "b", count: 64))",
         "approvableUntil":"2026-11-09T10:30:00.000Z","kind":"ask","textResult":true,"places":[\(place)],"callableNow":true}
        """
        let preview = try JSONDecoder().decode(CallTaskPreview.self, from: Data(json.utf8))
        XCTAssertEqual(preview.places.count, 1)
        XCTAssertEqual(preview.places[0].callee.source, .places)
        XCTAssertTrue(preview.textResult)
        XCTAssertEqual(preview.callableNow, true)
    }

    // MARK: Where it runs

    func testItNeedsItsOwnCardAndNeverRunsInTheCarOrWhilePaused() {
        let request = VoiceToolRequest.callPlaces(CallTaskDraft(places: [CallTaskPlace(name: "Uno", phone: "22 123 45 67")],
                                                                 question: "Czy mają Państwo stolik", goal: "Stolik.", textResult: true))
        let tool = ToolCatalog.descriptor(VoiceToolName.callPlaces)
        XCTAssertEqual(tool?.approval, .card)
        XCTAssertEqual(tool?.effect, .placeCall)
        XCTAssertEqual(tool?.runsOn, .phone)
        XCTAssertEqual(tool?.planEligible, false, "a plan card doesn't show every place and the question")
        XCTAssertEqual(AskFirst.need(for: request), .ownPayloadCard)
        guard case .refuse = CarProfile.decision(for: request) else { return XCTFail("car") }
        XCTAssertTrue(ConnectionPause.applies(to: request))
    }

    func testTheActivityRowNamesThePlacesButNeverTheirNumbersOrTheQuestion() throws {
        let request = VoiceToolRequest.callPlaces(CallTaskDraft(places: [CallTaskPlace(name: "Uno", phone: "22 123 45 67"), CallTaskPlace(name: "Due", phone: "600 100 200")],
                                                                 question: "Czy mają Państwo stolik", goal: "Stolik.", textResult: true))
        let row = try XCTUnwrap(ActivityRequest.describe(request, calendar: .current))
        XCTAssertEqual(row.detail, "Uno, Due")
        XCTAssertFalse(String(describing: row).contains("123 45 67"))
        XCTAssertFalse(String(describing: row).contains("stolik"))
    }

    // MARK: What the agent hears

    func testRepliesNeverSayAnyoneAnswered() {
        let started = VoiceToolReply.callTaskStarted(first: "Trattoria Uno", count: 3, textResult: true)
        XCTAssertTrue(started.hasPrefix("started:"))
        XCTAssertTrue(started.contains("Trattoria Uno"))
        XCTAssertTrue(started.contains("next place"))
        XCTAssertTrue(started.contains("text"))
        XCTAssertFalse(VoiceToolReply.callTaskStarted(first: "Uno", count: 1, textResult: false).contains("next place"))
        XCTAssertTrue(VoiceToolReply.callTaskUnknown.hasPrefix("unknown:"))
        XCTAssertTrue(VoiceToolReply.callTaskDeclined.hasPrefix("declined:"))
        XCTAssertEqual(ActivityEntry.outcome(of: VoiceToolReply.callTaskDeclined, isLookup: false).0, .declined)
        XCTAssertEqual(ActivityEntry.outcome(of: VoiceToolReply.callTaskUnknown, isLookup: false).0, .notSure)
        XCTAssertTrue(VoiceToolReply.callTaskRefused(CallCaseError.notApprovable("outside_hours")).contains("8:00 to 23:00"))
        XCTAssertTrue(VoiceToolReply.callTaskRefused(ServerError.offline).contains("couldn't reach"))
        XCTAssertTrue(VoiceToolReply.callTaskNoPhone.hasPrefix("failed:"))
    }
}
