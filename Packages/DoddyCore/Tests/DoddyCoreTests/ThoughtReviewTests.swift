import Foundation
import XCTest
@testable import DoddyCore

/// "A thought is ready for review" (ADR-342): which note comes back, and when.
final class ThoughtReviewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(_ text: String, daysAgo: Double, category: MemoryCategory = .other) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: .explicitText, category: category,
                         capturedAt: now.addingTimeInterval(-daysAgo * 86_400))
    }

    func testNothingIsDueBeforeAWeekAndListsNeverAre() throws {
        let fresh = try note("Locker 4512", daysAgo: 6.9)
        let list = try note("Shopping", daysAgo: 30, category: .list)
        XCTAssertNil(ThoughtReview.due(memories: [fresh, list], log: ThoughtReviewLog(), now: now))
    }

    func testTheNewestUnreviewedNoteOlderThanAWeekComesFirst() throws {
        let old = try note("Old", daysAgo: 60)
        let lastWeek = try note("Last week", daysAgo: 8)
        let older = try note("Older", daysAgo: 20)
        let picked = ThoughtReview.due(memories: [old, lastWeek, older], log: ThoughtReviewLog(), now: now)
        XCTAssertEqual(picked?.id, lastWeek.id, "a note comes back about a week after it was saved")
        XCTAssertEqual(ThoughtReview.due(memories: [older, old, lastWeek], log: ThoughtReviewLog(), now: now)?.id,
                       lastWeek.id, "the same input picks the same note whatever the order")
    }

    func testAReviewedNoteWaitsAMonthThenTheLongestAgoComesBack() throws {
        let a = try note("A", daysAgo: 100)
        let b = try note("B", daysAgo: 90)
        var log = ThoughtReviewLog()
        log.mark(a.id, at: now.addingTimeInterval(-31 * 86_400))
        log.mark(b.id, at: now.addingTimeInterval(-29 * 86_400))
        XCTAssertEqual(ThoughtReview.due(memories: [a, b], log: log, now: now)?.id, a.id)
        log.mark(a.id, at: now.addingTimeInterval(-10 * 86_400))
        XCTAssertNil(ThoughtReview.due(memories: [a, b], log: log, now: now), "both reviewed less than a month ago")
    }

    func testUnreviewedNotesComeBeforeReviewedOnes() throws {
        let reviewed = try note("Reviewed", daysAgo: 200)
        let never = try note("Never", daysAgo: 10)
        var log = ThoughtReviewLog()
        log.mark(reviewed.id, at: now.addingTimeInterval(-100 * 86_400))
        XCTAssertEqual(ThoughtReview.due(memories: [reviewed, never], log: log, now: now)?.id, never.id)
    }

    func testANoteWithoutADateIsNeverDue() throws {
        let unknown = try MemoryRecord(id: UUID(), rawText: "Imported", source: .importedLegacyUnknown, capturedAt: nil)
        XCTAssertNil(ThoughtReview.due(memories: [unknown], log: ThoughtReviewLog(), now: now))
    }

    func testLogRoundTripsAndDropsDeletedNotes() throws {
        let kept = UUID(), gone = UUID()
        var log = ThoughtReviewLog()
        log.mark(kept, at: now)
        log.mark(gone, at: now)
        let decoded = ThoughtReviewLog.decoded(try log.encoded())
        XCTAssertEqual(decoded, log)
        var pruned = decoded
        pruned.keepOnly([kept])
        XCTAssertEqual(pruned.reviewed.keys.map { $0 }, [kept])
        XCTAssertEqual(ThoughtReviewLog.decoded(nil), ThoughtReviewLog())
        XCTAssertEqual(ThoughtReviewLog.decoded(Data("junk".utf8)), ThoughtReviewLog(), "damage reads as empty, never crashes")
    }

    func testNextFireIsTheNextClockTimeStrictlyAfterNow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 12))!
        let later = ThoughtReview.nextFire(after: noon, hour: 19, minute: 30, calendar: calendar)
        XCTAssertEqual(later, calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 19, minute: 30)))
        let earlier = ThoughtReview.nextFire(after: noon, hour: 8, minute: 0, calendar: calendar)
        XCTAssertEqual(earlier, calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 8)))
        let exact = ThoughtReview.nextFire(after: later, hour: 19, minute: 30, calendar: calendar)
        XCTAssertEqual(exact, calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 19, minute: 30)),
                       "the very moment counts as passed")
    }

    func testSettingsClampAndStore() {
        let defaults = UserDefaults(suiteName: "ThoughtReviewTests-\(UUID().uuidString)")!
        XCTAssertEqual(ThoughtReviewSettings.stored(defaults), ThoughtReviewSettings())
        XCTAssertFalse(ThoughtReviewSettings().isOn, "off until the user turns it on")
        let chosen = ThoughtReviewSettings(isOn: true, hour: 25, minute: -1)
        XCTAssertEqual(chosen.hour, 23)
        XCTAssertEqual(chosen.minute, 0)
        chosen.store(defaults)
        XCTAssertEqual(ThoughtReviewSettings.stored(defaults), chosen)
    }

    func testWordsCarryNoNoteText() {
        for language in [NotificationLanguage.english, .polish] {
            XCTAssertFalse(ThoughtReview.title(language).isEmpty)
            XCTAssertFalse(ThoughtReview.body(language).isEmpty)
            XCTAssertFalse(ThoughtReview.openAction(language).isEmpty)
        }
        XCTAssertTrue(ThoughtReview.isReview(notificationID: ThoughtReview.notificationID))
        XCTAssertFalse(ThoughtReview.isReview(notificationID: "doddy.weekly-lookback"))
    }
}
