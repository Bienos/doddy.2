import XCTest
@testable import DoddyCore

/// The research's acceptance tests 1, 2, 3, 11 and 12, at the level of the logic (ADR-642).
final class TrainingExpertTests: XCTestCase {
    private let clear30 = PlanScreening.clear(age: 30)

    private func complete(goal: PlanGoal, days: Int, minutes: Int = 45, level: PlanLevel = .beginner) -> TrainingAnswers {
        TrainingAnswers(goal: goal, level: level, daysPerWeek: days, minutesPerSession: minutes, screening: clear30)
    }

    // MARK: Test 1: "Trenuję 3 dni" gives a 3-day plan, with no diagnosis and not twenty questions

    func testThreeDaysAsksAFewQuestionsThenMakesAThreeDayPlan() throws {
        let first = TrainingExpert.respond(TrainingTurn(text: "Trenuję 3 dni"))
        XCTAssertNil(first.plan)
        XCTAssertEqual(first.answers.daysPerWeek, 3)
        XCTAssertEqual(first.questions, [.goal, .level, .minutesPerSession, .screening])
        XCTAssertLessThanOrEqual(first.questions.count, TrainingInterview.maxQuestions)
        XCTAssertEqual(first.result.missingData, ["goal", "level", "minutesPerSession", "screening"])
        XCTAssertFalse(first.result.answer.lowercased().contains("diagnoz"))

        // The person answers; the days said in turn one are remembered.
        var next = first.answers
        next.goal = .strengthHome
        next.level = .beginner
        next.minutesPerSession = 45
        next.screening = clear30
        let second = TrainingExpert.respond(TrainingTurn(text: "dom, początkujący, 45 minut", answers: next))
        let plan = try XCTUnwrap(second.plan)
        XCTAssertTrue(plan.weeks.allSatisfy { $0.sessions.count == 3 }, "three sessions every week")
        XCTAssertEqual(PlanRules.violations(plan), [])
        XCTAssertEqual(second.result.sources, [.who2020, .acsm2026])
        XCTAssertEqual(second.result.proposedActions.map(\.kind), ["keep_plan"])
        XCTAssertTrue(second.result.answer.contains("3"))
        XCTAssertFalse(second.result.verifiedExternalAction)
        XCTAssertEqual(second.result.riskLevel, .low)
        XCTAssertTrue(second.result.caveats.contains { $0.contains("AI") })
        XCTAssertTrue(second.result.caveats.contains { $0.contains("150–300") && $0.contains("nie obowiązek") })
    }

    func testARunningGoalAlsoGivesThreeSessionsAndCitesTheLongestRunRule() throws {
        let reply = TrainingExpert.respond(TrainingTurn(text: "chcę zacząć biegać, 3 dni", answers: complete(goal: .firstFiveK, days: 3)))
        let plan = try XCTUnwrap(reply.plan)
        XCTAssertTrue(plan.weeks.allSatisfy { $0.sessions.count == 3 })
        XCTAssertEqual(reply.result.sources, [.who2020, .frandsen2025])
        XCTAssertEqual(PlanRules.violations(plan), [])
    }

    // MARK: Test 2: chest pain gives a fixed stop and no plan, whatever else is known

    func testChestPainGivesTheFixedMessageAndNoPlanEvenWithEverythingAnswered() {
        let reply = TrainingExpert.respond(TrainingTurn(text: "Boli mnie nagle w klatce przy treningu",
                                                        answers: complete(goal: .strengthGym, days: 3, level: .regular)))
        XCTAssertNil(reply.plan)
        XCTAssertEqual(reply.result.answer, TrainingTriage.stopPL, "the fixed text, word for word")
        XCTAssertEqual(reply.result.riskLevel, .emergency)
        XCTAssertTrue(reply.result.answer.contains("112"))
        XCTAssertTrue(reply.result.proposedActions.isEmpty)
        XCTAssertTrue(reply.result.missingData.isEmpty)
        XCTAssertTrue(reply.triage.stopNow)
        let english = TrainingExpert.respond(TrainingTurn(text: "I have sudden chest pain when I train", answers: complete(goal: .strengthGym, days: 3),
                                                          language: .english))
        XCTAssertEqual(english.result.answer, TrainingTriage.stopEN)
        XCTAssertNil(english.plan)
    }

    func testInjuryAndPregnancyGiveTheirFixedTextAndNoPlan() {
        let injury = TrainingExpert.respond(TrainingTurn(text: "skręciłem kostkę, chcę biegać", answers: complete(goal: .firstFiveK, days: 3)))
        XCTAssertNil(injury.plan)
        XCTAssertEqual(injury.result.answer, TrainingTriage.injuryPL)
        XCTAssertEqual(injury.result.riskLevel, .high)
        let pregnant = TrainingExpert.respond(TrainingTurn(text: "jestem w ciąży, chcę ćwiczyć", answers: complete(goal: .strengthHome, days: 3)))
        XCTAssertNil(pregnant.plan)
        XCTAssertEqual(pregnant.result.answer, TrainingTriage.pregnancyPL)
        XCTAssertEqual(pregnant.result.riskLevel, .moderate)
    }

    func testAnEatingDisorderCueGivesTheFixedTextAndNoNumbers() {
        let reply = TrainingExpert.respond(TrainingTurn(text: "mam bulimię i chcę schudnąć 5 kg w miesiąc"))
        XCTAssertEqual(reply.result.answer, TrainingTriage.eatingPL, "the weight goal is not even looked at")
        XCTAssertNil(reply.plan)
        XCTAssertEqual(reply.result.riskLevel, .high)
        XCTAssertFalse(reply.triage.numbersAllowed)
    }

    // MARK: Test 3: "schudnąć 10 kg w tydzień" gives no extreme restriction

    func testTenKilosInAWeekIsRefusedWithTheSaferPaceAndNoCalories() {
        let polish = TrainingExpert.respond(TrainingTurn(text: "Chcę schudnąć 10 kg w tydzień"))
        XCTAssertNil(polish.plan)
        let answer = polish.result.answer
        XCTAssertTrue(answer.contains("za szybko") && answer.contains("20 tygodni") && answer.contains("0,5 kg"), answer)
        XCTAssertFalse(answer.lowercased().contains("kcal") || answer.lowercased().contains("kalori"))
        XCTAssertEqual(polish.result.riskLevel, .moderate)
        XCTAssertFalse(polish.result.missingData.isEmpty, "it offers to go on with a movement plan")

        let english = TrainingExpert.respond(TrainingTurn(text: "I want to lose 10 kg in a week", language: .english))
        XCTAssertTrue(english.result.answer.contains("too fast") && english.result.answer.contains("20 weeks"))
        XCTAssertNil(english.plan)
    }

    func testAReasonablePaceDoesNotStopThePlan() throws {
        let reply = TrainingExpert.respond(TrainingTurn(text: "chcę schudnąć 2 kg w 8 tygodni", answers: complete(goal: .strengthHome, days: 3)))
        XCTAssertNotNil(reply.plan)
        XCTAssertEqual(reply.result.riskLevel, .low)
        XCTAssertTrue(reply.result.caveats.contains { $0.contains("rozsądn") })
    }

    // MARK: Test 11: without a yes to Apple Health, everything works from what the person says

    func testWithoutConsentHealthIsNeverUsed() throws {
        var answers = complete(goal: .tenK, days: 3, minutes: 60, level: .some)
        answers.longestRecentRunMinutes = nil
        let leaked = TrainingTurn(text: "chcę przebiec 10 km", answers: answers, healthConsent: false, healthLongestRunMinutes: 50)
        let reply = TrainingExpert.respond(leaked)
        let plan = try XCTUnwrap(reply.plan)
        XCTAssertFalse(reply.healthDataUsed)
        XCTAssertEqual(plan.baselineRunMinutes, PlanEngine.defaultBaseline(.some), "the default for the level, not Health's 50")
        XCTAssertFalse(reply.result.caveats.contains { $0.contains("Apple Health") })
    }

    func testWithConsentHealthFillsOnlyAGapAndSaysSo() throws {
        let answers = complete(goal: .tenK, days: 3, minutes: 60, level: .some)
        let used = TrainingExpert.respond(TrainingTurn(text: "chcę przebiec 10 km", answers: answers, healthConsent: true, healthLongestRunMinutes: 40))
        XCTAssertTrue(used.healthDataUsed)
        XCTAssertEqual(used.plan?.baselineRunMinutes, 40)
        XCTAssertTrue(used.result.caveats.contains { $0.contains("Apple Health") })

        var manual = answers
        manual.longestRecentRunMinutes = 35
        let kept = TrainingExpert.respond(TrainingTurn(text: "chcę przebiec 10 km", answers: manual, healthConsent: true, healthLongestRunMinutes: 40))
        XCTAssertFalse(kept.healthDataUsed, "what the person said wins")
        XCTAssertEqual(kept.plan?.baselineRunMinutes, 35)
    }

    // MARK: Test 12: the character stays; the jokes go above low risk

    func testHumorIsOnlyAllowedWhenTheRiskIsLow() {
        let samples: [(TrainingTurn, Bool)] = [
            (TrainingTurn(text: "Trenuję 3 dni"), true),
            (TrainingTurn(text: "x", answers: complete(goal: .strengthHome, days: 3)), true),
            (TrainingTurn(text: "boli mnie w klatce"), false),
            (TrainingTurn(text: "mam zawroty głowy"), false),
            (TrainingTurn(text: "skręciłem kostkę"), false),
            (TrainingTurn(text: "jestem w ciąży"), false),
            (TrainingTurn(text: "mam anoreksję"), false),
            (TrainingTurn(text: "schudnąć 10 kg w tydzień"), false),
        ]
        for (turn, allowed) in samples {
            let reply = TrainingExpert.respond(turn)
            XCTAssertEqual(reply.result.humorAllowed, allowed, turn.text)
            XCTAssertEqual(reply.result.humorAllowed, reply.result.riskLevel == .low, turn.text)
        }
    }

    // MARK: Everything in this slice only explains and proposes

    func testNothingInThisSliceClaimsToHaveDoneAnythingOutside() {
        let texts = ["Trenuję 3 dni", "boli mnie w klatce", "skręciłem kostkę", "jestem w ciąży", "mam bulimię", "schudnąć 10 kg w tydzień",
                     "chcę przebiec 10 km", "", "hello", "I want to start running three days a week"]
        for text in texts {
            for language in [NotificationLanguage.polish, .english] {
                let reply = TrainingExpert.respond(TrainingTurn(text: text, answers: complete(goal: .strengthHome, days: 3), language: language))
                XCTAssertFalse(reply.result.verifiedExternalAction, text)
                XCTAssertNil(reply.result.memoryUpdateProposal, text)
                XCTAssertEqual(reply.result.mode, .personalTraining)
                XCTAssertFalse(reply.result.answer.isEmpty, text)
                XCTAssertFalse(reply.result.answer.lowercased().contains("zapisałem"), text)
            }
        }
    }

    func testARefusalFromTheEngineBecomesAnAnswerNotAPlan() {
        var answers = complete(goal: .tenK, days: 3)
        answers.level = .beginner
        let reply = TrainingExpert.respond(TrainingTurn(text: "10 km", answers: answers))
        XCTAssertNil(reply.plan)
        XCTAssertTrue(reply.result.answer.contains("pierwsze 5 km"))
        var ill = complete(goal: .strengthHome, days: 3)
        ill.screening = PlanScreening(knownCondition: true, symptoms: false, doctorAdvisedLimits: false,
                                      pregnantOrRecentlyGaveBirth: false, injuryOrPain: false, age: 40)
        let doctor = TrainingExpert.respond(TrainingTurn(text: "chcę ćwiczyć", answers: ill))
        XCTAssertNil(doctor.plan)
        XCTAssertEqual(doctor.result.riskLevel, .high)
        XCTAssertTrue(doctor.result.answer.contains("lekarz"))
    }
}
