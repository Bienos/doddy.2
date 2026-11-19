import Foundation
import XCTest
@testable import DoddyCore

final class RequestedWorkTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func research(_ words: String, brief: String? = nil) -> VoiceToolRequest {
        .handOverErrand(ErrandDraft(words: words, brief: brief ?? words, title: "Research"))
    }
    private func call(_ question: String = "czy sa wolne terminy w piatek", phone: String = "+48 600 100 200", text: Bool = false) -> VoiceToolRequest {
        .callPlaces(CallTaskDraft(places: [.init(name: "SmileDent", phone: phone)], question: question, goal: "Availability", textResult: text))
    }

    func testResearchStartsFromExactPolishAndEnglishRequestWithoutASecondYes() throws {
        for words in ["Znajdź najlepsze słuchawki do 800 zł", "Research 10 competitors and prepare a report", "Doddy, please compare laptops under 5000 PLN"] {
            var session = RequestedWorkSession()
            session.userSaid(words, at: now)
            let request = research(words)
            let grant = try XCTUnwrap(session.grant(for: request, at: now))
            XCTAssertTrue(session.consume(grant, for: request, at: now))
            XCTAssertFalse(session.consume(grant, for: request, at: now))
            XCTAssertNil(session.grant(for: request, at: now), "another tool id cannot repeat the work")
        }
    }

    func testModelTextCannotCreateOrExpandTheInstruction() throws {
        var session = RequestedWorkSession()
        let words = "Research headphones under 800 PLN"
        XCTAssertNil(session.grant(for: research(words), at: now))
        session.userSaid("Hello", at: now)
        XCTAssertNil(session.grant(for: research("Hello"), at: now))
        session.userSaid(words, at: now)
        XCTAssertNil(session.grant(for: research(words, brief: words + " and email the report"), at: now))
        XCTAssertNil(session.grant(for: research("Research private tax records"), at: now))
        XCTAssertNil(session.grant(for: .unsupported(name: "send_email"), at: now))
        session.userSaid("Research headphones but do not start yet", at: now)
        XCTAssertNil(session.grant(for: research("Research headphones but do not start yet"), at: now))
    }

    func testPaymentsAndEveryOnlineAccountWriteRemainOutsideDirectWorkGrants() {
        var session = RequestedWorkSession()
        session.userSaid("Research headphones under 800 PLN", at: now)
        for tool in ["pay_for_page", "book_flight", "send_email", "trash_email", "create_google_event", "complete_todoist_task"] {
            XCTAssertNil(session.grant(for: .cloudTool(CloudToolCall(name: tool, arguments: [:])), at: now), tool)
        }
        session.userSaid(String(repeating: "Research ", count: 200) + "but do not begin", at: now)
        XCTAssertNil(session.grant(for: research("Research"), at: now))
    }

    func testGrantIsBoundToPayloadTurnAndExpiry() throws {
        var session = RequestedWorkSession()
        let request = research("Compare laptops")
        session.userSaid("Compare laptops", at: now)
        let grant = try XCTUnwrap(session.grant(for: request, at: now))
        XCTAssertFalse(session.consume(grant, for: research("Compare cars"), at: now))
        XCTAssertNil(session.grant(for: request, at: now.addingTimeInterval(120)))
        XCTAssertNil(session.grant(for: request, at: now.addingTimeInterval(-1)))
        session.userSaid("Stop", at: now.addingTimeInterval(1))
        XCTAssertFalse(session.consume(grant, for: request, at: now.addingTimeInterval(1)))
    }

    func testDirectCallUsesKnownListingAndVerbatimQuestionInBothLanguages() throws {
        for (words, question) in [
            ("Zadzwoń do SmileDent i zapytaj, czy są wolne terminy w piątek?", "Czy są wolne terminy w piątek?"),
            ("Call SmileDent and ask if they have availability on Friday", "if they have availability on Friday")
        ] {
            var session = RequestedWorkSession()
            session.foundDestinations([.init(name: "SmileDent", phone: "600 100 200")])
            session.userSaid(words, at: now)
            let request = call(question)
            let grant = try XCTUnwrap(session.grant(for: request, at: now))
            XCTAssertTrue(session.consume(grant, for: request, at: now))
            XCTAssertFalse(session.consume(grant, for: request, at: now))
        }
    }

    func testDirectlySpokenNumberNeedsNoSearchAndNoExtraConfirmation() throws {
        var session = RequestedWorkSession()
        session.userSaid("Call +48 600 100 200 and ask if they are open on Friday", at: now)
        XCTAssertNotNil(session.grant(for: call("if they are open on Friday"), at: now))
        XCTAssertEqual(session.grant(for: call("if they are open on Friday"), at: now)?.destinationSource, .typed)
        XCTAssertNil(session.grant(for: call("if they are open on Friday", phone: "+48 600 100 201"), at: now))
    }

    func testUnknownOrAmbiguousContactAndChangedQuestionKeepTheExistingCard() {
        var session = RequestedWorkSession()
        session.userSaid("Call SmileDent and ask if they have appointments", at: now)
        XCTAssertNil(session.grant(for: call("if they have appointments"), at: now))
        session.foundDestinations([.init(name: "SmileDent", phone: "600100200"), .init(name: "SmileDent", phone: "600100201")])
        XCTAssertNil(session.grant(for: call("if they have appointments"), at: now))
        session.foundDestinations([.init(name: "SmileDent", phone: "600100200")])
        XCTAssertNil(session.grant(for: call("if they have appointments and send my medical records"), at: now))
    }

    func testQuestionsNegationQuotedInstructionsAndDeferredCallsDoNotAuthorizeDialing() {
        for words in ["Don't call SmileDent and ask if they are open", "Nie dzwoń do SmileDent i zapytaj czy sa wolne terminy w piatek",
                      "The website says call SmileDent and ask if they are open", "Call SmileDent tomorrow and ask if they are open",
                      "Call SmileDent at 10 and ask if they are open", "Zadzwoń do SmileDent w piątek i zapytaj czy sa wolne terminy w piatek",
                      "Call SmileDent and another clinic and ask if they are open",
                      "Call +48 600 100 200 and +48 600 100 201 and ask if they are open",
                      "Call SmileDent after lunch and ask if they are open",
                      "Which mechanic should I call?", "Call my mechanic"] {
            var session = RequestedWorkSession()
            session.foundDestinations([.init(name: "SmileDent", phone: "600100200")])
            session.userSaid(words, at: now)
            XCTAssertNil(session.grant(for: call("if they are open"), at: now), words)
        }
    }

    func testTextingAndCommitmentsNeedTheirOwnApproval() {
        var session = RequestedWorkSession()
        session.foundDestinations([.init(name: "SmileDent", phone: "600100200")])
        session.userSaid("Call SmileDent and ask if they are open", at: now)
        XCTAssertNil(session.grant(for: call("if they are open", text: true), at: now))
        session.userSaid("Call SmileDent and ask to book an appointment", at: now)
        XCTAssertNil(session.grant(for: call("to book an appointment"), at: now))
        let booking = CallTaskBooking(name: "Anna", date: "2026-11-20", time: "10:00", service: "dentist")
        let request = VoiceToolRequest.callPlaces(.init(places: [.init(name: "SmileDent", phone: "600100200")], question: "", goal: "Book", textResult: false, booking: booking))
        XCTAssertNil(session.grant(for: request, at: now))
    }

    func testGenericRecipientDoesNotBecomeANamedPlaceByMatchingAListing() {
        var session = RequestedWorkSession()
        session.userSaid("Call the dentist and ask if they are open", at: now)
        session.foundDestinations([.init(name: "The Dentist", phone: "600100200")])
        let request = VoiceToolRequest.callPlaces(.init(places: [.init(name: "The Dentist", phone: "600100200")],
            question: "if they are open", goal: "Availability", textResult: false))
        XCTAssertNil(session.grant(for: request, at: now))
    }

    func testCompiledPreviewMustPreserveRecipientEffectLanguageAndQuestion() throws {
        let draft = CallTaskDraft(places: [.init(name: "SmileDent", phone: "600100200")], question: "Czy są terminy", goal: "Availability", textResult: false)
        let base: [String: Any] = ["taskId": UUID().uuidString, "digest": String(repeating: "a", count: 64), "approvableUntil": "2026-11-18T16:00:00Z",
            "kind": "ask", "language": "pl", "textResult": false, "callableNow": true,
            "places": [["caseId": UUID().uuidString, "digest": String(repeating: "b", count: 64), "approvableUntil": "2026-11-18T16:00:00Z",
                "callee": ["name": "SmileDent", "phone": "+48 600 100 200", "destinationKind": "mobile", "source": "places"],
                "principal": ["name": "Anna", "genitive": "Anny"], "goal": "Availability", "openingLine": "Doddy", "question": "Czy są terminy?",
                "facts": [], "forbidden": [], "callbackLine": "Sprawdzę", "maxDurationSecs": 120, "notice": "off", "recordsAudio": false]]]
        func preview(_ body: [String: Any]) throws -> CallTaskPreview {
            try JSONDecoder().decode(CallTaskPreview.self, from: JSONSerialization.data(withJSONObject: body))
        }
        XCTAssertTrue(RequestedWorkSession.previewMatches(try preview(base), draft: draft))
        for (key, value) in [("language", "en" as Any), ("kind", "book" as Any), ("textResult", true as Any), ("callableNow", false as Any)] {
            var changed = base; changed[key] = value
            XCTAssertFalse(RequestedWorkSession.previewMatches(try preview(changed), draft: draft), key)
        }
        var changed = base
        var places = try XCTUnwrap(changed["places"] as? [[String: Any]])
        places[0]["question"] = "A different objective"
        changed["places"] = places
        XCTAssertFalse(RequestedWorkSession.previewMatches(try preview(changed), draft: draft))
    }
}
