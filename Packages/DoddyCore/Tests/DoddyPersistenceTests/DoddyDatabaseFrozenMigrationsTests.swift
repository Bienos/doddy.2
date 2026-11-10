@testable import DoddyPersistence
import XCTest

/// Merged migrations are frozen (engineering audit, 7 Nov 2026). On 11 Oct two were renamed while
/// branches were merged: `v5_memory_corrections` became `v9_memory_corrections` (82a90972) and
/// `v9_list_shares` became `v10_list_shares` (7f97700e). GRDB records each migration by name, so a
/// phone that had run the old name would then find a table that already exists, or be refused as
/// "written by a newer version" (`DoddyDatabaseError.newerSchema`).
///
/// `shipped` is every migration on `main`, in order. A pull request that adds a migration appends its
/// name here in the same commit. Never rename, reorder or remove an entry: write a new migration
/// instead. Two pull requests that both add the next migration now conflict in this file, where the
/// clash is cheap, instead of on someone's phone.
final class DoddyDatabaseFrozenMigrationsTests: XCTestCase {
    static let shipped = [
        "v1_memories",
        "v2_profile_onboarding",
        "v3_note_reminders",
        "v4_note_reminder_places",
        "v5_note_reminder_repeat",
        "v6_list_items",
        "v7_memory_photos",
        "v8_memory_audio",
        "v9_memory_corrections",
        "v10_list_shares",
        "v11_learned_facts",
        "v12_procedures",
        "v13_outcome_events",
        "v14_call_cases",
        "v15_errands",
        "v16_recordings",
        "v17_message_thread",
        "v18_thread_document",
        "v19_training_log",
        "v20_thread_photo",
        "v21_thread_file",
        "v22_thread_local_action",
    ]

    func testMergedMigrationsKeepTheirNamesAndTheirOrder() {
        let registered = DoddyDatabase.migrator.migrations
        XCTAssertEqual(
            Array(registered.prefix(Self.shipped.count)), Self.shipped,
            "A merged migration was renamed, reordered or removed. Put it back as it was and add a new migration instead.")
    }

    func testEveryRegisteredMigrationIsListed() {
        let registered = DoddyDatabase.migrator.migrations
        XCTAssertEqual(
            registered, Self.shipped,
            "Add a new migration's name to the end of `shipped` in the same commit that registers it.")
    }

    func testMigrationNamesAreUnique() {
        let registered = DoddyDatabase.migrator.migrations
        XCTAssertEqual(Set(registered).count, registered.count, "Two migrations share a name.")
    }
}
