import XCTest
@testable import DoddyCore

/// ADR-632: a text card for every exercise the plan engine can prescribe.
final class ExerciseCardTests: XCTestCase {
    /// Every exercise key any strength plan can contain, over the answers the screens allow.
    private func prescribedKeys() -> Set<String> {
        var keys: Set<String> = []
        for goal in [PlanGoal.strengthHome, .strengthGym] {
            for level in PlanLevel.allCases {
                for days in 2...5 {
                    for minutes in [25, 30, 45, 60, 90] {
                        for age in [17, 30] {
                            let request = PlanRequest(goal: goal, level: level, daysPerWeek: days, minutesPerSession: minutes,
                                                      screening: .clear(age: age))
                            guard case .plan(let plan) = PlanEngine.make(request) else { continue }
                            for week in plan.weeks { for session in week.sessions { for e in session.exercises { keys.insert(e.key) } } }
                        }
                    }
                }
            }
        }
        return keys
    }

    func testEveryExerciseThePlansCanPrescribeHasACard() {
        let keys = prescribedKeys()
        XCTAssertGreaterThanOrEqual(keys.count, 20, "the sweep should reach the whole menu")
        for key in keys.sorted() { XCTAssertNotNil(ExerciseCatalogue.card(forKey: key), "no card for \(key)") }
    }

    func testThereAreEnoughCardsAndTheirIDsAreUnique() {
        XCTAssertGreaterThanOrEqual(ExerciseCatalogue.all.count, 12)
        let ids = ExerciseCatalogue.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertNotNil(ExerciseCatalogue.card(forKey: "run_walk"))
        XCTAssertNotNil(ExerciseCatalogue.card(forKey: "easy_run"))
        XCTAssertNil(ExerciseCatalogue.card(forKey: "no_such_exercise"))
        let patterns = Set(ExerciseCatalogue.all.map(\.pattern))
        XCTAssertTrue(patterns.isSuperset(of: [.squat, .hinge, .push, .pull, .locomotion]))
    }

    func testEveryCardIsCompleteBilingualAndCited() {
        for card in ExerciseCatalogue.all {
            XCTAssertFalse(card.name.pl.isEmpty || card.name.en.isEmpty, card.id)
            XCTAssertFalse(card.primaryMuscles.isEmpty, card.id)
            XCTAssertGreaterThanOrEqual(card.coachingCues.count, 2, card.id)
            XCTAssertGreaterThanOrEqual(card.commonIssues.count, 2, card.id)
            XCTAssertNotNil(card.easierVersion, card.id)
            XCTAssertFalse(card.sources.isEmpty, card.id)
            for source in card.sources {
                XCTAssertTrue(source.url.hasPrefix("https://"), card.id)
                XCTAssertEqual(source.checkedAt, "2026-10-24", card.id)
            }
            XCTAssertEqual(card.reviewedAt, "2026-10-24", card.id)
            for text in card.coachingCues + card.commonIssues + [card.name, card.safety] {
                XCTAssertFalse(text.pl.isEmpty || text.en.isEmpty, card.id)
            }
        }
    }

    func testEverySafetyLineSaysStopAndDoesNotGuessTheCause() {
        for card in ExerciseCatalogue.all {
            XCTAssertTrue(card.safety.pl.contains("ostrym bólu") && card.safety.pl.contains("lekarzowi"), card.id)
            XCTAssertTrue(card.safety.en.contains("sharp pain") && card.safety.en.contains("doctor"), card.id)
        }
    }

    func testNoCardMakesAMedicalClaimOrPointsToAPicture() throws {
        let banned = ["rehab", "cure", "heal", "detect", "predict", "injury risk", "leczy", "wyleczy", "ryzyko kontuzji", "diagnoz"]
        for card in ExerciseCatalogue.all {
            let data = try JSONEncoder().encode(card)
            let text = String(decoding: data, as: UTF8.self).lowercased()
            for word in banned { XCTAssertFalse(text.contains(word), "\(card.id): \(word)") }
            for image in [".jpg", ".jpeg", ".png", ".gif", ".webp", ".mp4", ".mov"] { XCTAssertFalse(text.contains(image), card.id) }
            XCTAssertTrue(card.wording.contains("No atlas"), card.id)
        }
    }

    func testTheLoadingRuleIsCitedFromTheTwoGuidelines() {
        let squat = ExerciseCatalogue.card(forKey: "squat")
        XCTAssertEqual(squat?.sources.map(\.url), ["https://www.ncbi.nlm.nih.gov/books/NBK566046/", "https://pmc.ncbi.nlm.nih.gov/articles/PMC12965823/"])
        let run = ExerciseCatalogue.card(forKey: "run_walk")
        XCTAssertTrue(run?.sources.contains(.frandsen2025) == true)
        XCTAssertTrue(run?.wording.contains("only the idea") == true, "the table is Doddy's own, not copied from the NHS")
    }

    func testACardSurvivesJSON() throws {
        let card = try XCTUnwrap(ExerciseCatalogue.card(forKey: "goblet_squat"))
        XCTAssertEqual(try JSONDecoder().decode(ExerciseCard.self, from: JSONEncoder().encode(card)), card)
        XCTAssertEqual(card.equipment, ["kettlebell", "dumbbell"])
        XCTAssertEqual(card.name.text(.polish), "Przysiad goblet")
        XCTAssertEqual(card.name.text(.english), "Goblet squat")
    }
}
