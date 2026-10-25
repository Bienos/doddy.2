import XCTest
@testable import DoddyCore

/// ADR-642: ask only what is missing, never more than five questions, never assume the safety answers.
final class TrainingInterviewTests: XCTestCase {
    func testTheDaysAreTakenFromTheWords() {
        XCTAssertEqual(TrainingInterview.extract(from: "Trenuję 3 dni").daysPerWeek, 3)
        XCTAssertEqual(TrainingInterview.extract(from: "mogę trzy razy w tygodniu").daysPerWeek, 3)
        XCTAssertEqual(TrainingInterview.extract(from: "ćwiczę 4x w tygodniu").daysPerWeek, 4)
        XCTAssertEqual(TrainingInterview.extract(from: "I can train three days a week").daysPerWeek, 3)
        XCTAssertNil(TrainingInterview.extract(from: "mam 10 dni urlopu").daysPerWeek, "10 is not days of training")
        XCTAssertNil(TrainingInterview.extract(from: "chcę przebiec 5 km").daysPerWeek)
    }

    func testTheGoalIsTakenFromTheWords() {
        let cases: [(String, PlanGoal)] = [
            ("chcę przebiec 10 km", .tenK), ("trenuję do półmaratonu", .halfMarathon), ("I want to run a half marathon", .halfMarathon),
            ("chcę zacząć biegać", .firstFiveK), ("pierwsze 5 km", .firstFiveK), ("couch to 5k", .firstFiveK),
            ("ćwiczę na siłowni", .strengthGym), ("I go to the gym", .strengthGym),
            ("chcę ćwiczyć siłowo w domu", .strengthHome), ("strength workouts at home", .strengthHome),
        ]
        for (text, goal) in cases { XCTAssertEqual(TrainingInterview.extract(from: text).goal, goal, text) }
        XCTAssertNil(TrainingInterview.extract(from: "Trenuję 3 dni").goal)
        XCTAssertNil(TrainingInterview.extract(from: "gymnastics class").goal, "gym inside a longer word is not the gym")
    }

    func testMinutesAndLevel() {
        XCTAssertEqual(TrainingInterview.extract(from: "mam 45 minut").minutesPerSession, 45)
        XCTAssertEqual(TrainingInterview.extract(from: "about 30 minutes").minutesPerSession, 30)
        XCTAssertNil(TrainingInterview.extract(from: "5 minut").minutesPerSession)
        XCTAssertNil(TrainingInterview.extract(from: "500 minut").minutesPerSession)
        XCTAssertEqual(TrainingInterview.extract(from: "jestem początkujący").level, .beginner)
        XCTAssertEqual(TrainingInterview.extract(from: "I train regularly").level, .regular)
        XCTAssertEqual(TrainingInterview.extract(from: "ćwiczę czasami").level, .some)
        XCTAssertNil(TrainingInterview.extract(from: "Trenuję 3 dni").level, "\"trenuję\" alone says nothing about the level")
    }

    func testWhatWasSaidBeforeIsNeverOverwritten() {
        var known = TrainingAnswers()
        known.goal = .strengthHome
        known.daysPerWeek = 2
        let after = TrainingInterview.extract(from: "teraz 4 dni i półmaraton i 60 minut", into: known)
        XCTAssertEqual(after.goal, .strengthHome)
        XCTAssertEqual(after.daysPerWeek, 2)
        XCTAssertEqual(after.minutesPerSession, 60, "an answer that was missing is filled in")
    }

    func testOnlyTheMissingQuestionsAreAskedAndNeverMoreThanFive() {
        XCTAssertEqual(TrainingInterview.maxQuestions, 5)
        let said = TrainingInterview.extract(from: "Trenuję 3 dni")
        guard case .ask(let questions) = TrainingInterview.next(said) else { return XCTFail("a plan needs more than the days") }
        XCTAssertEqual(questions, [.goal, .level, .minutesPerSession, .screening])
        XCTAssertFalse(questions.contains(.daysPerWeek), "the days were already said")
        XCTAssertLessThanOrEqual(questions.count, TrainingInterview.maxQuestions)
        guard case .ask(let all) = TrainingInterview.next(TrainingAnswers()) else { return XCTFail() }
        XCTAssertEqual(all.count, 5)
    }

    func testTheSafetyQuestionsAreNeverAssumed() {
        var answers = TrainingAnswers(goal: .strengthHome, level: .beginner, daysPerWeek: 3, minutesPerSession: 45)
        guard case .ask(let questions) = TrainingInterview.next(answers) else { return XCTFail("no plan without the screening") }
        XCTAssertEqual(questions, [.screening])
        answers.screening = .clear(age: 30)
        guard case .ready(let request) = TrainingInterview.next(answers) else { return XCTFail("everything is there") }
        XCTAssertEqual(request.goal, .strengthHome)
        XCTAssertEqual(request.daysPerWeek, 3)
        XCTAssertEqual(request.screening, .clear(age: 30))
        // Whatever the text says, extraction never answers the screening.
        XCTAssertNil(TrainingInterview.extract(from: "nic mi nie jest, nie mam żadnych objawów, mam 30 lat").screening)
    }

    func testEveryQuestionHasWordsInBothLanguages() {
        for question in TrainingQuestion.allCases {
            for language in [NotificationLanguage.polish, .english] {
                XCTAssertGreaterThan(TrainingInterview.prompt(question, language: language).count, 10)
            }
        }
    }
}
