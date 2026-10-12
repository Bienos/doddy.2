import XCTest
@testable import DoddyCore

final class MorningWaveTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: 30))!
    }

    func testTheFirstMorningVisitWaves() {
        XCTAssertEqual(MorningWave.dayToRecord(now: date(11, 8), lastWaveDay: nil, calendar: calendar), "2026-10-11")
        XCTAssertEqual(MorningWave.dayToRecord(now: date(11, 8), lastWaveDay: "2026-10-10", calendar: calendar), "2026-10-11")
    }

    func testASecondVisitTheSameMorningDoesNot() {
        XCTAssertNil(MorningWave.dayToRecord(now: date(11, 9), lastWaveDay: "2026-10-11", calendar: calendar))
    }

    func testTheAfternoonNeverWaves() {
        XCTAssertNil(MorningWave.dayToRecord(now: date(11, 12), lastWaveDay: nil, calendar: calendar))
        XCTAssertNil(MorningWave.dayToRecord(now: date(11, 18), lastWaveDay: "2026-10-10", calendar: calendar))
    }

    func testTheKeyIsGregorianOnAnyCalendar() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = calendar.timeZone
        XCTAssertEqual(MorningWave.dayKey(date(11, 8), calendar: buddhist), "2026-10-11")
    }
}
