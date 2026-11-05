import Foundation
import XCTest
@testable import DoddyCore

/// Sport mode step 5 (ADR-626): asking for a plan by voice or in Messages. A model may pass on a goal and,
/// if the person said them, the days and minutes. Never a safety answer, an age or a level.
final class PlanAskTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()
    private let now = Date(timeIntervalSince1970: 1_793_000_000)

    private func parse(_ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: VoiceToolName.openTrainingPlan, parametersJSON: Data(json.utf8), now: now, calendar: calendar)
    }

    // MARK: The checked request

    func testEveryGoalHasOneNameAndComesBack() {
        XCTAssertEqual(PlanAsk.goalNames.count, PlanGoal.allCases.count, "a goal added to the engine needs a name here")
        for goal in PlanGoal.allCases {
            XCTAssertEqual(PlanAsk.goal(named: PlanAsk.name(of: goal)), goal)
            XCTAssertFalse(PlanAsk.goalTitle(goal).isEmpty)
        }
        XCTAssertEqual(PlanAsk.goal(named: " 10K "), .tenK, "case and spaces don't matter")
        XCTAssertNil(PlanAsk.goal(named: "marathon"))
        XCTAssertNil(PlanAsk.goal(named: "none"))
        XCTAssertNil(PlanAsk.goal(named: ""))
    }

    func testDaysAndMinutesOutsideWhatTheScreenOffersAreLeftOutNotClamped() {
        let kept = PlanAsk.make(goalName: "10k", daysPerWeek: 3, minutesPerSession: 45)
        XCTAssertEqual(kept, PlanAsk(goal: .tenK, daysPerWeek: 3, minutesPerSession: 45))
        for days in [1, 6, 0, -2, 40] {
            XCTAssertNil(PlanAsk.make(goalName: "10k", daysPerWeek: days, minutesPerSession: 45)?.daysPerWeek, "days \(days)")
        }
        XCTAssertEqual(PlanAsk.make(goalName: "10k", daysPerWeek: 5, minutesPerSession: nil)?.daysPerWeek, 5, "running allows 5")
        XCTAssertNil(PlanAsk.make(goalName: "strength_gym", daysPerWeek: 5, minutesPerSession: nil)?.daysPerWeek, "strength allows 4")
        XCTAssertEqual(PlanAsk.make(goalName: "strength_home", daysPerWeek: 4, minutesPerSession: nil)?.daysPerWeek, 4)
        // Minutes: 20 to 150, counted in 5s like the screen's stepper.
        XCTAssertEqual(PlanAsk.make(goalName: "10k", daysPerWeek: nil, minutesPerSession: 47)?.minutesPerSession, 45)
        XCTAssertEqual(PlanAsk.make(goalName: "10k", daysPerWeek: nil, minutesPerSession: 48)?.minutesPerSession, 50)
        XCTAssertEqual(PlanAsk.make(goalName: "10k", daysPerWeek: nil, minutesPerSession: 20)?.minutesPerSession, 20)
        XCTAssertEqual(PlanAsk.make(goalName: "10k", daysPerWeek: nil, minutesPerSession: 150)?.minutesPerSession, 150)
        for minutes in [0, 10, 17, 153, 200, -5] {
            XCTAssertNil(PlanAsk.make(goalName: "10k", daysPerWeek: nil, minutesPerSession: minutes)?.minutesPerSession, "minutes \(minutes)")
        }
        XCTAssertNil(PlanAsk.make(goalName: "swimming", daysPerWeek: 3, minutesPerSession: 45), "no plan for a goal the engine doesn't know")
    }

    /// The rule that matters most: whatever a model sends, the request holds a goal, days and minutes, and nothing about the
    /// person's health. A field added to the type breaks this on purpose.
    func testARequestHoldsNothingAboutThePersonsHealth() throws {
        let ask = try XCTUnwrap(PlanAsk.make(goalName: "half_marathon", daysPerWeek: 4, minutesPerSession: 60))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ask)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["goal", "daysPerWeek", "minutesPerSession"])
        XCTAssertEqual(Mirror(reflecting: ask).children.count, 3)
    }

    func testTheCardSaysWhatIsFilledInAndThatTheSafetyQuestionsAreTheirs() throws {
        let full = try XCTUnwrap(PlanAsk.make(goalName: "10k", daysPerWeek: 3, minutesPerSession: 45))
        XCTAssertEqual(full.cardLines, ["Goal: 10 km", "3 days a week, 45 min a session", "You answer the safety questions yourself, on screen."])
        let bare = try XCTUnwrap(PlanAsk.make(goalName: "strength_gym", daysPerWeek: nil, minutesPerSession: nil))
        XCTAssertEqual(bare.cardLines, ["Goal: Strength at the gym", "You answer the safety questions yourself, on screen."])
    }

    // MARK: The voice tool

    func testTheToolParsesAndAsksForATap() throws {
        let request = parse(#"{"goal":"10k","days_per_week":3,"minutes_per_session":45}"#)
        let ask = try XCTUnwrap(PlanAsk.make(goalName: "10k", daysPerWeek: 3, minutesPerSession: 45))
        XCTAssertEqual(request, .openTrainingPlan(ask))
        XCTAssertEqual(ToolCatalog.descriptor(VoiceToolName.openTrainingPlan)?.approval, .card, "ASK-01: a card and a tap")
        guard case .tapFirst(let card) = AskFirst.need(for: request, calendar: calendar) else { return XCTFail("expected a tap first") }
        XCTAssertEqual(card.title, "Make a training plan?")
        XCTAssertEqual(card.confirmLabel, "Open")
        XCTAssertEqual(card.lines, ask.cardLines)
        XCTAssertTrue(AskFirst.needsTap(.tapFirst(card)), "a spoken yes is not enough")
    }

    func testTheToolAcceptsWholeNumbersAsTextOrJSONAndOnlyAKnownGoal() {
        XCTAssertEqual(parse(#"{"goal":"first_5k"}"#), .openTrainingPlan(PlanAsk(goal: .firstFiveK, daysPerWeek: nil, minutesPerSession: nil)))
        // 7 days is not offered: left out, so the screen's default stands.
        XCTAssertEqual(parse(#"{"goal":"10k","days_per_week":7,"minutes_per_session":45}"#),
                       .openTrainingPlan(PlanAsk(goal: .tenK, daysPerWeek: nil, minutesPerSession: 45)))
        XCTAssertEqual(parse(#"{"goal":"10k","days_per_week":2.5}"#), .openTrainingPlan(PlanAsk(goal: .tenK, daysPerWeek: nil, minutesPerSession: nil)))
        for bad in [#"{}"#, #"{"goal":""}"#, #"{"goal":"marathon"}"#, #"{"goal":"none"}"#, #"{"days_per_week":3}"#] {
            guard case .invalid(let name, let reason) = parse(bad) else { return XCTFail("expected invalid for \(bad)") }
            XCTAssertEqual(name, VoiceToolName.openTrainingPlan)
            XCTAssertTrue(reason.contains("first_5k, 10k, half_marathon, strength_home, strength_gym"), reason)
        }
    }

    func testAnyKeyForHealthAnswersIsIgnored() {
        // A model that adds a health answer, an age or a level changes nothing: the request has no place for them.
        let withExtras = parse(#"{"goal":"10k","days_per_week":3,"age":15,"injury":true,"level":"regular","knows_condition":"yes"}"#)
        XCTAssertEqual(withExtras, .openTrainingPlan(PlanAsk(goal: .tenK, daysPerWeek: 3, minutesPerSession: nil)))
    }

    func testItIsLoggedPausedAndRefusedInTheCar() {
        let ask = PlanAsk(goal: .tenK, daysPerWeek: nil, minutesPerSession: nil)
        let activity = ActivityRequest.describe(.openTrainingPlan(ask), calendar: calendar)
        XCTAssertEqual(activity?.app, .training)
        XCTAssertEqual(activity?.title, "Open the training plan")
        XCTAssertEqual(activity?.detail, "10 km")
        XCTAssertEqual(activity?.isLookup, false)
        XCTAssertEqual(ActivityApp.training.title, "Training plan")
        XCTAssertEqual(ActivityText.title("Open the training plan", .polish), "Otwórz plan treningowy")
        XCTAssertFalse(ConnectionPause.applies(to: .openTrainingPlan(ask)), "Doddy's own screen: no other app or account")
        if case .refuse = CarProfile.decision(for: .openTrainingPlan(ask)) {} else { XCTFail("a screen with questions waits until the user isn't driving") }
        XCTAssertNil(VoiceConnection.serving(VoiceToolName.openTrainingPlan))
    }

    func testWhatTheAgentHearsNeverIncludesTheirAnswersAndStopsHealthQuestions() throws {
        let ask = try XCTUnwrap(PlanAsk.make(goalName: "10k", daysPerWeek: 3, minutesPerSession: nil))
        let opened = VoiceToolReply.trainingPlanOpened(ask)
        XCTAssertTrue(opened.hasPrefix("opened:"))
        XCTAssertTrue(opened.contains("goal: 10 km; days a week: 3; minutes a session: not set, the user picks"), opened)
        XCTAssertTrue(opened.contains("You don't see their answers or the plan"))
        XCTAssertTrue(opened.contains("Never ask about their health, injuries, age or medicines"))
        XCTAssertTrue(opened.contains("never say a plan is made"))
        XCTAssertTrue(opened.contains("tell them to ask a doctor or physiotherapist first"))
        // A "no" on the card is answered by ASK-01's own reply, which says nothing was done.
        XCTAssertTrue(AskFirst.notAsked(VoiceToolName.openTrainingPlan).hasPrefix("declined:"))
    }

    // MARK: Messages

    private let request = AssistantRequest(sessionID: UUID(), userText: "Zrób mi plan na 10 km")

    private func body(plan: String?) -> GatewayHTTPResponse {
        let id = request.requestID.uuidString.lowercased()
        let extra = plan.map { #","plan":\#($0)"# } ?? ""
        return GatewayHTTPResponse(status: 200, body: Data(#"{"schemaVersion":1,"requestId":"\#(id)","text":"Mogę to ustawić.","citedMemoryIDs":[]\#(extra)}"#.utf8))
    }

    func testAnAnswerCanOfferAPlanAndTheCoreChecksIt() throws {
        let offered = try GatewayAssistantClient.interpret(body(plan: #"{"goal":"10k","daysPerWeek":3,"minutesPerSession":45}"#), for: request)
        XCTAssertEqual(offered.planAsk, PlanAsk(goal: .tenK, daysPerWeek: 3, minutesPerSession: 45))
        let partly = try GatewayAssistantClient.interpret(body(plan: #"{"goal":"strength_gym","daysPerWeek":9}"#), for: request)
        XCTAssertEqual(partly.planAsk, PlanAsk(goal: .strengthGym, daysPerWeek: nil, minutesPerSession: nil), "9 days isn't offered: the screen's own default")
        for bad in [#"{"goal":"marathon","daysPerWeek":3}"#, #"{"goal":"none"}"#, #"{"goal":""}"#] {
            let reply = try GatewayAssistantClient.interpret(body(plan: bad), for: request)
            XCTAssertNil(reply.planAsk, bad)
            XCTAssertEqual(reply.text, "Mogę to ustawić.", "the answer is still shown")
        }
        XCTAssertNil(try GatewayAssistantClient.interpret(body(plan: nil), for: request).planAsk, "an older server sends none")
    }

    func testTheVerifiedAnswerKeepsTheOffer() throws {
        let ask = PlanAsk(goal: .halfMarathon, daysPerWeek: 4, minutesPerSession: nil)
        let verified = try CitationVerifier.verify(AssistantReply(text: "Mogę to ustawić.", planAsk: ask), for: request)
        XCTAssertEqual(verified.planAsk, ask)
        XCTAssertNil(try CitationVerifier.verify(AssistantReply(text: "Cześć."), for: request).planAsk)
    }
}
