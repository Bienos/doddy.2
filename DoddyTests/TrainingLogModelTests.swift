import DoddyCore
import Foundation
import XCTest
#if canImport(Doddy)
@testable import Doddy
#endif

// The training log's state behind its screen (sport plan stage 3, ADR-642): nothing is opened or
// created while the log was never turned on, nothing is saved without the person's yes, taking the
// yes back keeps what was saved, a failure is shown in words and changes nothing, and the export
// file is read back and removed. A fake stands in for the store; the real one is tested on SQLite in
// DoddyPersistenceTests. Also run on Linux by scripts/test_training_log_model.sh.

private actor FakeTrainingLog: TrainingLogRepository {
    private var granted = false
    private var changedAt: Date?
    private var kept: [LoggedSession] = []
    private let clock: Date
    /// The next call of this kind throws this, once.
    private var failure: TrainingLogError?

    init(clock: Date, granted: Bool = false, kept: [LoggedSession] = []) {
        self.clock = clock
        self.granted = granted
        self.changedAt = granted ? clock : nil
        self.kept = kept
    }

    func failNext(with error: TrainingLogError) { failure = error }

    private func maybeFail() throws {
        if let failure { self.failure = nil; throw failure }
    }

    func consent() throws -> TrainingLogConsent {
        try maybeFail()
        return TrainingLogConsent(granted: granted, changedAt: changedAt)
    }

    func grantConsent() throws -> TrainingLogConsent {
        try maybeFail()
        granted = true
        changedAt = clock
        return TrainingLogConsent(granted: true, changedAt: clock)
    }

    func withdrawConsent() throws -> TrainingLogConsent {
        try maybeFail()
        granted = false
        changedAt = clock
        return TrainingLogConsent(granted: false, changedAt: clock)
    }

    func record(_ session: LoggedSession) throws -> LoggedSession {
        try maybeFail()
        guard granted else { throw TrainingLogError.consentMissing }
        kept.removeAll { $0.id == session.id }
        kept.append(session)
        return session
    }

    func sessions(from: Date?) throws -> [LoggedSession] {
        try maybeFail()
        return kept.filter { from == nil || $0.performedAt >= from! }.sorted { $0.performedAt > $1.performedAt }
    }

    func session(id: UUID) throws -> LoggedSession? { kept.first { $0.id == id } }

    func delete(id: UUID) throws {
        try maybeFail()
        guard kept.contains(where: { $0.id == id }) else { throw TrainingLogError.notFound(id) }
        kept.removeAll { $0.id == id }
    }

    func deleteAll() throws -> Int {
        try maybeFail()
        defer { kept = [] }
        return kept.count
    }

    func export() throws -> TrainingLogExport {
        try maybeFail()
        return TrainingLogExport(exportedAt: clock, consentGranted: granted, sessions: kept)
    }
}

private final class OpenCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func hit() { lock.lock(); value += 1; lock.unlock() }
}

final class TrainingLogModelTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(daysAgo: Double = 1, feeling: TrainingFeeling = .okay, key: String = "goblet_squat", reps: Int = 12) throws -> LoggedSession {
        try LoggedSession(
            performedAt: t0.addingTimeInterval(-daysAgo * 86_400), feeling: feeling,
            sets: (0..<3).map { _ in try LoggedSet(exerciseKey: key, reps: reps, loadKilograms: 16, repsInReserve: 2) })
    }

    private func exportFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("training-log-model-test-\(UUID().uuidString)", isDirectory: true)
    }

    @MainActor
    private func model(_ fake: FakeTrainingLog, exists: Bool, opened: OpenCounter = OpenCounter(), folder: URL? = nil,
                       plan: TrainingPlan? = nil) -> TrainingLogModel {
        TrainingLogModel(
            open: { opened.hit(); return fake }, storeExists: { exists }, plan: { plan }, now: { [t0] in t0 },
            exportDirectory: folder ?? exportFolder())
    }

    @MainActor
    func testNothingIsOpenedOrCreatedWhileTheLogWasNeverTurnedOn() async {
        let opened = OpenCounter()
        let log = model(FakeTrainingLog(clock: t0), exists: false, opened: opened)
        await log.load()
        XCTAssertTrue(log.isLoaded)
        XCTAssertEqual(log.consent, .neverAsked)
        XCTAssertTrue(log.sessions.isEmpty)
        XCTAssertNil(log.review)
        XCTAssertNil(log.reviewText())
        XCTAssertEqual(opened.count, 0, "no store was opened, so no file was made")
    }

    @MainActor
    func testTurningItOnOpensTheStoreOnceAndRecordsTheYes() async {
        let opened = OpenCounter()
        let log = model(FakeTrainingLog(clock: t0), exists: false, opened: opened)
        await log.load()
        await log.setKeeping(true)
        XCTAssertTrue(log.consent.granted)
        XCTAssertEqual(log.consent.changedAt, t0)
        await log.setKeeping(false)
        await log.setKeeping(true)
        XCTAssertEqual(opened.count, 1, "one store for the life of the screen")
        XCTAssertNil(log.problem)
    }

    @MainActor
    func testNothingIsSavedWithoutTheYesAndTheScreenSaysSo() async throws {
        let log = model(FakeTrainingLog(clock: t0), exists: false)
        await log.load()
        let saved = await log.record(try session())
        XCTAssertFalse(saved)
        XCTAssertEqual(log.problem, "Turn on the training log first. Nothing was saved.")
        XCTAssertTrue(log.sessions.isEmpty)
    }

    @MainActor
    func testASavedSessionShowsUpWithItsReview() async throws {
        let log = model(FakeTrainingLog(clock: t0), exists: false)
        await log.setKeeping(true)
        let saved = await log.record(try session())
        XCTAssertTrue(saved)
        XCTAssertEqual(log.sessions.count, 1)
        XCTAssertEqual(log.review?.priority, .progress(exercise: "goblet_squat", advice: .addLoad(kilograms: 5)))
        let text = try XCTUnwrap(log.reviewText(language: .english))
        XCTAssertTrue(text.contains("add 5 kg"), text)
    }

    @MainActor
    func testTheKeptPlansRangeIsUsedForTheReview() async throws {
        let request = PlanRequest(goal: .strengthGym, level: .beginner, daysPerWeek: 3, minutesPerSession: 45, screening: .clear(age: 30))
        guard case .plan(let plan) = PlanEngine.make(request) else { return XCTFail("a plain gym plan") }
        let planned = try XCTUnwrap(plan.weeks.flatMap(\.sessions).flatMap(\.exercises).first { $0.unit == .reps })
        let log = model(FakeTrainingLog(clock: t0), exists: false, plan: plan)
        await log.setKeeping(true)
        let saved = await log.record(try session(key: planned.key, reps: planned.high))
        XCTAssertTrue(saved)
        XCTAssertEqual(log.review?.exercises.first?.high, planned.high)
        XCTAssertEqual(log.review?.exercises.first?.low, planned.low)
    }

    @MainActor
    func testTakingBackTheYesStopsSavingAndKeepsWhatWasSaved() async throws {
        let log = model(FakeTrainingLog(clock: t0), exists: false)
        await log.setKeeping(true)
        await log.record(try session(daysAgo: 2))
        await log.setKeeping(false)
        XCTAssertFalse(log.consent.granted)
        XCTAssertEqual(log.sessions.count, 1, "taking back the yes is not a delete")
        let saved = await log.record(try session(daysAgo: 1))
        XCTAssertFalse(saved)
        XCTAssertEqual(log.sessions.count, 1)
    }

    @MainActor
    func testDeletingOneAndDeletingAllLeaveTheYesAlone() async throws {
        let first = try session(daysAgo: 3), second = try session(daysAgo: 1)
        let log = model(FakeTrainingLog(clock: t0, granted: true, kept: [first, second]), exists: true)
        await log.load()
        XCTAssertEqual(log.sessions.map(\.id), [second.id, first.id], "newest first")
        await log.delete(first.id)
        XCTAssertEqual(log.sessions.map(\.id), [second.id])
        let all = await log.deleteAll()
        XCTAssertTrue(all)
        XCTAssertTrue(log.sessions.isEmpty)
        XCTAssertTrue(log.consent.granted)
        XCTAssertEqual(log.review?.priority, .logFirstSession)
    }

    @MainActor
    func testAFailureIsShownInWordsAndChangesNothing() async throws {
        let fake = FakeTrainingLog(clock: t0, granted: true, kept: [try session(daysAgo: 2)])
        let log = model(fake, exists: true)
        await log.load()
        await fake.failNext(with: .verificationFailed)
        let saved = await log.record(try session(daysAgo: 1))
        XCTAssertFalse(saved)
        XCTAssertEqual(log.problem, "Doddy couldn't confirm that was saved on this iPhone. Nothing was kept.")
        await log.load()
        XCTAssertEqual(log.sessions.count, 1, "nothing was claimed")
    }

    @MainActor
    func testAStoreThatCannotBeOpenedIsReportedAndNothingIsClaimed() async throws {
        let log = TrainingLogModel(open: { throw CocoaError(.fileReadNoPermission) }, storeExists: { true })
        await log.load()
        XCTAssertTrue(log.isLoaded)
        XCTAssertNotNil(log.problem)
        XCTAssertTrue(log.sessions.isEmpty)
        await log.setKeeping(true)
        XCTAssertFalse(log.consent.granted, "a yes is not claimed when it could not be kept")
        let saved = await log.record(try session())
        XCTAssertFalse(saved)
    }

    @MainActor
    func testTheExportFileIsReadBackAndRemovedWhenDiscarded() async throws {
        let folder = exportFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let mine = try session()
        let log = model(FakeTrainingLog(clock: t0, granted: true, kept: [mine]), exists: true, folder: folder)
        await log.load()
        await log.prepareExport()
        let url = try XCTUnwrap(log.exportURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let export = try TrainingLogExport.decode(try Data(contentsOf: url))
        XCTAssertEqual(export.sessions, [mine])
        XCTAssertTrue(export.consentGranted)

        log.discardExport()
        XCTAssertNil(log.exportURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "a copy of health data does not stay in the temporary folder")
    }

    func testEveryStoreErrorHasWordsForTheScreen() {
        let errors: [TrainingLogError] = [
            .consentMissing, .invalid(.emptySession), .invalid(.tooManySets), .invalid(.inTheFuture), .invalid(.badReps),
            .notFound(UUID()), .verificationFailed, .corruptRecord("x"),
        ]
        var seen: Set<String> = []
        for error in errors {
            let text = TrainingLogModel.message(error)
            XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(text.contains("TrainingLogError"), "no type names on the screen: \(text)")
            seen.insert(text)
        }
        XCTAssertEqual(seen.count, errors.count, "each says its own thing")
    }
}
