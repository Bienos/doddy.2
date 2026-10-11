import XCTest
@testable import DoddyCore

/// Bills and subscriptions (ADR-344).
final class RenewalsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testNextDateRollsForwardByCycleAndKeepsMonthEnds() {
        let monthly = Renewal(name: "Rent", cycle: .monthly, start: day(2026, 1, 31))
        XCTAssertEqual(monthly.next(after: day(2026, 2, 10), calendar: calendar), day(2026, 2, 28))
        XCTAssertEqual(monthly.next(after: day(2026, 3, 1), calendar: calendar), day(2026, 3, 31))
        let weekly = Renewal(name: "Box", cycle: .weekly, start: day(2026, 10, 1))
        XCTAssertEqual(weekly.next(after: day(2026, 10, 11, 15), calendar: calendar), day(2026, 10, 15))
        // Today counts as next.
        XCTAssertEqual(weekly.next(after: day(2026, 10, 8, 20), calendar: calendar), day(2026, 10, 8))
        let yearly = Renewal(name: "Domain", cycle: .yearly, start: day(2024, 3, 1))
        XCTAssertEqual(yearly.next(after: day(2026, 10, 11), calendar: calendar), day(2027, 3, 1))
    }

    func testReminderIsDaysBeforeAtNineOrTheFollowingOne() {
        var netflix = Renewal(name: "Netflix", cycle: .monthly, start: day(2026, 9, 14), remindDaysBefore: 3)
        XCTAssertEqual(netflix.reminderDate(now: day(2026, 10, 1), calendar: calendar), day(2026, 10, 11, 9))
        // Too late for this month's: next month's.
        XCTAssertEqual(netflix.reminderDate(now: day(2026, 10, 12), calendar: calendar), day(2026, 11, 11, 9))
        netflix.remindDaysBefore = nil
        XCTAssertNil(netflix.reminderDate(now: day(2026, 10, 1), calendar: calendar))
    }

    func testSaveChecksTheFields() {
        var all = Renewals(stored: nil)
        XCTAssertEqual(all.save(Renewal(name: "  ", cycle: .monthly, start: day(2026, 1, 1))), .noName)
        XCTAssertEqual(all.save(Renewal(name: "Gym", amount: -5, currency: "PLN", cycle: .monthly, start: day(2026, 1, 1))), .badAmount)
        XCTAssertEqual(all.save(Renewal(name: "Gym", amount: 99, currency: "zł", cycle: .monthly, start: day(2026, 1, 1))), .badCurrency)
        XCTAssertEqual(all.save(Renewal(name: "Gym", cycle: .monthly, start: day(2026, 1, 1), remindDaysBefore: 30)), .badReminder)
        let gym = Renewal(name: "Gym", amount: 99, currency: "pln", cycle: .monthly, start: day(2026, 1, 1))
        XCTAssertNil(all.save(gym))
        XCTAssertEqual(Renewals(stored: all.stored).items.first?.currency, "PLN")
        var changed = gym
        changed.amount = 109
        XCTAssertNil(all.save(changed))
        XCTAssertEqual(all.items.count, 1)
        all.remove(gym.id)
        XCTAssertTrue(all.items.isEmpty)
    }

    func testMonthlyTotalsPerCurrencyAndMissingAmounts() {
        var all = Renewals(stored: nil)
        _ = all.save(Renewal(name: "Netflix", amount: 49, currency: "PLN", cycle: .monthly, start: day(2026, 1, 1)))
        _ = all.save(Renewal(name: "Insurance", amount: 1200, currency: "PLN", cycle: .yearly, start: day(2026, 1, 1)))
        _ = all.save(Renewal(name: "iCloud", amount: Decimal(string: "2.99")!, currency: "EUR", cycle: .monthly, start: day(2026, 1, 1)))
        _ = all.save(Renewal(name: "Water", cycle: .quarterly, start: day(2026, 1, 1)))
        let totals = all.monthlyTotals()
        XCTAssertEqual(totals.totals.map(\.currency), ["EUR", "PLN"])
        XCTAssertEqual(totals.totals.last?.amount, 149)
        XCTAssertEqual(totals.withoutAmount, 1)
    }

    func testVoiceToolIsReadOnlyAndNeverGuesses() {
        let request = VoiceToolRequest.parse(name: "upcoming_renewals", parametersJSON: Data(#"{"days": 7}"#.utf8))
        XCTAssertEqual(request, .upcomingRenewals(days: 7))
        XCTAssertEqual(CarProfile.decision(for: request), .run)
        XCTAssertFalse(ConnectionPause.applies(to: request))
        guard case .invalid = VoiceToolRequest.parse(name: "upcoming_renewals", parametersJSON: Data(#"{"days": 400}"#.utf8)) else {
            return XCTFail("400 days is too many")
        }
        var all = Renewals(stored: nil)
        let now = day(2026, 10, 11)
        XCTAssertTrue(VoiceToolReply.renewals([], days: 30, calendar: calendar, now: now).contains("hasn't added any"))
        _ = all.save(Renewal(name: "Netflix", amount: 49, currency: "PLN", cycle: .monthly, start: day(2026, 9, 14)))
        _ = all.save(Renewal(name: "Domain", cycle: .yearly, start: day(2026, 3, 1)))
        let reply = VoiceToolReply.renewals(all.upcoming(now: now, calendar: calendar), days: 30, calendar: calendar, now: now)
        XCTAssertTrue(reply.contains("Netflix on 2026-10-14, every month, 49 PLN"))
        XCTAssertFalse(reply.contains("Domain"))
    }
}

extension RenewalsTests {
    func testNotificationSaysOnlyWhatTheUserTypedIn() {
        let netflix = Renewal(name: "Netflix", amount: 49, currency: "PLN", cycle: .monthly, start: day(2026, 9, 14))
        let english = netflix.notification(next: day(2026, 10, 14), calendar: calendar)
        XCTAssertEqual(english.title, "Netflix renews soon")
        XCTAssertEqual(english.body, "On 14.10 (49 PLN). You added this in Doddy.")
        let polish = Renewal(name: "Woda", cycle: .quarterly, start: day(2026, 1, 1)).notification(next: day(2026, 10, 1), calendar: calendar, language: .polish)
        XCTAssertEqual(polish.body, "Dnia 01.10. Dodano to w Doddy.")
    }
}
