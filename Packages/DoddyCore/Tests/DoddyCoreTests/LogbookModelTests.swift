import Foundation
import XCTest
@testable import DoddyCore

/// Logbook on the iPhone: on by default (owner, 9 Nov 2026), off stops counting at once, and the
/// server's deletion is reported only once it confirmed (DOD-08).

private final class FakeLogbook: LogbookClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    private var _days: [String] = []
    var serverOn = false
    var storedDays = 3
    var failNext: LogbookError?
    var failAll: LogbookError?

    var calls: [String] { lock.withLock { _calls } }
    var days: [String] { lock.withLock { _days } }

    private func failure() -> LogbookError? {
        lock.withLock {
            if let failAll { return failAll }
            defer { failNext = nil }
            return failNext
        }
    }

    func setEnabled(_ enabled: Bool) async throws(LogbookError) -> Int {
        lock.withLock { _calls.append("state:\(enabled)") }
        if let error = failure() { throw error }
        serverOn = enabled
        return enabled ? 0 : storedDays
    }

    func putDay(_ day: LogbookDay) async throws(LogbookError) {
        lock.withLock { _calls.append("day:\(day.day)") }
        if let error = failure() { throw error }
        guard serverOn else { throw .off }
        lock.withLock { _days.append(day.day) }
    }

    func deleteAll() async throws(LogbookError) -> Int {
        lock.withLock { _calls.append("delete") }
        return storedDays
    }
}

private let noon = Date(timeIntervalSince1970: 1_794_222_000) // 9 Nov 2026, 11:00 UTC, 12:00 in Warsaw
private let warsawCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
    return calendar
}()

@MainActor
final class LogbookModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "logbook-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func model(_ fake: FakeLogbook?, now: Date = noon) -> LogbookModel {
        LogbookModel(
            makeClient: { fake }, renewClient: { fake }, defaults: defaults,
            now: { now }, calendar: { warsawCalendar })
    }

    func testItIsOnByDefaultAndTurnsTheServerOnBeforeSending() async {
        let fake = FakeLogbook()
        let logbook = model(fake)
        XCTAssertTrue(logbook.isOn, "on unless the person turned it off")
        await logbook.sync(sources: LogbookSources())
        XCTAssertEqual(fake.calls.first, "state:true")
        XCTAssertEqual(fake.days.count, 8, "the last week, then today")
        XCTAssertNil(logbook.problem)
        XCTAssertEqual(logbook.lastSent, noon)

        // The next sync within the hour sends nothing and doesn't ask the server again.
        let before = fake.calls.count
        await logbook.sync(sources: LogbookSources())
        XCTAssertEqual(fake.calls.count, before)
    }

    func testTurningItOffStopsCountingAndReportsTheDeletionOnlyOnceConfirmed() async {
        let fake = FakeLogbook()
        let logbook = model(fake)
        await logbook.sync(sources: LogbookSources())
        logbook.recordConversation(LogbookConversation(startedAt: noon, endedAt: noon.addingTimeInterval(60), ended: "user", language: "pl"))
        XCTAssertEqual(logbook.storedConversations().count, 1)

        fake.failNext = .transport
        let confirmed = await logbook.setOn(false, sources: LogbookSources())
        XCTAssertFalse(confirmed)
        XCTAssertFalse(logbook.isOn, "counting stops at once")
        XCTAssertTrue(logbook.storedConversations().isEmpty, "nothing more is kept for Logbook")
        XCTAssertNil(logbook.deletedDays, "never 'deleted' before the server says so")
        XCTAssertTrue(logbook.deletionPending)
        XCTAssertEqual(logbook.problem, .offline)

        logbook.recordConversation(LogbookConversation(startedAt: noon, endedAt: noon, ended: "user", language: "pl"))
        XCTAssertTrue(logbook.storedConversations().isEmpty, "off counts nothing")

        // The next sync asks the server again, and sends nothing.
        let sentBefore = fake.days.count
        await logbook.sync(sources: LogbookSources())
        XCTAssertEqual(fake.calls.last, "state:false")
        XCTAssertEqual(logbook.deletedDays, 3)
        XCTAssertFalse(logbook.deletionPending)
        XCTAssertEqual(fake.days.count, sentBefore)
    }

    func testTheChoiceIsKeptAcrossLaunches() async {
        let fake = FakeLogbook()
        let first = model(fake)
        await first.setOn(false, sources: LogbookSources())
        XCTAssertFalse(model(fake).isOn)
    }

    func testAServerThatHasItOffForThisAccountIsTurnedOnAgainOnce() async {
        let fake = FakeLogbook()
        let logbook = model(fake)
        await logbook.sync(sources: LogbookSources())
        // Another account signed in on this iPhone: its server state is off.
        fake.serverOn = false
        let later = model(fake, now: noon.addingTimeInterval(7_200))
        await later.sync(sources: LogbookSources())
        XCTAssertTrue(fake.calls.suffix(3).contains("state:true"), "turned on again")
        XCTAssertEqual(fake.days.last, "2026-11-09")
        XCTAssertNil(later.problem)
    }

    func testWithoutAServerNothingIsSentAndTheProblemIsNamed() async {
        let logbook = model(nil)
        await logbook.sync(sources: LogbookSources())
        XCTAssertEqual(logbook.problem, .notConfigured)
        XCTAssertNil(logbook.lastSent)
    }

    func testAFailedDayIsSentAgainNextTime() async {
        let fake = FakeLogbook()
        let logbook = model(fake)
        fake.failAll = .transport
        await logbook.sync(sources: LogbookSources())
        XCTAssertEqual(logbook.problem, .offline)
        fake.failAll = nil
        await logbook.sync(sources: LogbookSources())
        XCTAssertEqual(fake.days.count, 8, "every day is sent once the server answers")
        XCTAssertNil(logbook.problem)
    }

    func testOldConversationsAreNotKeptForever() {
        let logbook = model(FakeLogbook())
        let old = noon.addingTimeInterval(-10 * 86_400)
        logbook.recordConversation(LogbookConversation(startedAt: old, endedAt: old, ended: "user", language: "pl"))
        logbook.recordConversation(LogbookConversation(startedAt: noon, endedAt: noon, ended: "user", language: "pl"))
        XCTAssertEqual(logbook.storedConversations().map(\.startedAt), [noon], "only what can still be sent")
    }
}
