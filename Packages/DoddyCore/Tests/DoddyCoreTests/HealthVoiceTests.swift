import Foundation
import XCTest
@testable import DoddyCore

/// Sport mode step 3 (ADR-623): "How did my week go?" by voice, read_health_week.
final class HealthVoiceTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { at(24, 9, 30) }

    func testTheToolParsesAndAsksFirst() {
        let request = VoiceToolRequest.parse(name: VoiceToolName.readHealthWeek, parametersJSON: Data("{}".utf8), now: now, calendar: calendar)
        XCTAssertEqual(request, .readHealthWeek)
        XCTAssertEqual(ToolCatalog.descriptor(VoiceToolName.readHealthWeek)?.approval, .askFirst, "ASK-01: a read of the person's data asks first")
        XCTAssertEqual(ToolCatalog.descriptor(VoiceToolName.readHealthWeek)?.effect, .lookup)
        guard case .yesFirst(let card) = AskFirst.need(for: request, calendar: calendar) else {
            return XCTFail("expected a yes first")
        }
        XCTAssertEqual(card.title, "Read your week from Apple Health?")
        XCTAssertTrue(card.lines.contains("A short summary goes to Doddy's voice"), "the card says the summary leaves the iPhone")
        XCTAssertFalse(AskFirst.publicLookups.contains(VoiceToolName.readHealthWeek), "never a public lookup that runs at once")
    }

    func testItIsLoggedPausedAndAllowedInTheCar() {
        let activity = ActivityRequest.describe(.readHealthWeek, calendar: calendar)
        XCTAssertEqual(activity?.app, .health)
        XCTAssertEqual(activity?.isLookup, true)
        XCTAssertEqual(ActivityApp.health.title, "Apple Health")
        XCTAssertEqual(ActivityText.title("Read the week from Apple Health", .polish), "Odczytano tydzień z Apple Health")
        XCTAssertTrue(ConnectionPause.applies(to: .readHealthWeek), "Pause all connections stops it")
        XCTAssertEqual(CarProfile.decision(for: .readHealthWeek), .run, "a read, answered by voice")
        XCTAssertNil(VoiceConnection.serving(VoiceToolName.readHealthWeek), "gated by its own consent, not a Connections switch")
    }

    func testConsentVersionIsSeparateFromMessages() {
        XCTAssertFalse(HealthVoiceConsent.isGranted(storedVersion: 0))
        XCTAssertTrue(HealthVoiceConsent.isGranted(storedVersion: HealthVoiceConsent.version))
    }

    func testWhatTheAgentHears() {
        let run = HealthWorkout(activity: .running, start: at(22, 7, 5), end: at(22, 7, 52).addingTimeInterval(15),
                                distanceMeters: 8200, activeKilocalories: 610.4, averageHeartRate: 151.6)
        let lift = HealthWorkout(activity: .strength, start: at(20, 18), end: at(20, 18, 55), distanceMeters: nil,
                                 activeKilocalories: nil, averageHeartRate: nil)
        let glance = HealthGlance(
            workouts: [run, lift],
            thisWeek: WeekTotals.of([run, lift], in: HealthWindow.lastDays(now: now, calendar: calendar)),
            previousWeek: WeekTotals(workouts: 1, duration: 1800, runningMeters: 5000, runningSecondsWithDistance: 1800),
            lastNight: SleepNight(asleep: 27_000, core: 18_000, deep: 3600, rem: 5400, fellAsleep: at(23, 23), wokeUp: at(24, 6, 30)),
            restingHeartRate: ReadingGlance(latest: HealthReading(value: 52.4, date: at(24, 7)), average: 53.6, days: 7),
            heartRateVariability: ReadingGlance(latest: HealthReading(value: 48, date: at(24, 6)), average: 50.2, days: 6),
            vo2Max: HealthReading(value: 44.12, date: at(20, 8)))
        let reply = VoiceToolReply.healthWeek(glance, calendar: calendar)
        let lines = reply.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "From Apple Health on the iPhone, worked out there. Say only these numbers; never guess others.")
        XCTAssertEqual(lines[2], "- Run, Thu 7:05, 8.20 km, 47:15, 5:46 /km, average heart rate 152 bpm, 610 active kcal")
        XCTAssertEqual(lines[3], "- Strength training, Tue 18:00, 55:00")
        XCTAssertEqual(lines[4], "Last 7 days in total: 2 workouts, 1 h 42 min, running 8.2 km at 5:46 /km on average.")
        XCTAssertEqual(lines[5], "The 7 days before: 1 workout, 30 min, running 5.0 km at 6:00 /km on average.")
        XCTAssertEqual(lines[6], "Last night: 7 h 30 min asleep (deep 1 h 0 min, REM 1 h 30 min, core 5 h 0 min).")
        XCTAssertEqual(lines[7], "Resting heart rate: 52 bpm, 7-day average 54.")
        XCTAssertEqual(lines[8], "Heart rate variability: 48 ms, 7-day average 50.")
        XCTAssertEqual(lines[9], "VO2 max: 44.1 ml/kg/min.")
        XCTAssertTrue(lines[10].contains("no diagnosis, no medical advice"))
        XCTAssertTrue(lines[10].contains("call 112"), "the red flags are in every reply")
    }

    func testAQuietWeekSaysNoneInsteadOfInventing() {
        let glance = HealthGlance(workouts: [], lastNight: nil, restingHeartRate: nil, heartRateVariability: nil, vo2Max: nil)
        let reply = VoiceToolReply.healthWeek(glance, calendar: calendar)
        XCTAssertTrue(reply.contains("Workouts in the last 7 days: none recorded."))
        XCTAssertTrue(reply.contains("Last 7 days in total: 0 workouts."))
        XCTAssertFalse(reply.contains("Last night"), "no sleep line when Health has no sleep")
    }

    func testOnlyTenWorkoutsAreListed() {
        let many = (0..<13).map { HealthWorkout(activity: .walking, start: at(23, 8).addingTimeInterval(Double(-$0) * 3600), end: at(23, 8, 30).addingTimeInterval(Double(-$0) * 3600),
                                               distanceMeters: nil, activeKilocalories: nil, averageHeartRate: nil) }
        let reply = VoiceToolReply.healthWeek(HealthGlance(workouts: many, lastNight: nil, restingHeartRate: nil, heartRateVariability: nil, vo2Max: nil), calendar: calendar)
        XCTAssertEqual(reply.components(separatedBy: "\n").filter { $0.hasPrefix("- Walk") }.count, 10)
        XCTAssertTrue(reply.contains("- and 3 older ones"))
    }

    func testRefusalsDontInvent() {
        XCTAssertTrue(VoiceToolReply.healthWeekNotAllowed.hasPrefix("not allowed:"))
        XCTAssertTrue(VoiceToolReply.healthWeekEmpty.hasPrefix("empty:"))
        XCTAssertTrue(VoiceToolReply.healthWeekFailed("locked").contains("Don't guess"))
    }
}
