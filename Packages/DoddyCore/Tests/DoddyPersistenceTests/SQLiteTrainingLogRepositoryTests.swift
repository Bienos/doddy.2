import DoddyCore
@testable import DoddyPersistence
import Foundation
import GRDB
import XCTest

/// The training logbook on real SQLite (ADR-632): consent first, every write read back, delete for
/// good, export always possible.
final class SQLiteTrainingLogRepositoryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func make() throws -> SQLiteTrainingLogRepository {
        let time = t0
        return SQLiteTrainingLogRepository(database: try DoddyDatabase.inMemory(), now: { time })
    }

    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("doddy-traininglog-\(UUID()).sqlite").path
    }

    private func squatSession(id: UUID = UUID(), daysAgo: Double = 0, key: String = "goblet_squat", reps: Int = 10,
                              feeling: TrainingFeeling = .okay) throws -> LoggedSession {
        try LoggedSession(
            id: id, performedAt: t0.addingTimeInterval(-daysAgo * 86_400), planWeek: 2, feeling: feeling,
            sets: [LoggedSet(exerciseKey: key, reps: reps, loadKilograms: 12.5, repsInReserve: 2),
                   LoggedSet(exerciseKey: key, reps: reps - 1, loadKilograms: 12.5, repsInReserve: 1)])
    }

    private func count(_ table: String, at path: String) throws -> Int {
        try DatabaseQueue(path: path).read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM \(table)") ?? -1 }
    }

    // MARK: Consent

    func testNothingIsKeptUntilThePersonSaysYes() async throws {
        let log = try make()
        let first = try await log.consent()
        XCTAssertEqual(first, .neverAsked)
        XCTAssertFalse(first.granted)

        do {
            _ = try await log.record(try squatSession())
            XCTFail("no yes, no write")
        } catch {
            XCTAssertEqual(error as? TrainingLogError, .consentMissing)
        }
        let kept = try await log.sessions(from: nil)
        XCTAssertTrue(kept.isEmpty)
    }

    func testYesAndTakingItBackAreRecordedWithTheirTime() async throws {
        let log = try make()
        let granted = try await log.grantConsent()
        XCTAssertEqual(granted, TrainingLogConsent(granted: true, changedAt: t0))
        let again = try await log.consent()
        XCTAssertEqual(again, granted)
        let withdrawn = try await log.withdrawConsent()
        XCTAssertEqual(withdrawn, TrainingLogConsent(granted: false, changedAt: t0))
    }

    func testTakingBackTheYesStopsRecordingButDoesNotDeleteAndTheExportStillWorks() async throws {
        let log = try make()
        _ = try await log.grantConsent()
        let session = try squatSession()
        _ = try await log.record(session)
        _ = try await log.withdrawConsent()

        do {
            _ = try await log.record(try squatSession())
            XCTFail("recording stopped")
        } catch {
            XCTAssertEqual(error as? TrainingLogError, .consentMissing)
        }
        let stillThere = try await log.sessions(from: nil)
        XCTAssertEqual(stillThere, [session], "withdrawing is not deleting")
        let export = try await log.export()
        XCTAssertEqual(export.sessions, [session])
        XCTAssertFalse(export.consentGranted)
    }

    // MARK: Record and read back

    func testASessionComesBackExactlyAndNewestFirst() async throws {
        let log = try make()
        _ = try await log.grantConsent()
        let older = try squatSession(daysAgo: 7, reps: 9)
        let newer = try squatSession(daysAgo: 1, reps: 11)
        let run = try LoggedSession(performedAt: t0.addingTimeInterval(-3 * 86_400), feeling: .hard, runMinutes: 28)
        for session in [older, newer, run] { _ = try await log.record(session) }

        let listed = try await log.sessions(from: nil)
        XCTAssertEqual(listed, [newer, run, older])
        let fetched = try await log.session(id: older.id)
        XCTAssertEqual(fetched, older)
        let missing = try await log.session(id: UUID())
        XCTAssertNil(missing)
        let recent = try await log.sessions(from: t0.addingTimeInterval(-4 * 86_400))
        XCTAssertEqual(recent, [newer, run])
        XCTAssertEqual(listed[0].sets.map(\.loadGrams), [12_500, 12_500], "load is exact")
    }

    func testASessionMoreThanADayAheadIsRefused() async throws {
        let log = try make()
        _ = try await log.grantConsent()
        let future = try squatSession(daysAgo: -2)
        do {
            _ = try await log.record(future)
            XCTFail("a session two days ahead is not a session that was done")
        } catch {
            XCTAssertEqual(error as? TrainingLogError, .invalid(.inTheFuture))
        }
        _ = try await log.record(try squatSession(daysAgo: -0.5))
    }

    func testACorrectionReplacesTheEntryAndItsSets() async throws {
        let path = temporaryPath()
        defer { for suffix in ["", "-wal", "-shm", "-journal"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let time = t0
        let log = SQLiteTrainingLogRepository(database: try DoddyDatabase(path: path), now: { time })
        _ = try await log.grantConsent()
        let id = UUID()
        _ = try await log.record(try squatSession(id: id, reps: 10))
        let corrected = try LoggedSession(
            id: id, performedAt: t0, feeling: .easy, sets: [LoggedSet(exerciseKey: "push_up", reps: 15, repsInReserve: 3)])
        _ = try await log.record(corrected)

        let listed = try await log.sessions(from: nil)
        XCTAssertEqual(listed, [corrected])
        XCTAssertEqual(try count("training_sessions", at: path), 1)
        XCTAssertEqual(try count("training_sets", at: path), 1, "the two old sets went with the old entry")
    }

    func testEverythingSurvivesClosingAndReopeningTheFile() async throws {
        let path = temporaryPath()
        defer { for suffix in ["", "-wal", "-shm", "-journal"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let time = t0
        let session = try squatSession()
        do {
            let log = SQLiteTrainingLogRepository(database: try DoddyDatabase(path: path), now: { time })
            _ = try await log.grantConsent()
            _ = try await log.record(session)
        }
        let reopened = SQLiteTrainingLogRepository(database: try DoddyDatabase(path: path), now: { time })
        let consent = try await reopened.consent()
        XCTAssertTrue(consent.granted)
        let sessions = try await reopened.sessions(from: nil)
        XCTAssertEqual(sessions, [session])
    }

    // MARK: Read-back

    func testAWriteThatDoesNotReadBackIsRolledBackAndReportedAsFailed() async throws {
        let path = temporaryPath()
        defer { for suffix in ["", "-wal", "-shm", "-journal"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let time = t0
        let log = SQLiteTrainingLogRepository(database: try DoddyDatabase(path: path), now: { time })
        _ = try await log.grantConsent()
        // Something on the way changes what is written: the read-back must see it.
        try await DatabaseQueue(path: path).write { db in
            try db.execute(sql: """
                CREATE TRIGGER corrupt_sets AFTER INSERT ON training_sets
                BEGIN UPDATE training_sets SET reps = reps + 1 WHERE rowid = NEW.rowid; END
                """)
        }
        do {
            _ = try await log.record(try squatSession())
            XCTFail("the read-back should not match")
        } catch {
            XCTAssertEqual(error as? TrainingLogError, .verificationFailed)
        }
        XCTAssertEqual(try count("training_sessions", at: path), 0, "nothing of the failed save is kept")
        XCTAssertEqual(try count("training_sets", at: path), 0)
    }

    // MARK: Delete

    func testDeletingOneSessionRemovesItsSetsAndAMissingOneIsReported() async throws {
        let path = temporaryPath()
        defer { for suffix in ["", "-wal", "-shm", "-journal"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let time = t0
        let log = SQLiteTrainingLogRepository(database: try DoddyDatabase(path: path), now: { time })
        _ = try await log.grantConsent()
        let keep = try squatSession(daysAgo: 1)
        let drop = try squatSession(daysAgo: 2)
        _ = try await log.record(keep)
        _ = try await log.record(drop)

        try await log.delete(id: drop.id)
        let left = try await log.sessions(from: nil)
        XCTAssertEqual(left, [keep])
        XCTAssertEqual(try count("training_sets", at: path), 2, "only the kept session's sets remain")
        do {
            try await log.delete(id: drop.id)
            XCTFail("already gone")
        } catch {
            XCTAssertEqual(error as? TrainingLogError, .notFound(drop.id))
        }
    }

    func testDeleteAllLeavesNothingReadableInTheFileAndKeepsTheConsent() async throws {
        let path = temporaryPath()
        defer { DatabaseFileBytes.remove(path) }
        let time = t0
        let log = SQLiteTrainingLogRepository(database: try DoddyDatabase(path: path), now: { time })
        _ = try await log.grantConsent()
        let marker = "zq_marker_kettlebell_91"
        for days in 1...3 { _ = try await log.record(try squatSession(daysAgo: Double(days), key: marker)) }
        XCTAssertGreaterThan(DatabaseFileBytes.occurrences(of: marker, at: path), 0, "the marker is really in the file before")

        let removed = try await log.deleteAll()
        XCTAssertEqual(removed, 3)
        let sessions = try await log.sessions(from: nil)
        XCTAssertTrue(sessions.isEmpty)
        XCTAssertEqual(try count("training_sets", at: path), 0)
        XCTAssertEqual(DatabaseFileBytes.occurrences(of: marker, at: path), 0, "the exercise name is gone from the file, not just from queries")
        let consent = try await log.consent()
        XCTAssertTrue(consent.granted, "deleting the log is not taking back the yes")
        let again = try await log.deleteAll()
        XCTAssertEqual(again, 0)
    }

    // MARK: The table itself

    func testTheTableRefusesWhatTheValueRefusesEvenFromAnotherPath() throws {
        let path = temporaryPath()
        defer { DatabaseFileBytes.remove(path) }
        _ = try DoddyDatabase(path: path)
        let queue = try DatabaseQueue(path: path)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO training_sessions (id, performed_at_ms, feeling) VALUES ('s1', 1, 'okay')")
        }
        func fails(_ sql: String) -> Bool {
            do { try queue.write { db in try db.execute(sql: sql) }; return false } catch { return true }
        }
        XCTAssertTrue(fails("INSERT INTO training_sessions (id, performed_at_ms, feeling) VALUES ('s2', 1, 'great')"), "feeling")
        XCTAssertTrue(fails("INSERT INTO training_sessions (id, performed_at_ms, feeling, plan_week) VALUES ('s3', 1, 'okay', 53)"), "week")
        XCTAssertTrue(fails("INSERT INTO training_sessions (id, performed_at_ms, feeling, run_minutes) VALUES ('s4', 1, 'okay', 0)"), "run minutes")
        XCTAssertTrue(fails("INSERT INTO training_sets (session_id, position, exercise_key, reps) VALUES ('s1', 0, 'squat', 999)"), "reps")
        XCTAssertTrue(fails("INSERT INTO training_sets (session_id, position, exercise_key, reps, reps_in_reserve) VALUES ('s1', 0, 'squat', 5, 11)"), "reserve")
        XCTAssertTrue(fails("INSERT INTO training_sets (session_id, position, exercise_key, reps, load_grams) VALUES ('s1', 0, 'squat', 5, -1)"), "load")
        XCTAssertTrue(fails("INSERT INTO training_sets (session_id, position, exercise_key, reps) VALUES ('nobody', 0, 'squat', 5)"), "a set with no session")
        XCTAssertTrue(fails("INSERT INTO training_log_consent (id, granted, changed_at_ms) VALUES (2, 1, 1)"), "only one consent row")
    }

    func testARowThatBreaksTheRulesOfAValueIsReportedAsCorruptNotShown() async throws {
        let path = temporaryPath()
        defer { DatabaseFileBytes.remove(path) }
        let time = t0
        let log = SQLiteTrainingLogRepository(database: try DoddyDatabase(path: path), now: { time })
        let id = UUID().uuidString
        try await DatabaseQueue(path: path).write { db in
            try db.execute(sql: "INSERT INTO training_sessions (id, performed_at_ms, feeling) VALUES (?, 1, 'okay')", arguments: [id])
            try db.execute(sql: "INSERT INTO training_sets (session_id, position, exercise_key, reps) VALUES (?, 0, 'Not A Key', 5)", arguments: [id])
        }
        do {
            _ = try await log.sessions(from: nil)
            XCTFail("a broken row must not be shown as if it were fine")
        } catch {
            guard case TrainingLogError.corruptRecord = error else { return XCTFail("\(error)") }
        }
    }

    // MARK: Migration

    /// A phone on the build before this one has no logbook tables; opening the file adds them and
    /// does not refuse it as written by a newer version.
    func testAFileFromTheBuildBeforeGetsTheLogbookTables() throws {
        let path = temporaryPath()
        defer { DatabaseFileBytes.remove(path) }
        _ = try DoddyDatabase(path: path)
        let queue = try DatabaseQueue(path: path)
        try queue.write { db in
            for table in ["training_sets", "training_sessions", "training_log_consent"] { try db.execute(sql: "DROP TABLE \(table)") }
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v19_training_log'")
        }
        XCTAssertNoThrow(try DoddyDatabase(path: path))
        let tables = try queue.read { db in Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")) }
        XCTAssertTrue(tables.isSuperset(of: ["training_sessions", "training_sets", "training_log_consent"]))
    }

    // MARK: Export

    func testTheExportHoldsEverythingAndRoundTrips() async throws {
        let log = try make()
        _ = try await log.grantConsent()
        let a = try squatSession(daysAgo: 5)
        let b = try LoggedSession(performedAt: t0.addingTimeInterval(-86_400), feeling: .hard, runMinutes: 30)
        _ = try await log.record(b)
        _ = try await log.record(a)
        let export = try await log.export()
        XCTAssertEqual(export.sessions, [a, b], "oldest first")
        XCTAssertTrue(export.consentGranted)
        XCTAssertEqual(export.exportedAt, t0)
        XCTAssertEqual(try TrainingLogExport.decode(try export.json()), export)
    }
}
