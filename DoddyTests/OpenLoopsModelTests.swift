import DoddyCore
import Foundation
import XCTest
#if canImport(Doddy)
@testable import Doddy
#endif

// The "Na oku" page's state (ADR-756): it builds its list from what the provider returns, shows a progress
// state until the first read finishes (never "nothing waiting" before then), names a source the provider
// could not read, and reads one time at a time. The list rules themselves are held by DoddyCore's
// OpenLoopsTests. Also run on Linux by scripts/test_open_loops_model.sh.

final class OpenLoopsModelTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()

    private func at(_ hour: Int) -> Date {
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5))!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    /// A clock that always says `date`; built here so the test class itself is not captured by a Sendable closure.
    private func fixed(_ date: Date) -> @Sendable () -> Date { { date } }

    private func input(_ titles: String...) -> OpenLoopsInput {
        OpenLoopsInput(appleReminders: titles.enumerated().map {
            ReminderSummary(id: "r\($0.offset)", title: $0.element, due: at(15 + $0.offset), dueHasTime: true)
        })
    }

    @MainActor
    func testItShowsProgressUntilTheFirstReadFinishesAndNeverEmptyBeforeThat() async {
        let model = OpenLoopsModel(provider: { OpenLoopsInput() }, now: fixed(at(12)), calendar: calendar)
        XCTAssertEqual(model.phase, .loading)
        XCTAssertNil(model.agenda)
        XCTAssertNil(model.refreshedAt)
        await model.refresh()
        XCTAssertNotNil(model.agenda)
        XCTAssertEqual(model.agenda?.isEmpty, true)
        XCTAssertEqual(model.refreshedAt, at(12))
        XCTAssertFalse(model.isRefreshing)
    }

    @MainActor
    func testTheListIsWhatTheProviderReturnedAtTheTimeOfTheRead() async {
        let model = OpenLoopsModel(provider: { self.input("Pay rent", "Call mum") }, now: fixed(at(12)), calendar: calendar)
        await model.refresh()
        XCTAssertEqual(model.agenda?.items(in: .today).map(\.id), ["appleReminder:r0", "appleReminder:r1"])
    }

    @MainActor
    func testAnUnreadableSourceStaysNamedAndIsNotShownAsEmpty() async {
        let model = OpenLoopsModel(provider: { OpenLoopsInput(unavailable: [.calendarEvent]) }, now: fixed(at(12)), calendar: calendar)
        await model.refresh()
        XCTAssertEqual(model.agenda?.unavailable, [.calendarEvent])
        XCTAssertEqual(model.agenda?.isEmpty, false)
    }

    @MainActor
    func testANewReadReplacesTheListAndKeepsNothingFromTheOldOne() async {
        var round = 0
        let model = OpenLoopsModel(provider: {
            round += 1
            return round == 1 ? self.input("Old") : self.input("New")
        }, now: fixed(at(12)), calendar: calendar)
        await model.refresh()
        XCTAssertEqual(model.agenda?.allItems.count, 1)
        await model.refresh()
        XCTAssertEqual(model.agenda?.allItems.compactMap { item -> String? in
            if case .text(let text) = item.title { return text }
            return nil
        }, ["New"])
    }

    @MainActor
    func testACallDuringAReadIsFoldedIntoOneMoreReadAfterIt() async {
        var reads = 0
        var model: OpenLoopsModel!
        model = OpenLoopsModel(provider: {
            reads += 1
            if reads == 1 { await model.refresh() }
            return self.input("Read \(reads)")
        }, now: fixed(at(12)), calendar: calendar)
        await model.refresh()
        XCTAssertEqual(reads, 2, "the overlapping call didn't start a read of its own, it asked for one more after the first")
        XCTAssertEqual(model.agenda?.allItems.first?.title, .text("Read 2"), "the list is the newer of the two reads")
        XCTAssertFalse(model.isRefreshing)
    }

    @MainActor
    func testTheLimitPerSectionIsPassedOn() async {
        let model = OpenLoopsModel(provider: { self.input("a", "b", "c") }, now: fixed(at(12)), calendar: calendar, limitPerSection: 2)
        await model.refresh()
        XCTAssertEqual(model.agenda?.items(in: .today).count, 2)
        XCTAssertEqual(model.agenda?.more[.today], 1)
    }
}
