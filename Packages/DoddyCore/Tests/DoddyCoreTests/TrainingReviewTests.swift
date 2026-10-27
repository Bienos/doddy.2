import XCTest
@testable import DoddyCore

/// ADR-642: the weekly review. One priority, one variable, nothing raised without "reps left",
/// nothing raised on pain or two hard sessions, no shaming and no promises.
final class TrainingReviewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func set(_ key: String, _ reps: Int, kg: Double? = nil, reserve: Int? = 2) -> LoggedSet {
        try! LoggedSet(exerciseKey: key, reps: reps, loadKilograms: kg, repsInReserve: reserve)
    }

    private func session(daysAgo: Double, _ feeling: TrainingFeeling = .okay, sets: [LoggedSet] = [], run: Int? = nil) -> LoggedSession {
        try! LoggedSession(performedAt: now.addingTimeInterval(-daysAgo * day), feeling: feeling, runMinutes: run, sets: sets)
    }

    private func three(_ key: String, reps: Int, kg: Double? = nil, reserve: Int? = 2) -> [LoggedSet] {
        (0..<3).map { _ in set(key, reps, kg: kg, reserve: reserve) }
    }

    private func review(_ sessions: [LoggedSession], plan: TrainingPlan? = nil, atHome: Bool = false) -> TrainingReviewResult {
        TrainingReview.review(sessions: sessions, plan: plan, atHome: atHome, now: now)
    }

    // MARK: Nothing to judge

    func testNothingInTheLastTwoWeeksMeansNoChangeAndALineAboutLoggingNextTime() {
        for sessions in [[LoggedSession](), [session(daysAgo: 15, sets: three("goblet_squat", reps: 12, kg: 10))]] {
            let result = review(sessions)
            XCTAssertEqual(result.priority, .logFirstSession)
            XCTAssertEqual(result.sessionsLookedAt, 0)
            let text = TrainingReview.message(result, language: .polish)
            XCTAssertTrue(text.contains("zostaw plan bez zmian"), text)
        }
    }

    func testTheWindowIsFourteenDays() {
        let edge = review([session(daysAgo: 13.9, sets: three("goblet_squat", reps: 12, kg: 10))])
        XCTAssertEqual(edge.sessionsLookedAt, 1)
        let outside = review([session(daysAgo: 14.1, sets: three("goblet_squat", reps: 12, kg: 10))])
        XCTAssertEqual(outside.sessionsLookedAt, 0)
    }

    // MARK: Pain beats everything

    func testPainStopsEveryIncreaseEvenWhenTheLatestSessionWasReadyForMore() {
        let ready = session(daysAgo: 1, .easy, sets: three("goblet_squat", reps: 12, kg: 10))
        let hurt = session(daysAgo: 9, .pain, sets: three("goblet_squat", reps: 8, kg: 10))
        let result = review([ready, hurt])
        XCTAssertEqual(result.priority, .stopAndGetChecked)
        for language in [NotificationLanguage.polish, .english] {
            let text = TrainingReview.message(result, language: language).lowercased()
            XCTAssertFalse(text.contains("dodaj") || text.contains(" add "), text)
            XCTAssertTrue(text.contains("fizjoterapeut") || text.contains("physiotherapist"), text)
        }
        XCTAssertEqual(TrainingReview.expertResult(result, language: .polish).riskLevel, .high)
        XCTAssertFalse(TrainingReview.expertResult(result, language: .polish).humorAllowed)
    }

    func testPainOlderThanTwoWeeksIsNotHeldAgainstThePerson() {
        let old = session(daysAgo: 20, .pain, sets: three("goblet_squat", reps: 8, kg: 10))
        let fresh = session(daysAgo: 2, .okay, sets: three("goblet_squat", reps: 12, kg: 10))
        XCTAssertNotEqual(review([old, fresh]).priority, .stopAndGetChecked)
    }

    // MARK: Hard sessions

    func testTwoHardSessionsInARowMeanTheSameAsLastTimeAndNothingAdded() {
        let a = session(daysAgo: 1, .hard, sets: three("goblet_squat", reps: 12, kg: 10))
        let b = session(daysAgo: 4, .hard, sets: three("goblet_squat", reps: 12, kg: 10))
        let result = review([a, b])
        XCTAssertEqual(result.priority, .easeOff, "ready for more on paper, but two hard sessions win")
    }

    func testOneHardSessionAloneChangesNothing() {
        let hard = session(daysAgo: 1, .hard, sets: three("goblet_squat", reps: 10, kg: 10))
        let easy = session(daysAgo: 4, .okay, sets: three("goblet_squat", reps: 10, kg: 10))
        XCTAssertNotEqual(review([hard, easy]).priority, .easeOff)
        XCTAssertNotEqual(review([easy, hard]).priority, .easeOff, "the order they are passed in does not matter")
    }

    func testTwoHardRunsAlsoMeanEaseOffAndARunNeverRaisesAnything() {
        XCTAssertEqual(review([session(daysAgo: 1, .hard, run: 30), session(daysAgo: 4, .hard, run: 25)]).priority, .easeOff)
        let calm = review([session(daysAgo: 1, .easy, run: 30)])
        XCTAssertEqual(calm.priority, .keepAsPlanned, "the plan already raises the long run by at most 10%")
        XCTAssertTrue(calm.exercises.isEmpty)
    }

    // MARK: One exercise, one variable

    func testAllSetsAtTheTopWithTwoLeftAddsLoadAndNothingElse() {
        // Lower body +5 kg, upper body +2.5 kg: StrengthProgression's rule, default range 8 to 12.
        let legs = review([session(daysAgo: 2, sets: three("goblet_squat", reps: 12, kg: 16))])
        XCTAssertEqual(legs.priority, .progress(exercise: "goblet_squat", advice: .addLoad(kilograms: 5)))
        let press = review([session(daysAgo: 2, sets: three("dumbbell_shoulder_press", reps: 12, kg: 20))])
        XCTAssertEqual(press.priority, .progress(exercise: "dumbbell_shoulder_press", advice: .addLoad(kilograms: 2.5)))

        let text = TrainingReview.message(legs, language: .polish)
        XCTAssertTrue(text.contains("dodaj 5 kg"), text)
        XCTAssertTrue(text.contains("zacznij od 8 powtórzeń"), "after more load, back to the bottom of the range: \(text)")
        XCTAssertFalse(text.contains("dołóż po 1 powtórzeniu"), "one variable at a time: \(text)")
        XCTAssertTrue(TrainingReview.message(press, language: .polish).contains("dodaj 2,5 kg"))
        XCTAssertTrue(TrainingReview.message(press, language: .english).contains("add 2.5 kg"))
    }

    func testRepsNotYetAtTheTopAddRepsAndNotLoad() {
        let result = review([session(daysAgo: 2, sets: three("goblet_squat", reps: 10, kg: 16))])
        XCTAssertEqual(result.priority, .progress(exercise: "goblet_squat", advice: .addReps))
        let text = TrainingReview.message(result, language: .english)
        XCTAssertTrue(text.contains("add 1 rep to each set, up to 12"), text)
        XCTAssertFalse(text.contains(" kg"), "the load stays: \(text)")
    }

    func testAtHomeTheNextStepIsAHarderVersionAndNotAWeight() {
        let result = review([session(daysAgo: 2, sets: three("push_up", reps: 12, reserve: 2))], atHome: true)
        XCTAssertEqual(result.priority, .progress(exercise: "push_up", advice: .harderVariation))
        XCTAssertFalse(TrainingReview.message(result, language: .polish).contains(" kg"))
    }

    func testAHoldGetsALongerHoldNeverAWeight() {
        for atHome in [true, false] {
            let result = review([session(daysAgo: 2, sets: three("plank", reps: 40))], atHome: atHome)
            XCTAssertEqual(result.priority, .progress(exercise: "plank", advice: .longerHold))
            let text = TrainingReview.message(result, language: .polish)
            XCTAssertTrue(text.contains("do 40 s"), text)
            XCTAssertFalse(text.contains(" kg"), text)
        }
    }

    func testSetsShortOfTheRangeMeanLighterAndOnlyThenTheEasierVersionIsNamed() {
        let sets = [set("goblet_squat", 5, kg: 20, reserve: 0), set("goblet_squat", 6, kg: 20, reserve: 0), set("goblet_squat", 9, kg: 20, reserve: 1)]
        let result = review([session(daysAgo: 2, sets: sets)])
        XCTAssertEqual(result.priority, .lighter(exercise: "goblet_squat"))
        let text = TrainingReview.message(result, language: .polish)
        XCTAssertTrue(text.contains("lżej"), text)
        XCTAssertTrue(text.contains("Łatwiejsza wersja: Przysiad bez ciężaru"), text)
        XCTAssertEqual(TrainingReview.expertResult(result, language: .polish).riskLevel, .moderate)
    }

    // MARK: Nothing raised without "reps left"

    func testASetWithoutHowManyRepsWereLeftNeverRaisesAnything() {
        let result = review([session(daysAgo: 2, sets: three("goblet_squat", reps: 12, kg: 16, reserve: nil))])
        XCTAssertEqual(result.priority, .keepAsPlanned)
        XCTAssertTrue(result.exercises[0].missingReserve)
        let text = TrainingReview.message(result, language: .polish)
        XCTAssertTrue(text.contains("ile powtórzeń jeszcze byś zrobił"), text)
    }

    func testOneSetTakenToFailureKeepsTheLoad() {
        var sets = three("goblet_squat", reps: 12, kg: 16)
        sets[2] = set("goblet_squat", 12, kg: 16, reserve: 0)
        XCTAssertEqual(review([session(daysAgo: 2, sets: sets)]).priority, .keepAsPlanned)
    }

    // MARK: One priority

    func testWithTwoExercisesReadyOnlyTheFirstOneIsNamed() {
        let sets = three("goblet_squat", reps: 12, kg: 16) + three("dumbbell_shoulder_press", reps: 12, kg: 20)
        let result = review([session(daysAgo: 2, sets: sets)])
        XCTAssertEqual(result.priority, .progress(exercise: "goblet_squat", advice: .addLoad(kilograms: 5)))
        XCTAssertEqual(result.exercises.map(\.key), ["goblet_squat", "dumbbell_shoulder_press"], "the screens may still show both")
        let text = TrainingReview.message(result, language: .english)
        XCTAssertFalse(text.lowercased().contains("press"), "the words name one thing: \(text)")
    }

    func testLighterComesBeforeProgress() {
        let slow = [set("goblet_squat", 5, kg: 20, reserve: 0), set("goblet_squat", 6, kg: 20, reserve: 0)]
        let sets = three("dumbbell_shoulder_press", reps: 12, kg: 20) + slow
        XCTAssertEqual(review([session(daysAgo: 2, sets: sets)]).priority, .lighter(exercise: "goblet_squat"))
    }

    // MARK: The plan and the last two weeks

    func testThePlansOwnRangeIsUsedWhenThePlanHasTheExercise() throws {
        let request = PlanRequest(goal: .strengthGym, level: .beginner, daysPerWeek: 3, minutesPerSession: 45, screening: .clear(age: 30))
        guard case .plan(let plan) = PlanEngine.make(request) else { return XCTFail("a plain gym plan") }
        let planned = try XCTUnwrap(plan.weeks.flatMap(\.sessions).flatMap(\.exercises).first { $0.unit == .reps })
        let atTop = review([session(daysAgo: 1, sets: three(planned.key, reps: planned.high, kg: 20))], plan: plan)
        guard case .progress(let key, let advice) = atTop.priority else { return XCTFail("\(atTop.priority)") }
        XCTAssertEqual(key, planned.key)
        XCTAssertEqual(advice, .addLoad(kilograms: planned.lowerBody ? 5 : 2.5))
        XCTAssertEqual(atTop.exercises[0].low, planned.low)
        XCTAssertEqual(atTop.exercises[0].high, planned.high)
        if planned.high - 1 >= planned.low {
            let below = review([session(daysAgo: 1, sets: three(planned.key, reps: planned.high - 1, kg: 20))], plan: plan)
            XCTAssertEqual(below.priority, .progress(exercise: planned.key, advice: .addReps))
        }
    }

    func testTheLatestSessionOfAnExerciseIsJudgedAndTheOneBeforeIsCompared() {
        let before = session(daysAgo: 9, sets: three("goblet_squat", reps: 10, kg: 16))
        let latest = session(daysAgo: 2, sets: three("goblet_squat", reps: 12, kg: 16))
        let result = review([before, latest])
        XCTAssertEqual(result.exercises[0].latest.totalReps, 36)
        XCTAssertEqual(result.exercises[0].previous?.totalReps, 30)
        let text = TrainingReview.message(result, language: .polish)
        XCTAssertTrue(text.contains("W ostatnim treningu razem 36 powtórzeń, wcześniej 30."), text)
        XCTAssertTrue(TrainingReview.message(result, language: .english).contains("In your last session 36 reps in total, before that 30."))
    }

    func testTotalsAreNotComparedAcrossDifferentLoads() {
        let before = session(daysAgo: 9, sets: three("goblet_squat", reps: 12, kg: 12))
        let latest = session(daysAgo: 2, sets: three("goblet_squat", reps: 12, kg: 16))
        let text = TrainingReview.message(review([before, latest]), language: .polish)
        XCTAssertFalse(text.contains("wcześniej"), text)
    }

    // MARK: Honesty of the words

    func testTheSameLogGivesTheSameAnswerWhateverTheOrder() {
        let sessions = [
            session(daysAgo: 1, .okay, sets: three("goblet_squat", reps: 12, kg: 16)),
            session(daysAgo: 4, .okay, sets: three("goblet_squat", reps: 11, kg: 16)),
            session(daysAgo: 8, .easy, sets: three("dumbbell_shoulder_press", reps: 9, kg: 20)),
        ]
        let expected = review(sessions)
        XCTAssertEqual(review(sessions.reversed()), expected)
        XCTAssertEqual(review([sessions[1], sessions[2], sessions[0]]), expected)
    }

    /// No shaming, no counting of what was missed, no promise about where the person will end up.
    func testNoWordInAnyReviewShamesOrPromises() {
        let priorities: [ReviewPriority] = [
            .logFirstSession, .stopAndGetChecked, .easeOff, .lighter(exercise: "goblet_squat"),
            .progress(exercise: "goblet_squat", advice: .addLoad(kilograms: 5)),
            .progress(exercise: "push_up", advice: .harderVariation),
            .progress(exercise: "goblet_squat", advice: .addReps),
            .progress(exercise: "plank", advice: .longerHold), .keepAsPlanned,
        ]
        let banned = [
            "gwarant", "na pewno", "schudn", "przemian", "leniw", "porażk", "zawiod", "opuści", "pominę", "seria dni", "rekord",
            "guarantee", "transform", "lazy", "fail", "missed", "skipped", "streak", "you will lose", "you'll lose", "best version",
            "kcal", "kalor", "calor",
        ]
        for priority in priorities {
            let result = TrainingReviewResult(priority: priority, exercises: [], sessionsLookedAt: 1)
            for language in [NotificationLanguage.polish, .english] {
                let text = TrainingReview.message(result, language: language).lowercased()
                XCTAssertFalse(text.isEmpty)
                for word in banned { XCTAssertFalse(text.contains(word), "\"\(word)\" in: \(text)") }
            }
        }
    }

    func testTheReviewAsAnExpertResultClaimsNothingItDidNotDo() throws {
        let result = review([session(daysAgo: 2, sets: three("goblet_squat", reps: 12, kg: 16))])
        let expert = TrainingReview.expertResult(result, language: .english)
        XCTAssertEqual(expert.mode, .personalTraining)
        XCTAssertTrue(expert.proposedActions.isEmpty, "nothing is changed in the plan; the person decides")
        XCTAssertNil(expert.memoryUpdateProposal)
        XCTAssertFalse(expert.verifiedExternalAction)
        XCTAssertEqual(expert.sources, [.acsm2026])
        XCTAssertTrue(expert.caveats.contains { $0.contains("not a certified trainer") })
        XCTAssertTrue(expert.humorAllowed)
        XCTAssertEqual(TrainingReview.expertResult(review([]), language: .english).missingData, ["training_log"])
    }

    // MARK: The tables the review keeps next to the engine's

    /// `timedKeys` and the lower-body rule are copies of what the engine knows. If the menu changes,
    /// this fails instead of a plank being advised "more weight".
    func testTheReviewAgreesWithTheEngineAboutWhichExercisesAreTimedAndLowerBody() {
        var seen: [String: (timed: Bool, lower: Bool)] = [:]
        for goal in [PlanGoal.strengthHome, .strengthGym] {
            for level in PlanLevel.allCases {
                for days in 2...5 {
                    for minutes in [25, 45, 90] {
                        let request = PlanRequest(goal: goal, level: level, daysPerWeek: days, minutesPerSession: minutes,
                                                  screening: .clear(age: 30))
                        guard case .plan(let plan) = PlanEngine.make(request) else { continue }
                        for e in plan.weeks.flatMap(\.sessions).flatMap(\.exercises) {
                            seen[e.key] = (e.unit == .seconds, e.lowerBody)
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThanOrEqual(seen.count, 20)
        for (key, facts) in seen {
            XCTAssertEqual(TrainingReview.isTimedHold(key), facts.timed, "timed: \(key)")
            XCTAssertEqual(TrainingReview.isLowerBody(key), facts.lower, "lower body: \(key)")
        }
    }
}
