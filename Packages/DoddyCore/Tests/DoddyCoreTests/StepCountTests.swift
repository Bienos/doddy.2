import Foundation
import XCTest
@testable import DoddyCore

/// read_steps (ADR-567): which day, the seven-day limit, and the exact numbers the agent hears.
final class StepCountTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    /// Tuesday 20 October 2026, 14:05 in Warsaw.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 14, minute: 5))! }

    private func parse(_ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: VoiceToolName.readSteps, parametersJSON: Data(json.utf8), now: now, calendar: calendar)
    }

    func testDays() {
        XCTAssertEqual(parse("{}"), .readSteps(StepDay(daysAgo: 0)!))
        XCTAssertEqual(parse(#"{"day":"Today"}"#), .readSteps(StepDay(daysAgo: 0)!))
        XCTAssertEqual(parse(#"{"day":"yesterday"}"#), .readSteps(StepDay(daysAgo: 1)!))
        XCTAssertEqual(parse(#"{"day":"2026-10-14"}"#), .readSteps(StepDay(daysAgo: 6)!))
        XCTAssertEqual(parse(#"{"day":"2026-10-20"}"#), .readSteps(StepDay(daysAgo: 0)!))
    }

    func testOnlyTheLastSevenDays() {
        let kept = VoiceToolRequest.invalid(name: "read_steps", reason: "the iPhone keeps steps for the last 7 days only, today included; a future day has none")
        XCTAssertEqual(parse(#"{"day":"2026-10-13"}"#), kept)
        XCTAssertEqual(parse(#"{"day":"2026-10-21"}"#), kept)
        XCTAssertEqual(parse(#"{"day":"last week"}"#), .invalid(name: "read_steps", reason: "day must be today, yesterday or a date written YYYY-MM-DD"))
        XCTAssertNil(StepDay(daysAgo: 7))
        XCTAssertNil(StepDay(daysAgo: -1))
    }

    func testRanges() {
        let today = StepDay(daysAgo: 0)!.range(now: now, calendar: calendar)
        XCTAssertEqual(today.start, calendar.startOfDay(for: now))
        XCTAssertEqual(today.end, now, "today counts until now")
        let yesterday = StepDay(daysAgo: 1)!.range(now: now, calendar: calendar)
        XCTAssertEqual(yesterday.end, calendar.startOfDay(for: now))
        XCTAssertEqual(calendar.dateComponents([.day], from: yesterday.start).day, 19)
    }

    func testRules() {
        let request = VoiceToolRequest.readSteps(StepDay(daysAgo: 1)!)
        XCTAssertEqual(VoiceConnection.serving(VoiceToolName.readSteps), .steps)
        guard case .yesFirst(let card) = AskFirst.need(for: request) else { return XCTFail("a read asks first (ASK-01)") }
        XCTAssertEqual(card.lines, ["Yesterday, from Motion & Fitness"])
        XCTAssertTrue(ConnectionPause.applies(to: request))
        XCTAssertEqual(CarProfile.decision(for: request), .run, "a read is fine while driving")
        XCTAssertEqual(ToolCatalog.descriptor(VoiceToolName.readSteps)?.effect, .lookup)
        XCTAssertEqual(ActivityRequest.describe(request, calendar: calendar)?.app, .steps)
    }

    func testTheReplyHasTheExactNumbers() {
        let reply = VoiceToolReply.steps(StepTotals(steps: 6_240, distanceMeters: 4_318, floorsUp: 5), day: StepDay(daysAgo: 0)!, until: now, calendar: calendar)
        XCTAssertTrue(reply.hasPrefix("Today until 14:05, from the iPhone's Motion & Fitness:"))
        XCTAssertTrue(reply.contains("Steps: 6240"))
        XCTAssertTrue(reply.contains("Walking distance: 4.3 km"))
        XCTAssertTrue(reply.contains("Floors climbed: 5"))
        let short = VoiceToolReply.steps(StepTotals(steps: 120, distanceMeters: 84, floorsUp: nil), day: StepDay(daysAgo: 2)!, until: nil, calendar: calendar)
        XCTAssertTrue(short.contains("2 days ago, from"))
        XCTAssertTrue(short.contains("Walking distance: 80 m"))
        XCTAssertFalse(short.contains("Floors"), "an iPhone without a barometer reports none")
    }
}
