import DoddyCore
import Foundation
import GRDB

/// Reviewed profile and first-use progress, in the same SQLite file as memories but in their
/// own tables. Every write is one transaction and is read back before success is returned.
public final class SQLiteProfileRepository: ProfileRepository {
    private let dbQueue: DatabaseQueue
    private let now: @Sendable () -> Date

    public init(database: DoddyDatabase, now: @escaping @Sendable () -> Date = Date.init) {
        self.dbQueue = database.queue
        self.now = now
    }

    // MARK: Profile

    public func profile() async throws -> ApprovedProfile {
        try await dbQueue.read(Self.fetchProfile)
    }

    public func commit(_ draft: ProfileDraft, basedOn: ApprovedProfile) async throws -> ApprovedProfile {
        let desired = try draft.validated()
        let approvedAt = DoddyDatabase.truncatedToMilliseconds(now())
        return try await dbQueue.write { db in
            let current = try Self.fetchProfile(db)
            guard current == basedOn else { throw ProfileStoreError.revisionConflict }

            var expected: [ProfileKey: ProfileField] = [:]
            for key in ProfileKey.allCases {
                let existing = current.fields[key]
                guard let value = desired[key] else {
                    if existing != nil {
                        try db.execute(sql: "DELETE FROM profile_fields WHERE key = ?", arguments: [key.rawValue])
                    }
                    continue
                }
                if let existing, existing.value == value {
                    expected[key] = existing
                    continue
                }
                let field = ProfileField(
                    key: key, value: value, approvedAt: approvedAt, revision: (existing?.revision ?? 0) + 1)
                try db.execute(
                    sql: """
                        INSERT INTO profile_fields (key, value, source, approved_at_ms, revision)
                        VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(key) DO UPDATE SET
                            value = excluded.value, source = excluded.source,
                            approved_at_ms = excluded.approved_at_ms, revision = excluded.revision
                        """,
                    arguments: [
                        key.rawValue, field.value, field.source.rawValue,
                        DoddyDatabase.milliseconds(field.approvedAt), field.revision,
                    ])
                expected[key] = field
            }
            let stored = try Self.fetchProfile(db)
            guard stored == ApprovedProfile(fields: expected) else { throw ProfileStoreError.verificationFailed }
            return stored
        }
    }

    public func forgetProfile() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM profile_fields")
        }
    }

    // MARK: Onboarding progress

    public func onboarding() async throws -> OnboardingProgress {
        let fallback = OnboardingProgress.initial(at: DoddyDatabase.truncatedToMilliseconds(now()))
        return try await dbQueue.read { db in try Self.fetchProgress(db) ?? fallback }
    }

    public func saveOnboarding(_ progress: OnboardingProgress) async throws -> OnboardingProgress {
        var progress = progress
        progress.updatedAt = DoddyDatabase.truncatedToMilliseconds(progress.updatedAt)
        return try await dbQueue.write { [progress] db in
            try db.execute(
                sql: """
                    INSERT INTO onboarding_progress
                        (id, walkthrough_version, setup_decision, setup_step, intro_decision, updated_at_ms)
                    VALUES (1, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        walkthrough_version = excluded.walkthrough_version,
                        setup_decision = excluded.setup_decision, setup_step = excluded.setup_step,
                        intro_decision = excluded.intro_decision, updated_at_ms = excluded.updated_at_ms
                    """,
                arguments: [
                    progress.walkthroughVersion, progress.setupDecision.rawValue, progress.setupStep?.rawValue,
                    progress.introDecision.rawValue, DoddyDatabase.milliseconds(progress.updatedAt),
                ])
            guard try Self.fetchProgress(db) == progress else { throw ProfileStoreError.verificationFailed }
            return progress
        }
    }

    // MARK: Helpers

    private static func fetchProfile(_ db: Database) throws -> ApprovedProfile {
        var fields: [ProfileKey: ProfileField] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT * FROM profile_fields") {
            let keyString: String = row["key"]
            guard let key = ProfileKey(rawValue: keyString),
                  let source = ProfileSource(rawValue: row["source"])
            else { throw ProfileStoreError.corruptRecord(keyString) }
            let field = ProfileField(
                key: key, value: row["value"], source: source,
                approvedAt: DoddyDatabase.date(milliseconds: row["approved_at_ms"]), revision: row["revision"])
            // Re-check the domain rules on read; a row that breaks them is reported, not shown.
            guard (try? ProfileDraft(values: [key: field.value]).validated()[key]) == field.value else {
                throw ProfileStoreError.corruptRecord(keyString)
            }
            fields[key] = field
        }
        return ApprovedProfile(fields: fields)
    }

    private static func fetchProgress(_ db: Database) throws -> OnboardingProgress? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM onboarding_progress WHERE id = 1") else { return nil }
        guard let setupDecision = SetupDecision(rawValue: row["setup_decision"]),
              let introDecision = IntroDecision(rawValue: row["intro_decision"])
        else { throw ProfileStoreError.corruptRecord("onboarding_progress") }
        let stepString: String? = row["setup_step"]
        let step = try stepString.map { raw in
            guard let step = SetupStep(rawValue: raw) else { throw ProfileStoreError.corruptRecord("onboarding_progress") }
            return step
        }
        return OnboardingProgress(
            walkthroughVersion: row["walkthrough_version"], setupDecision: setupDecision, setupStep: step,
            introDecision: introDecision, updatedAt: DoddyDatabase.date(milliseconds: row["updated_at_ms"]))
    }
}
