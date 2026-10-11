import DoddyCore
@testable import DoddyPersistence
import Foundation
import GRDB
import XCTest

/// Real SQLite, no mocks: learned facts, procedures and outcome events (ADR-324), the
/// v10 → v13 upgrade, read-back, expiry, deletion reaching the index, Polish diacritics.
final class SQLiteLearningRepositoryTests: XCTestCase {
    private static let t0 = Date(timeIntervalSince1970: 1_760_000_000.123_456)
    private var t0: Date { Self.t0 }
    private var day: TimeInterval { 86_400 }

    /// A clock the test moves; repositories read it on every write.
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var _date: Date
        init(_ date: Date) { _date = date }
        var date: Date {
            get { lock.withLock { _date } }
            set { lock.withLock { _date = newValue } }
        }
    }

    private func tempPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("doddy-\(UUID()).sqlite").path
    }

    private func provenance(_ reason: String = "preference") throws -> LearningProvenance {
        try LearningProvenance(proposer: .rule, reason: reason, episodeDates: [t0])
    }

    private func validated(_ proposal: LearningProposal) throws -> ValidatedProposal {
        try LearningPolicy.validate(
            proposal, environment: LearningEnvironment(connectionsPaused: false, sensitiveMode: false, isToolOn: { _ in true }),
            counts: .none, knownDigests: [], now: t0)
    }

    private func factProposal(_ value: String, kind: LearnedFactKind = .preference, episodes: [String]? = nil) throws -> ValidatedProposal {
        try validated(.fact(try FactProposal(
            kind: kind, value: value, confidence: 80, provenance: try provenance(), sourceEpisodeIDs: episodes ?? [UUID().uuidString])))
    }

    private func procedureProposal(_ trigger: String = "Evening wrap-up", episodes: [String]? = nil) throws -> ValidatedProposal {
        let steps = [
            try ProcedureStep(number: 1, toolName: VoiceToolName.createReminder, fixed: ["list": "Home"], asked: ["title", "due"]),
            try ProcedureStep(number: 2, toolName: VoiceToolName.setTimer, fixed: ["minutes": "25"], asked: []),
        ]
        return try validated(.procedure(try ProcedureProposal(
            triggerText: trigger, steps: steps, provenance: try provenance("repeated_sequence"),
            sourceEpisodeIDs: episodes ?? [UUID().uuidString, UUID().uuidString, UUID().uuidString])))
    }

    private func count(_ database: DoddyDatabase, _ table: String) throws -> Int {
        try database.queue.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM \(table)") ?? 0 }
    }

    /// Proposes and confirms in one go, as the card does after Save.
    private func confirmed(_ repo: SQLiteLearnedFactRepository, _ text: String, kind: LearnedFactKind = .preference) async throws -> LearnedFact {
        let proposed = try await repo.propose(try factProposal(text, kind: kind))
        return try await repo.confirm(id: proposed.id, exactText: text)
    }

    // MARK: Migration

    func testMigrationUpgradesAnExistingDatabaseAndKeepsNotes() async throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        // A file as the previous release left it: migrated up to v10 with one note.
        let queue = try DatabaseQueue(path: path)
        try DoddyDatabase.migrator.migrate(queue, upTo: "v10_list_shares")
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO memories (id, raw_text, current_text, category, source, captured_at_ms, updated_at_ms,
                                          user_edited, search_text, schema_version)
                    VALUES (?, 'Kupić mleko', 'Kupić mleko', 'other', 'explicit_text', 1, NULL, 0, 'kupic mleko', 1)
                    """,
                arguments: [UUID().uuidString])
            XCTAssertFalse(try db.tableExists("learned_facts"))
        }
        try queue.close()

        let database = try DoddyDatabase(path: path)
        try await database.queue.read { db in
            for table in ["learned_facts", "learned_fact_revisions", "learned_facts_fts", "procedures", "procedures_fts", "outcome_events"] {
                XCTAssertTrue(try db.tableExists(table), table)
            }
        }
        let notes = try await SQLiteMemoryRepository(database: database).list(limit: nil)
        XCTAssertEqual(notes.map(\.currentText), ["Kupić mleko"], "the upgrade touches no note")
    }

    // MARK: Facts

    func testProposeConfirmReadsBackAndSurvivesReopen() async throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let clock = Clock(t0)
        let repo = SQLiteLearnedFactRepository(database: try DoddyDatabase(path: path), now: { clock.date })

        let proposed = try await repo.propose(try factProposal("Reminders at 9:00 suit me", episodes: ["ep-1"]))
        XCTAssertEqual(proposed.status, .proposed)
        XCTAssertNil(proposed.confirmedAt)
        XCTAssertEqual(proposed.evidenceDigest, EvidenceDigest.compute(["ep-1"]))
        let beforeConfirm = try await repo.query("reminders", limit: 5)
        XCTAssertEqual(beforeConfirm, [], "a proposal is never retrieved")

        clock.date = t0.addingTimeInterval(60)
        let confirmed = try await repo.confirm(id: proposed.id, exactText: "Reminders at 9:00 suit me")
        XCTAssertEqual(confirmed.status, .confirmed)
        XCTAssertEqual(confirmed.confirmedAt, DoddyDatabase.truncatedToMilliseconds(clock.date))
        XCTAssertEqual(confirmed.expiresAt, confirmed.confirmedAt?.addingTimeInterval(365 * day), "preference: 365 days")
        let revisions = try await repo.revisions(of: proposed.id)
        XCTAssertEqual(revisions.map(\.number), [1])

        let reopened = SQLiteLearnedFactRepository(database: try DoddyDatabase(path: path), now: { clock.date })
        let stored = try await reopened.fact(id: proposed.id)
        XCTAssertEqual(stored, confirmed)
        let listed = try await reopened.list(status: .confirmed)
        XCTAssertEqual(listed, [confirmed])
        let found = try await reopened.query("reminders 9", limit: 5)
        XCTAssertEqual(found.map(\.id), [proposed.id])
        let digests = try await reopened.knownDigests()
        XCTAssertEqual(digests, [proposed.evidenceDigest])
    }

    func testConfirmNeedsTheExactTextAndOnlyOnce() async throws {
        let repo = SQLiteLearnedFactRepository(database: try DoddyDatabase.inMemory(), now: { Self.t0 })
        let proposed = try await repo.propose(try factProposal("Marta's birthday is 12 May"))
        await assertThrows(.textMismatch) { _ = try await repo.confirm(id: proposed.id, exactText: "Marta's birthday is 14 May") }
        let unchanged = try await repo.fact(id: proposed.id)
        XCTAssertEqual(unchanged?.status, .proposed, "nothing changed")
        _ = try await repo.confirm(id: proposed.id, exactText: "Marta's birthday is 12 May")
        await assertThrows(.notProposed(proposed.id)) { _ = try await repo.confirm(id: proposed.id, exactText: "Marta's birthday is 12 May") }
        let missing = UUID()
        await assertThrows(.notFound(missing)) { _ = try await repo.confirm(id: missing, exactText: "x") }
    }

    func testTheSameEvidenceIsNeverProposedTwiceAndNeverThisSticks() async throws {
        let repo = SQLiteLearnedFactRepository(database: try DoddyDatabase.inMemory(), now: { Self.t0 })
        let proposal = try factProposal("I prefer tea", episodes: ["a", "b"])
        let first = try await repo.propose(proposal)
        await assertThrows(.duplicateEvidence) { _ = try await repo.propose(proposal) }
        let rejected = try await repo.reject(id: first.id)
        XCTAssertEqual(rejected.status, .rejected)
        let digests = try await repo.knownDigests()
        XCTAssertEqual(digests, [first.evidenceDigest], "the policy sees it and refuses the evidence")
        await assertThrows(.duplicateEvidence) { _ = try await repo.propose(proposal) }
        // An unanswered proposal is dropped after the limit; the evidence may come back later.
        let other = try await repo.propose(try factProposal("I prefer coffee", episodes: ["c"]))
        let pruned = try await repo.pruneProposals(olderThan: Self.t0.addingTimeInterval(1))
        XCTAssertEqual(pruned, 1)
        let gone = try await repo.fact(id: other.id)
        XCTAssertNil(gone)
        let kept = try await repo.fact(id: first.id)
        XCTAssertNotNil(kept, "a rejected row is not a proposal and stays")
    }

    func testExpiryRetireReconfirmAndRevise() async throws {
        let clock = Clock(t0)
        let repo = SQLiteLearnedFactRepository(database: try DoddyDatabase.inMemory(), now: { clock.date })
        let routine = try await confirmed(repo, "I take the 7:10 train on Mondays", kind: .routine)
        XCTAssertEqual(routine.expiresAt, routine.confirmedAt?.addingTimeInterval(180 * day))
        let fresh = try await repo.query("train", limit: 5)
        XCTAssertEqual(fresh.count, 1)

        clock.date = t0.addingTimeInterval(181 * day)
        let afterExpiry = try await repo.query("train", limit: 5)
        XCTAssertEqual(afterExpiry, [], "expired: not retrieved, still listed")
        let stillListed = try await repo.list(status: .confirmed)
        XCTAssertEqual(stillListed.count, 1)
        let storedFact = try await repo.fact(id: routine.id)
        let stored = try XCTUnwrap(storedFact)
        XCTAssertTrue(stored.needsReview(at: clock.date))

        let again = try await repo.reconfirm(id: routine.id)
        XCTAssertEqual(again.expiresAt, DoddyDatabase.truncatedToMilliseconds(clock.date).addingTimeInterval(180 * day))
        let afterReconfirm = try await repo.query("train", limit: 5)
        XCTAssertEqual(afterReconfirm.count, 1)

        let revised = try await repo.revise(id: routine.id, value: "I take the 7:40 train on Mondays")
        XCTAssertEqual(revised.value, "I take the 7:40 train on Mondays")
        let revisions = try await repo.revisions(of: routine.id)
        XCTAssertEqual(revisions.map(\.value), ["I take the 7:10 train on Mondays", "I take the 7:40 train on Mondays"])
        let byNewWording = try await repo.query("7:40", limit: 5)
        XCTAssertEqual(byNewWording.map(\.id), [routine.id])

        let retired = try await repo.retire(id: routine.id)
        XCTAssertEqual(retired.status, .retired)
        XCTAssertNil(retired.confirmedAt)
        let afterRetire = try await repo.query("train", limit: 5)
        XCTAssertEqual(afterRetire, [])
        let retiredList = try await repo.list(status: .retired)
        XCTAssertEqual(retiredList.map(\.id), [routine.id], "visible and reversible")
        await assertThrows(.wrongStatus(routine.id, .retired)) { _ = try await repo.revise(id: routine.id, value: "x") }
    }

    func testDeleteReachesTheIndexAndPolishDiacriticsAreFound() async throws {
        let database = try DoddyDatabase.inMemory()
        let repo = SQLiteLearnedFactRepository(database: database, now: { Self.t0 })
        let zosia = try await confirmed(repo, "Kupić mleko u Zosi", kind: .place)
        let lodz = try await confirmed(repo, "Jeżdżę do Łodzi w poniedziałki", kind: .routine)
        let byZosi = try await repo.query("zosi", limit: 5)
        XCTAssertEqual(byZosi.map(\.id), [zosia.id])
        let byLodzi = try await repo.query("Łodzi", limit: 5)
        XCTAssertEqual(byLodzi.map(\.id), [lodz.id])
        let byLodziPlain = try await repo.query("lodzi", limit: 5)
        XCTAssertEqual(byLodziPlain.map(\.id), [lodz.id], "typed without diacritics")
        let byCar = try await repo.query("car", limit: 5)
        XCTAssertEqual(byCar, [], "no false hit")
        XCTAssertEqual(try count(database, "learned_facts_fts"), 2)

        try await repo.delete(id: zosia.id)
        let afterDelete = try await repo.query("zosi", limit: 5)
        XCTAssertEqual(afterDelete, [])
        XCTAssertEqual(try count(database, "learned_facts_fts"), 1)
        XCTAssertEqual(try count(database, "learned_fact_revisions"), 1, "its revision went with it")
        await assertThrows(.notFound(zosia.id)) { try await repo.delete(id: zosia.id) }

        try await repo.deleteAll()
        let everything = try await repo.list(status: nil)
        XCTAssertEqual(everything, [])
        XCTAssertEqual(try count(database, "learned_facts_fts"), 0)
        XCTAssertEqual(try count(database, "learned_fact_revisions"), 0)
    }

    func testConflictingFactsAreBothReturnedWithProvenance() async throws {
        let repo = SQLiteLearnedFactRepository(database: try DoddyDatabase.inMemory(), now: { Self.t0 })
        _ = try await confirmed(repo, "Marta's birthday is 12 May", kind: .person)
        _ = try await confirmed(repo, "Marta's birthday is 14 May", kind: .person)
        let hits = try await repo.query("Marta birthday", limit: 5)
        XCTAssertEqual(Set(hits.map(\.value)), ["Marta's birthday is 12 May", "Marta's birthday is 14 May"])
        XCTAssertTrue(hits.allSatisfy { $0.provenance.episodeDates == [DoddyDatabase.truncatedToMilliseconds(Self.t0)] })
    }

    func testFactExportCarriesProvenanceAndRevisions() async throws {
        let repo = SQLiteLearnedFactRepository(database: try DoddyDatabase.inMemory(), now: { Self.t0 })
        let proposed = try await repo.propose(try factProposal("I prefer tea", episodes: ["ep-9"]))
        _ = try await repo.confirm(id: proposed.id, exactText: "I prefer tea")
        let data = try await repo.export()
        let export = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let facts = export?["facts"] as? [[String: Any]]
        XCTAssertEqual(facts?.count, 1)
        XCTAssertEqual((facts?.first?["provenance"] as? [String: Any])?["proposer"] as? String, "rule")
        XCTAssertEqual(facts?.first?["sourceEpisodeIDs"] as? [String], ["ep-9"])
        XCTAssertEqual((export?["revisions"] as? [[String: Any]])?.count, 1)
    }

    // MARK: Procedures

    func testProcedureLifecycleReadsBackAndSurvivesReopen() async throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let clock = Clock(t0)
        let repo = SQLiteProcedureRepository(database: try DoddyDatabase(path: path), now: { clock.date })

        let proposed = try await repo.propose(try procedureProposal())
        XCTAssertEqual(proposed.status, .proposed)
        let beforeConfirm = try await repo.query("evening", limit: 3)
        XCTAssertEqual(beforeConfirm, [])
        await assertThrows(.textMismatch) { _ = try await repo.confirm(id: proposed.id, exactTrigger: "Morning") }
        let confirmed = try await repo.confirm(id: proposed.id, exactTrigger: "Evening wrap-up")
        XCTAssertEqual(confirmed.version, 1)
        let found = try await repo.query("evening", limit: 3)
        XCTAssertEqual(found.map(\.id), [proposed.id])

        clock.date = t0.addingTimeInterval(day)
        let used = try await repo.markUsed(id: proposed.id)
        XCTAssertEqual(used.useCount, 1)
        XCTAssertEqual(used.lastUsedAt, DoddyDatabase.truncatedToMilliseconds(clock.date))

        let newSteps = [try ProcedureStep(number: 1, toolName: VoiceToolName.createReminder, fixed: [:], asked: ["title", "due"])]
        let edited = try await repo.update(id: proposed.id, triggerText: "Wieczorne podsumowanie", steps: newSteps)
        XCTAssertEqual(edited.version, 2)
        XCTAssertEqual(edited.steps, newSteps)
        let byNewTrigger = try await repo.query("wieczorne", limit: 3)
        XCTAssertEqual(byNewTrigger.map(\.id), [proposed.id])
        let byOldTrigger = try await repo.query("evening", limit: 3)
        XCTAssertEqual(byOldTrigger, [], "the old trigger left the index")

        let reopened = SQLiteProcedureRepository(database: try DoddyDatabase(path: path), now: { clock.date })
        let stored = try await reopened.procedure(id: proposed.id)
        XCTAssertEqual(stored, edited)

        clock.date = t0.addingTimeInterval(92 * day)
        let retired = try await reopened.retireUnused(since: clock.date.addingTimeInterval(-90 * day))
        XCTAssertEqual(retired.map(\.id), [proposed.id])
        let afterRetire = try await reopened.query("wieczorne", limit: 3)
        XCTAssertEqual(afterRetire, [])
        let revived = try await reopened.revive(id: proposed.id)
        XCTAssertEqual(revived.status, .confirmed)
        let retiredAgain = try await reopened.retireUnused(since: clock.date.addingTimeInterval(-90 * day))
        XCTAssertEqual(retiredAgain, [], "revived counts as used now")
        try await reopened.delete(id: proposed.id)
        let gone = try await reopened.procedure(id: proposed.id)
        XCTAssertNil(gone)
    }

    func testAHandEditedRowCannotLowerAnApprovalOrAddATool() async throws {
        let database = try DoddyDatabase.inMemory()
        let repo = SQLiteProcedureRepository(database: database, now: { Self.t0 })
        let id = try await repo.propose(try procedureProposal()).id
        _ = try await repo.confirm(id: id, exactTrigger: "Evening wrap-up")

        try await database.queue.write { db in
            try db.execute(
                sql: "UPDATE procedures SET steps_json = ? WHERE id = ?",
                arguments: [#"[{"number":1,"tool":"create_reminder","fixed":{},"asked":["title"],"approval":"none","tier":"L0"}]"#, id.uuidString])
        }
        let editedRow = try await repo.procedure(id: id)
        let edited = try XCTUnwrap(editedRow)
        XCTAssertEqual(edited.steps.map(\.approval), [.card], "the row's claim is not read; the card stays")

        try await database.queue.write { db in
            try db.execute(
                sql: "UPDATE procedures SET steps_json = ? WHERE id = ?",
                arguments: [#"[{"number":1,"tool":"open_map","fixed":{},"asked":[]}]"#, id.uuidString])
        }
        await assertThrows(.corruptRecord(id.uuidString)) { _ = try await repo.procedure(id: id) }
        await assertThrows(.corruptRecord(id.uuidString)) { _ = try await repo.query("evening", limit: 3) }
    }

    func testProcedureDuplicateEvidenceDeleteAllAndExport() async throws {
        let database = try DoddyDatabase.inMemory()
        let repo = SQLiteProcedureRepository(database: database, now: { Self.t0 })
        let proposal = try procedureProposal(episodes: ["x", "y", "z"])
        _ = try await repo.propose(proposal)
        await assertThrows(.duplicateEvidence) { _ = try await repo.propose(proposal) }
        await assertThrows(.wrongProposalKind) { _ = try await repo.propose(try self.factProposal("not a procedure")) }
        let digests = try await repo.knownDigests()
        XCTAssertEqual(digests, [EvidenceDigest.compute(["x", "y", "z"])])
        let data = try await repo.export()
        let export = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = export?["procedures"] as? [[String: Any]]
        let steps = items?.first?["steps"] as? [[String: Any]]
        XCTAssertEqual(steps?.count, 2)
        XCTAssertNil(steps?.first?["approval"], "no approval is ever written")
        try await repo.deleteAll()
        XCTAssertEqual(try count(database, "procedures_fts"), 0)
    }

    // MARK: Outcome events

    func testOutcomeEventsRecordCountPruneAndExport() async throws {
        let repo = SQLiteOutcomeEventRepository(database: try DoddyDatabase.inMemory())
        func event(_ kind: OutcomeKind, daysAgo: Double, detail: OutcomeDetail) throws -> OutcomeEvent {
            try OutcomeEvent(requestID: "req-\(Int(daysAgo * 10))", kind: kind, detail: detail, createdAt: t0.addingTimeInterval(-daysAgo * day))
        }
        let recorded = try await repo.record(try event(.corrected, daysAgo: 1, detail: try OutcomeDetail(toolName: "create_reminder", correction: .undo)))
        _ = try await repo.record(try event(.completed, daysAgo: 2, detail: try OutcomeDetail(toolName: "set_timer")))
        _ = try await repo.record(try event(.capabilityGap, daysAgo: 3, detail: try OutcomeDetail(gapCategory: .music)))
        _ = try await repo.record(try event(.redone, daysAgo: 95, detail: try OutcomeDetail(toolName: "create_reminder")))

        let listed = try await repo.list(since: t0.addingTimeInterval(-100 * day), limit: 10)
        XCTAssertEqual(listed.map(\.kind), [.redone, .capabilityGap, .completed, .corrected], "oldest first")
        XCTAssertEqual(listed.last, recorded)
        let corrections = try await repo.count(kinds: OutcomeEvent.correctionKinds, since: t0.addingTimeInterval(-7 * day))
        XCTAssertEqual(corrections, 1)
        let gaps = try await repo.count(kinds: [.capabilityGap], since: t0.addingTimeInterval(-7 * day))
        XCTAssertEqual(gaps, 1)
        let pruned = try await repo.prune(olderThan: t0.addingTimeInterval(-90 * day))
        XCTAssertEqual(pruned, 1)
        let remaining = try await repo.list(since: .distantPast, limit: 10)
        XCTAssertEqual(remaining.count, 3)

        let export = String(decoding: try await repo.export(), as: UTF8.self)
        XCTAssertTrue(export.contains(#""gapCategory":"music""#))
        XCTAssertFalse(export.contains("value"), "no user text anywhere in the file")
        try await repo.deleteAll()
        let afterDeleteAll = try await repo.list(since: .distantPast, limit: 10)
        XCTAssertEqual(afterDeleteAll, [])
    }

    // MARK: Helpers

    private func assertThrows(
        _ expected: LearningStoreError, file: StaticString = #filePath, line: UInt = #line, _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? LearningStoreError, expected, file: file, line: line)
        }
    }
}
