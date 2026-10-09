import DoddyCore
@testable import DoddyPersistence
import Foundation
import GRDB
import XCTest

/// Real SQLite, no mocks: reviewed profile, onboarding progress and the v1 → v2 upgrade.
final class SQLiteProfileRepositoryTests: XCTestCase {
    private static let t0 = Date(timeIntervalSince1970: 1_760_000_000.123_456)
    private static let t1 = Date(timeIntervalSince1970: 1_760_000_500)
    private var t0: Date { Self.t0 }
    private var t1: Date { Self.t1 }

    private func tempPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("doddy-\(UUID()).sqlite").path
    }

    func testCommitStoresOnlyReviewedFieldsAndSurvivesReopen() async throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let repo = SQLiteProfileRepository(database: try DoddyDatabase(path: path), now: { Self.t0 })
        let empty = try await repo.profile()
        XCTAssertTrue(empty.isEmpty)

        var draft = ProfileDraft()
        draft[.name] = " Ola "
        draft[.style] = "Short and clear"
        draft[.help] = ""
        let saved = try await repo.commit(draft, basedOn: empty)
        XCTAssertEqual(saved.value(.name), "Ola")
        XCTAssertEqual(saved.value(.style), "Short and clear")
        XCTAssertNil(saved.fields[.help], "skipped answers are not stored")
        XCTAssertEqual(saved.fields[.name]?.revision, 1)
        XCTAssertEqual(saved.fields[.name]?.source, .explicitUserReview)

        let reopened = SQLiteProfileRepository(database: try DoddyDatabase(path: path))
        let afterReopen = try await reopened.profile()
        XCTAssertEqual(afterReopen, saved)
    }

    func testEditKeepsUnchangedFieldsBumpsChangedOnesAndRemovesMissingOnes() async throws {
        let clock = TestClock(t0)
        let repo = SQLiteProfileRepository(database: try DoddyDatabase.inMemory(), now: { clock.now })
        var draft = ProfileDraft()
        draft[.name] = "Ola"
        draft[.humor] = "Just the useful bit"
        draft[.context] = "Learning the guitar"
        let first = try await repo.commit(draft, basedOn: .empty)

        clock.now = t1
        var edit = first.draft
        edit[.name] = "Aleksandra"
        edit.remove(.context)
        let second = try await repo.commit(edit, basedOn: first)

        XCTAssertEqual(second.value(.name), "Aleksandra")
        XCTAssertEqual(second.fields[.name]?.revision, 2)
        XCTAssertEqual(second.fields[.name]?.approvedAt, t1)
        XCTAssertEqual(second.fields[.humor], first.fields[.humor], "unchanged field keeps its approval")
        XCTAssertNil(second.fields[.context])
    }

    func testStaleDraftCannotOverwriteANewerProfile() async throws {
        let repo = SQLiteProfileRepository(database: try DoddyDatabase.inMemory(), now: { Self.t0 })
        var draft = ProfileDraft()
        draft[.name] = "Ola"
        let first = try await repo.commit(draft, basedOn: .empty)

        var other = first.draft
        other[.name] = "Ala"
        _ = try await repo.commit(other, basedOn: first)

        var stale = first.draft
        stale[.name] = "Olek"
        do {
            _ = try await repo.commit(stale, basedOn: first)
            XCTFail("a stale draft must not be saved")
        } catch {
            XCTAssertEqual(error as? ProfileStoreError, .revisionConflict)
        }
        let current = try await repo.profile()
        XCTAssertEqual(current.value(.name), "Ala")
    }

    func testInvalidDraftWritesNothing() async throws {
        let repo = SQLiteProfileRepository(database: try DoddyDatabase.inMemory(), now: { Self.t0 })
        var draft = ProfileDraft()
        draft[.name] = "Ola"
        draft[.context] = String(repeating: "x", count: ProfileKey.context.maxLength + 1)
        do {
            _ = try await repo.commit(draft, basedOn: .empty)
            XCTFail("expected validation error")
        } catch {
            XCTAssertNotNil(error as? ProfileValidationError)
        }
        let profile = try await repo.profile()
        XCTAssertTrue(profile.isEmpty)
    }

    func testForgettingTheProfileKeepsMemoriesAndDeletingMemoriesKeepsTheProfile() async throws {
        let database = try DoddyDatabase.inMemory()
        let profiles = SQLiteProfileRepository(database: database, now: { Self.t0 })
        let memories = SQLiteMemoryRepository(database: database)
        var draft = ProfileDraft()
        draft[.name] = "Ola"
        _ = try await profiles.commit(draft, basedOn: .empty)
        let memory = try await memories.save(NewMemory(text: "Spare keys are in the blue tin.", capturedAt: t0))

        try await profiles.forgetProfile()
        let profileAfterForget = try await profiles.profile()
        XCTAssertTrue(profileAfterForget.isEmpty)
        let memoriesAfterForget = try await memories.list(limit: nil)
        XCTAssertEqual(memoriesAfterForget.map(\.id), [memory.id])

        _ = try await profiles.commit(draft, basedOn: .empty)
        try await memories.deleteAll()
        let profileAfterDeleteAll = try await profiles.profile()
        XCTAssertEqual(profileAfterDeleteAll.value(.name), "Ola")
    }

    func testOnboardingProgressRoundTripsEveryStateAndSurvivesReopen() async throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repo = SQLiteProfileRepository(database: try DoddyDatabase(path: path), now: { Self.t0 })

        let initial = try await repo.onboarding()
        XCTAssertEqual(initial.route, .setup(.welcome))

        // Every enum value must pass the table's CHECK constraints.
        for step in SetupStep.allCases {
            let saved = try await repo.saveOnboarding(initial.guiding(to: step, at: t1))
            XCTAssertEqual(saved.setupStep, step)
        }
        for intro in IntroDecision.allCases {
            for finished in [true, false] {
                let progress = initial.finishingSetup(testPassed: finished, at: t1).decidingIntro(intro, at: t1)
                let saved = try await repo.saveOnboarding(progress)
                XCTAssertEqual(saved.setupDecision, finished ? .userReportedTestPassed : .userReportedDone)
            }
        }
        let skipped = initial.deferringSetup(at: t1).decidingIntro(.skipped, at: t1)
        _ = try await repo.saveOnboarding(skipped.guiding(to: .touch, at: t1))

        let reopened = SQLiteProfileRepository(database: try DoddyDatabase(path: path))
        let progress = try await reopened.onboarding()
        XCTAssertEqual(progress.route, .setup(.touch))
        XCTAssertEqual(progress.introDecision, .skipped)
    }

    func testUpgradeFromV1KeepsMemoriesAndStartsWithEmptyProfile() async throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let v1 = try DatabaseQueue(path: path)
        try DoddyDatabase.migrator.migrate(v1, upTo: "v1_memories")
        try await v1.write { db in
            try db.execute(
                sql: """
                    INSERT INTO memories (id, raw_text, current_text, category, source, captured_at_ms, search_text)
                    VALUES (?, 'Blue tin', 'Blue tin', 'other', 'explicit_text', 1, 'blue tin')
                    """,
                arguments: [UUID().uuidString])
        }
        try v1.close()

        let database = try DoddyDatabase(path: path)
        let memories = try await SQLiteMemoryRepository(database: database).list(limit: nil)
        XCTAssertEqual(memories.map(\.currentText), ["Blue tin"])
        let profile = try await SQLiteProfileRepository(database: database).profile()
        XCTAssertTrue(profile.isEmpty)
    }

    func testFileFromANewerAppVersionIsRejectedAndLeftUntouched() async throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        _ = try DoddyDatabase(path: path)
        let newer = try DatabaseQueue(path: path)
        try await newer.write { db in
            try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v99_future')")
        }
        try newer.close()
        let before = try Data(contentsOf: URL(fileURLWithPath: path))

        XCTAssertThrowsError(try DoddyDatabase(path: path)) { error in
            XCTAssertEqual(error as? DoddyDatabaseError, .newerSchema)
        }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), before)
    }
}

/// Settable clock for approval timestamps. Tests run it from one task at a time.
private final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}
