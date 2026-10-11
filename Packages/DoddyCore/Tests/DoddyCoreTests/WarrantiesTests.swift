import XCTest
@testable import DoddyCore

/// Warranties and receipts (ADR-342).
final class WarrantiesTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testPolishReceiptGivesDateAndLength() {
        let receipt = """
        MEDIA EXPERT sp. z o.o.
        PARAGON FISKALNY
        2026-03-14 18:22
        Odkurzacz XY-200  899,00
        Gwarancja producenta: 24 miesiące
        Zwrot do 28.03.2026
        """
        let suggestion = WarrantyReading.suggest(from: receipt, now: day(2026, 3, 20), calendar: calendar)
        XCTAssertEqual(suggestion.purchased, day(2026, 3, 14))
        XCTAssertEqual(suggestion.months, 24)
    }

    func testFutureDatesAreNotThePurchase() {
        let text = "Bought 01/02/2026\nReturn by 01/03/2026\nWarranty 2 years"
        let suggestion = WarrantyReading.suggest(from: text, now: day(2026, 2, 10), calendar: calendar)
        XCTAssertEqual(suggestion.purchased, day(2026, 2, 1))
        XCTAssertEqual(suggestion.months, 24)
    }

    func testLengthOnlyFromAWarrantyLine() {
        XCTAssertNil(WarrantyReading.months(in: "Abo 12 Monate\nSumme 49,99"))
        XCTAssertEqual(WarrantyReading.months(in: "Garantie: 3 Jahre"), 36)
        XCTAssertEqual(WarrantyReading.months(in: "Gwarancja 12 m-cy"), 12)
        XCTAssertEqual(WarrantyReading.months(in: "Warranty: 6 months"), 6)
        XCTAssertNil(WarrantyReading.months(in: "Warranty 500 months"))
    }

    func testImpossibleDatesAreIgnored() {
        XCTAssertTrue(WarrantyReading.dates(in: "31.02.2026 and 45.13.2026", calendar: calendar).isEmpty)
        XCTAssertEqual(WarrantyReading.dates(in: "14.03.26", calendar: calendar), [day(2026, 3, 14)])
    }

    func testReminderIsAMonthBeforeAtNineOrNone() {
        let warranty = Warranty(id: UUID(), purchased: day(2026, 3, 14), months: 24, title: "Vacuum")
        XCTAssertEqual(warranty.ends(calendar: calendar), day(2028, 3, 14))
        XCTAssertEqual(warranty.reminderDate(calendar: calendar, now: day(2026, 3, 20)), day(2028, 2, 14, 9))
        XCTAssertNil(warranty.reminderDate(calendar: calendar, now: day(2028, 2, 20)))
    }

    func testStoreSavesReplacesAndDropsDeletedNotes() {
        var store = Warranties(stored: nil)
        let id = UUID()
        XCTAssertEqual(store.save(Warranty(id: id, purchased: day(2026, 1, 1), months: 12, title: "  Kettle ")), .saved)
        XCTAssertEqual(store.warranty(for: id)?.title, "Kettle")
        XCTAssertEqual(store.save(Warranty(id: id, purchased: day(2026, 1, 1), months: 24, title: "Kettle")), .replaced)
        XCTAssertEqual(store.save(Warranty(id: UUID(), purchased: day(2026, 1, 1), months: 0, title: "x")), .invalid)
        let reloaded = Warranties(stored: store.stored)
        XCTAssertEqual(reloaded.items.count, 1)
        XCTAssertEqual(reloaded.warranty(for: id)?.months, 24)
        store.keep(only: [])
        XCTAssertTrue(store.items.isEmpty)
    }

    func testRunningWarrantiesFirstSoonestEnd() {
        var store = Warranties(stored: nil)
        let ended = Warranty(id: UUID(), purchased: day(2020, 1, 1), months: 12, title: "Old")
        let soon = Warranty(id: UUID(), purchased: day(2025, 1, 1), months: 24, title: "Soon")
        let later = Warranty(id: UUID(), purchased: day(2026, 1, 1), months: 36, title: "Later")
        for item in [later, ended, soon] { _ = store.save(item) }
        XCTAssertEqual(store.sorted(calendar: calendar, now: day(2026, 6, 1)).map(\.title), ["Soon", "Later", "Old"])
    }
}
