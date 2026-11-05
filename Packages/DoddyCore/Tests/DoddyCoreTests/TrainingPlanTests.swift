import Foundation
import XCTest
@testable import DoddyCore

/// Sport mode step 4 (ADR-624): plans worked out by code, with the research's safety rules.
final class TrainingPlanTests: XCTestCase {
    private func request(_ goal: PlanGoal, _ level: PlanLevel = .some, days: Int = 3, minutes: Int = 45,
                         longest: Int? = nil, screening: PlanScreening = .clear(age: 30)) -> PlanRequest {
        PlanRequest(goal: goal, level: level, daysPerWeek: days, minutesPerSession: minutes,
                    longestRecentRunMinutes: longest, screening: screening)
    }

    private func plan(_ request: PlanRequest, file: StaticString = #filePath, line: UInt = #line) -> TrainingPlan? {
        guard case .plan(let plan) = PlanEngine.make(request) else {
            XCTFail("expected a plan, got \(PlanEngine.make(request))", file: file, line: line)
            return nil
        }
        return plan
    }

    // MARK: Safety first

    func testScreeningRefusesAndSaysWhoToAsk() {
        var screening = PlanScreening.clear(age: 30)
        screening.symptoms = true
        XCTAssertEqual(PlanEngine.make(request(.tenK, screening: screening)), .refused(.seeDoctorFirst))
        screening = .clear(age: 30); screening.knownCondition = true
        XCTAssertEqual(PlanEngine.make(request(.strengthGym, screening: screening)), .refused(.seeDoctorFirst))
        screening = .clear(age: 30); screening.doctorAdvisedLimits = true
        XCTAssertEqual(PlanEngine.make(request(.firstFiveK, screening: screening)), .refused(.seeDoctorFirst))
        screening = .clear(age: 30); screening.pregnantOrRecentlyGaveBirth = true
        XCTAssertEqual(PlanEngine.make(request(.firstFiveK, screening: screening)), .refused(.pregnancy))
        screening.injuryOrPain = true
        XCTAssertEqual(PlanEngine.make(request(.firstFiveK, screening: screening)), .refused(.injury), "injury names the person to see first")
        XCTAssertEqual(PlanEngine.make(request(.strengthHome, screening: .clear(age: 15))), .refused(.tooYoung))
    }

    func testTheGoalMustFit() {
        XCTAssertEqual(PlanEngine.make(request(.halfMarathon, .beginner)), .refused(.notReadyFor(.halfMarathon, suggested: .firstFiveK)))
        XCTAssertEqual(PlanEngine.make(request(.tenK, .beginner)), .refused(.notReadyFor(.tenK, suggested: .firstFiveK)))
        XCTAssertEqual(PlanEngine.make(request(.halfMarathon, .regular, screening: .clear(age: 17))),
                       .refused(.notReadyFor(.halfMarathon, suggested: .tenK)))
        XCTAssertEqual(PlanEngine.make(request(.tenK, days: 1)), .refused(.needsMoreDays(minimum: 2)))
        XCTAssertEqual(PlanEngine.make(request(.firstFiveK, .beginner, minutes: 35)), .refused(.needsMoreTime(minimumMinutes: 40)))
        XCTAssertEqual(PlanEngine.make(request(.strengthHome, minutes: 20)), .refused(.needsMoreTime(minimumMinutes: 25)))
        XCTAssertEqual(PlanEngine.make(request(.tenK, minutes: 15)), .refused(.needsMoreTime(minimumMinutes: 20)))
    }

    // MARK: Every plan keeps every rule

    func testEveryPlanTheEngineMakesKeepsTheRules() {
        var plans = 0
        for goal in PlanGoal.allCases {
            for level in PlanLevel.allCases {
                for days in 1...6 {
                    for minutes in [15, 20, 25, 30, 40, 45, 60, 90] {
                        for longest in [nil, 10, 20, 45, 90, 200] as [Int?] {
                            for age in [16, 17, 30, 70] {
                                let r = request(goal, level, days: days, minutes: minutes, longest: longest, screening: .clear(age: age))
                                guard case .plan(let plan) = PlanEngine.make(r) else { continue }
                                plans += 1
                                let found = PlanRules.violations(plan)
                                XCTAssertEqual(found, [], "\(goal) \(level) \(days) days \(minutes) min longest \(String(describing: longest)) age \(age)")
                                if !found.isEmpty { return }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(plans, 1000, "the loop really made plans")
    }

    // MARK: From zero to 5 km

    func testFirstFiveKBuildsToThirtyMinutes() {
        guard let plan = plan(request(.firstFiveK, .beginner, days: 4, minutes: 45)) else { return }
        XCTAssertEqual(plan.weeks.count, 12)
        XCTAssertEqual(plan.weeks[0].sessions.map(\.day), [2, 4, 6], "three days are enough, even when four are free")
        XCTAssertEqual(plan.weeks[0].sessions[0].runWalk, RunWalk(runSeconds: 60, walkSeconds: 90, repeats: 8))
        XCTAssertEqual(plan.weeks[0].sessions[0].minutes, 29, "5 min walk, 18.5 min block, 5 min walk")
        XCTAssertEqual(plan.weeks[11].sessions[0].runWalk, RunWalk(runSeconds: 1800, walkSeconds: 0, repeats: 1))
        XCTAssertTrue(plan.weeks.allSatisfy { $0.sessions.allSatisfy { $0.effort == .easy && $0.hardMinutes == 0 } })
        guard let twoDays = self.plan(request(.firstFiveK, .beginner, days: 2, minutes: 40)) else { return }
        XCTAssertEqual(twoDays.weeks.count, 14)
        XCTAssertEqual(twoDays.weeks[0].sessions.map(\.day), [2, 6])
    }

    // MARK: 10 km and half marathon

    func testTenKLongRunsGrowByAtMostTenPercentWithAnEasierFourthWeek() {
        guard let plan = plan(request(.tenK, .some, days: 3, minutes: 45, longest: 30)) else { return }
        let longs = plan.weeks.map { $0.sessions.first { $0.kind == .longRun }?.minutes }
        XCTAssertEqual(longs, [33, 36, 39, 31, 42, 46, 50, 55])
        XCTAssertEqual(plan.weeks.map(\.easier), [false, false, false, true, false, false, false, false])
        XCTAssertTrue(plan.weeks[7].taper)
        XCTAssertEqual(plan.baselineRunMinutes, 30)
        XCTAssertFalse(plan.weeks[0].sessions.contains(where: \.isHard), "someone who runs now and then gets no hard session in weeks 1 and 2")
        XCTAssertTrue(plan.weeks[2].sessions.contains(where: \.isHard))
        XCTAssertFalse(plan.weeks[3].sessions.contains(where: \.isHard), "nothing hard in the easier week")
    }

    func testHalfMarathonForARegularRunner() {
        guard let plan = plan(request(.halfMarathon, .regular, days: 5, minutes: 60)) else { return }
        XCTAssertEqual(plan.weeks.count, 12)
        XCTAssertEqual(plan.baselineRunMinutes, 45)
        XCTAssertEqual(plan.weeks[0].sessions.map(\.day), [1, 2, 4, 5, 7])
        XCTAssertEqual(plan.weeks[0].sessions.last?.kind, .longRun)
        XCTAssertEqual(plan.weeks[0].sessions[1].kind, .tempoRun)
        XCTAssertEqual(plan.weeks[1].sessions[1].kind, .intervals)
        XCTAssertEqual(plan.weeks.filter(\.easier).map(\.number), [4, 8])
        let longest = plan.weeks.compactMap { $0.sessions.first { $0.kind == .longRun }?.minutes }.max()
        XCTAssertLessThanOrEqual(longest ?? 0, 120)
        for week in plan.weeks {
            let run = week.sessions.reduce(0) { $0 + $1.minutes }
            let hard = week.sessions.reduce(0) { $0 + $1.hardMinutes }
            XCTAssertLessThanOrEqual(Double(hard), 0.2 * Double(run), "80/20 in week \(week.number)")
            XCTAssertTrue(week.sessions.filter { $0.kind != .longRun }.allSatisfy { $0.minutes <= 60 })
        }
    }

    // MARK: Strength

    func testBeginnerHomeStrength() {
        guard let plan = plan(request(.strengthHome, .beginner, days: 5, minutes: 45)) else { return }
        XCTAssertEqual(plan.weeks.count, 8)
        XCTAssertEqual(plan.weeks[0].sessions.map(\.day), [1, 3, 5], "full-body days need a day between them")
        XCTAssertEqual(plan.weeks[0].sessions[0].exercises.first?.sets, 2)
        XCTAssertEqual(plan.weeks[2].sessions[0].exercises.first?.sets, 3)
        XCTAssertEqual(plan.weeks[3].sessions[0].exercises.first?.sets, 2, "the easier week drops a set")
        XCTAssertTrue(plan.weeks[0].sessions[0].exercises.contains { $0.key == "incline_push_up" })
        XCTAssertTrue(plan.weeks.flatMap(\.sessions).flatMap(\.exercises).allSatisfy { $0.repsInReserve >= 2 })
    }

    func testRegularGymFourDaysIsUpperAndLower() {
        guard let plan = plan(request(.strengthGym, .regular, days: 4, minutes: 60)) else { return }
        let week = plan.weeks[0].sessions
        XCTAssertEqual(week.map(\.day), [1, 2, 4, 5])
        XCTAssertTrue(week[0].exercises.allSatisfy { !$0.lowerBody })
        XCTAssertTrue(week[1].exercises.allSatisfy(\.lowerBody))
    }

    func testShortSessionsDropExercisesThenSets() {
        guard let plan = plan(request(.strengthGym, .some, days: 3, minutes: 30)) else { return }
        let session = plan.weeks[0].sessions[0]
        XCTAssertEqual(session.exercises.count, 3)
        XCTAssertEqual(session.exercises.first?.sets, 2)
        XCTAssertLessThanOrEqual(session.minutes, 30)
    }

    func testSixteenAndSeventeenGetLighterWork() {
        guard let plan = plan(request(.strengthGym, .some, days: 3, minutes: 60, screening: .clear(age: 17))) else { return }
        let reps = plan.weeks.flatMap(\.sessions).flatMap(\.exercises).filter { $0.unit == .reps }
        XCTAssertTrue(reps.allSatisfy { $0.low >= 10 && $0.high == 15 && $0.repsInReserve == 3 })
    }

    // MARK: The rules catch a bad plan

    func testTheRulesCatchWhatTheEngineNeverMakes() {
        let r = request(.tenK, .regular, days: 3, minutes: 45, longest: 30)
        let weeks = [
            PlanWeek(number: 1, sessions: [
                PlanSession(day: 2, kind: .intervals, minutes: 40, hardMinutes: 25,
                            intervals: Intervals(repeats: 5, workSeconds: 300, recoverySeconds: 60)),
                PlanSession(day: 3, kind: .tempoRun, minutes: 30, hardMinutes: 20, tempoMinutes: 20),
                PlanSession(day: 6, kind: .longRun, minutes: 50),
                PlanSession(day: 7, kind: .easyRun, minutes: 60),
            ]),
            PlanWeek(number: 2, sessions: [
                PlanSession(day: 1, kind: .strength, minutes: 40, exercises: [
                    StrengthExercise(key: "back_squat", name: "Back squat", lowerBody: true, sets: 6, low: 3, high: 5, unit: .reps, repsInReserve: 0),
                ]),
            ]),
        ]
        let bad = TrainingPlan(request: r, weeks: weeks, baselineRunMinutes: 30)
        let found = PlanRules.violations(bad)
        XCTAssertTrue(found.contains(.runTooLong(week: 1, day: 6)), "50 min after a 30 min start")
        XCTAssertTrue(found.contains(.tooMuchHard(week: 1)), "45 of 180 minutes hard")
        XCTAssertTrue(found.contains(.hardBackToBack(week: 1, day: 3)))
        XCTAssertTrue(found.contains(.tooManyDays(week: 1)))
        XCTAssertTrue(found.contains(.weekdayTooLong(week: 1, day: 7)))
        XCTAssertTrue(found.contains(.strengthTooHard(week: 2, day: 1, exercise: "back_squat")))
    }

    // MARK: When to add load

    func testProgression() {
        let top = [SetResult(reps: 12, repsInReserve: 2), SetResult(reps: 12, repsInReserve: 3), SetResult(reps: 12, repsInReserve: 2)]
        XCTAssertEqual(StrengthProgression.next(after: top, low: 8, high: 12, lowerBody: true, atHome: false), .addLoad(kilograms: 5))
        XCTAssertEqual(StrengthProgression.next(after: top, low: 8, high: 12, lowerBody: false, atHome: false), .addLoad(kilograms: 2.5))
        XCTAssertEqual(StrengthProgression.next(after: top, low: 8, high: 12, lowerBody: false, atHome: true), .harderVariation)
        let middle = [SetResult(reps: 10, repsInReserve: 2), SetResult(reps: 9, repsInReserve: 2)]
        XCTAssertEqual(StrengthProgression.next(after: middle, low: 8, high: 12, lowerBody: true, atHome: false), .addReps)
        let failure = [SetResult(reps: 12, repsInReserve: 2), SetResult(reps: 12, repsInReserve: 0)]
        XCTAssertEqual(StrengthProgression.next(after: failure, low: 8, high: 12, lowerBody: true, atHome: false), .keep, "a set to failure: no more load")
        let short = [SetResult(reps: 6, repsInReserve: 1), SetResult(reps: 5, repsInReserve: 0), SetResult(reps: 9, repsInReserve: 2)]
        XCTAssertEqual(StrengthProgression.next(after: short, low: 8, high: 12, lowerBody: true, atHome: false), .lighter)
        XCTAssertEqual(StrengthProgression.next(after: [], low: 8, high: 12, lowerBody: true, atHome: false), .keep)
    }
}
