import XCTest
@testable import DoddyCore

/// ADR-632: the rules of a logged set and a logged session, and the export file. The store itself is
/// tested on real SQLite in DoddyPersistenceTests.
final class TrainingLogTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func problem(_ build: () throws -> Void) -> TrainingLogProblem? {
        do { try build() } catch TrainingLogError.invalid(let problem) { return problem } catch { return nil }
        return nil
    }

    // MARK: Sets

    func testALoadIsKeptInGramsSoItComparesExactly() throws {
        let set = try LoggedSet(exerciseKey: "goblet_squat", reps: 10, loadKilograms: 2.5, repsInReserve: 2)
        XCTAssertEqual(set.loadGrams, 2500)
        XCTAssertEqual(set.loadKilograms, 2.5)
        XCTAssertEqual(try LoggedSet(exerciseKey: "goblet_squat", reps: 10, loadKilograms: 62.35).loadGrams, 62_350)
        XCTAssertNil(try LoggedSet(exerciseKey: "push_up", reps: 12).loadGrams, "bodyweight has no load")
    }

    func testASetThatBreaksARuleIsRefusedWithTheRule() {
        XCTAssertEqual(problem { _ = try LoggedSet(exerciseKey: "", reps: 5) }, .badExerciseKey)
        XCTAssertEqual(problem { _ = try LoggedSet(exerciseKey: "Goblet Squat", reps: 5) }, .badExerciseKey, "a key is not free text")
        XCTAssertEqual(problem { _ = try LoggedSet(exerciseKey: "ć", reps: 5) }, .badExerciseKey)
        XCTAssertEqual(problem { _ = try LoggedSet(exerciseKey: String(repeating: "a", count: 49), reps: 5) }, .badExerciseKey)
        XCTAssertEqual(problem { _ = try LoggedSet(exerciseKey: "squat", reps: -1) }, .badReps)
        XCTAssertEqual(problem { _ = try LoggedSet(exerciseKey: "squat", reps: 201) }, .badReps)
        XCTAssertEqual(problem { _ = try LoggedSet(exerciseKey: "squat", reps: 5, loadKilograms: -1) }, .badLoad)
        XCTAssertEqual(problem { _ = try LoggedSet(exerciseKey: "squat", reps: 5, loadKilograms: 501) }, .badLoad)
        XCTAssertEqual(problem { _ = try LoggedSet(exerciseKey: "squat", reps: 5, loadKilograms: .nan) }, .badLoad)
        XCTAssertEqual(problem { _ = try LoggedSet(exerciseKey: "squat", reps: 5, loadKilograms: .infinity) }, .badLoad)
        XCTAssertEqual(problem { _ = try LoggedSet(exerciseKey: "squat", reps: 5, repsInReserve: 11) }, .badReserve)
        XCTAssertEqual(problem { _ = try LoggedSet(exerciseKey: "squat", reps: 5, repsInReserve: -1) }, .badReserve)
    }

    func testTheEdgesOfEachRuleAreAllowed() throws {
        _ = try LoggedSet(exerciseKey: String(repeating: "a", count: 48), reps: 0, loadKilograms: 500, repsInReserve: 10)
        _ = try LoggedSet(exerciseKey: "a", reps: 200, loadKilograms: 0, repsInReserve: 0)
    }

    // MARK: Sessions

    func testASessionNeedsSetsOrARun() throws {
        XCTAssertEqual(problem { _ = try LoggedSession(performedAt: self.t0, feeling: .okay) }, .emptySession)
        _ = try LoggedSession(performedAt: t0, feeling: .okay, runMinutes: 30)
        _ = try LoggedSession(performedAt: t0, feeling: .okay, sets: [LoggedSet(exerciseKey: "squat", reps: 5)])
    }

    func testSessionRules() throws {
        let set = try LoggedSet(exerciseKey: "squat", reps: 5)
        XCTAssertEqual(problem { _ = try LoggedSession(performedAt: self.t0, feeling: .okay, sets: Array(repeating: set, count: 41)) }, .tooManySets)
        _ = try LoggedSession(performedAt: t0, feeling: .okay, sets: Array(repeating: set, count: 40))
        XCTAssertEqual(problem { _ = try LoggedSession(performedAt: self.t0, planWeek: 0, feeling: .okay, sets: [set]) }, .badWeek)
        XCTAssertEqual(problem { _ = try LoggedSession(performedAt: self.t0, planWeek: 53, feeling: .okay, sets: [set]) }, .badWeek)
        XCTAssertEqual(problem { _ = try LoggedSession(performedAt: self.t0, feeling: .okay, runMinutes: 0) }, .badRunMinutes)
        XCTAssertEqual(problem { _ = try LoggedSession(performedAt: self.t0, feeling: .okay, runMinutes: 601) }, .badRunMinutes)
    }

    func testATimeIsKeptToTheMillisecondLikeTheDatabaseKeepsIt() throws {
        let session = try LoggedSession(performedAt: Date(timeIntervalSince1970: 1_800_000_000.1239), feeling: .easy, runMinutes: 20)
        XCTAssertEqual(session.performedAt, Date(timeIntervalSince1970: 1_800_000_000.123))
    }

    // MARK: Files

    func testASessionSurvivesJSONAndAFileCannotSmuggleInABrokenSet() throws {
        let session = try LoggedSession(
            performedAt: t0, planWeek: 3, feeling: .hard,
            sets: [LoggedSet(exerciseKey: "goblet_squat", reps: 10, loadKilograms: 12.5, repsInReserve: 2),
                   LoggedSet(exerciseKey: "plank", reps: 40)])
        let data = try JSONEncoder().encode(session)
        XCTAssertEqual(try JSONDecoder().decode(LoggedSession.self, from: data), session)

        let broken = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"reps\":10", with: "\"reps\":999")
        XCTAssertNotEqual(broken, String(decoding: data, as: UTF8.self), "the edit should have changed the file")
        XCTAssertThrowsError(try JSONDecoder().decode(LoggedSession.self, from: Data(broken.utf8)),
                             "a set read from a file goes through the same rules")
    }

    // MARK: Export

    func testTheExportIsReadableOldestFirstAndComesBackWhole() throws {
        let later = try LoggedSession(performedAt: t0.addingTimeInterval(86_400), feeling: .okay, runMinutes: 25)
        let earlier = try LoggedSession(
            performedAt: t0, feeling: .hard, sets: [LoggedSet(exerciseKey: "push_up", reps: 12, repsInReserve: 1)])
        let export = TrainingLogExport(exportedAt: t0.addingTimeInterval(172_800), consentGranted: true, sessions: [later, earlier])
        XCTAssertEqual(export.sessions.map(\.id), [earlier.id, later.id])

        let data = try export.json()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"format\" : \"doddy.training_log\""), text)
        XCTAssertTrue(text.contains("\"version\" : 1"))
        XCTAssertTrue(text.contains("\"exercise_key\" : \"push_up\""))
        XCTAssertTrue(text.contains("2027-01-15T08:00:00.000Z"), "dates are ISO 8601: \(text)")
        XCTAssertEqual(try TrainingLogExport.decode(data), export)
    }

    func testTheExportHoldsNothingButTheLog() throws {
        let session = try LoggedSession(performedAt: t0, feeling: .easy, sets: [LoggedSet(exerciseKey: "squat", reps: 8)])
        let data = try TrainingLogExport(exportedAt: t0, consentGranted: false, sessions: [session]).json()
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["format", "version", "exported_at", "consent_granted", "sessions"])
        let first = try XCTUnwrap((root["sessions"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(first.keys), ["id", "performed_at", "plan_week", "feeling", "run_minutes", "sets"])
    }
}
