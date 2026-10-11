import XCTest
@testable import DoddyCore

/// Voice diary (ADR-345).
final class DiaryTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func at(_ d: Int, _ h: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))! }

    func testLinesAreKeptAsWrittenByLocalDay() throws {
        var diary = Diary()
        _ = diary.add("  Long walk by the river. ", now: at(10, 21), calendar: calendar)
        _ = diary.add("Rainy, stayed in.", now: at(11, 8), calendar: calendar)
        _ = diary.add("Dinner with Gosia.", now: at(11, 20), calendar: calendar)
        XCTAssertEqual(diary.days.map(\.day), ["2026-10-11", "2026-10-10"])
        XCTAssertEqual(diary.days.first?.entries.map(\.text), ["Rainy, stayed in.", "Dinner with Gosia."])
        XCTAssertEqual(diary.days.last?.entries.first?.text, "Long walk by the river.")
        let reloaded = Diary(stored: diary.stored)
        XCTAssertEqual(reloaded, diary)
        let id = try XCTUnwrap(diary.entries.first?.id)
        diary.remove(id)
        XCTAssertFalse(diary.contains(id))
    }

    func testEmptyAndTooLongAreRefused() {
        var diary = Diary()
        XCTAssertEqual(diary.add("   ", now: at(11, 9), calendar: calendar), .failure(.empty))
        XCTAssertEqual(diary.add(String(repeating: "a", count: 501), now: at(11, 9), calendar: calendar), .failure(.tooLong))
        XCTAssertTrue(diary.entries.isEmpty)
    }

    func testVoiceCanOnlyProposeALineWithACard() {
        let request = VoiceToolRequest.parse(name: "add_to_diary", parametersJSON: Data(#"{"text": " Good day at work. "}"#.utf8))
        XCTAssertEqual(request, .addToDiary(text: "Good day at work."))
        guard case .refuse = CarProfile.decision(for: request) else { return XCTFail("needs a tap, so not while driving") }
        XCTAssertFalse(ConnectionPause.applies(to: request))
        // The diary's words are never written to What Doddy did.
        XCTAssertNil(ActivityRequest.describe(request, calendar: calendar)?.detail)
        guard case .invalid = VoiceToolRequest.parse(name: "add_to_diary", parametersJSON: Data(#"{"text": ""}"#.utf8)) else {
            return XCTFail("empty text")
        }
        XCTAssertTrue(VoiceToolReply.diarySaved(DiaryEntry(day: "2026-10-11", text: "x", savedAt: at(11, 9))).hasPrefix("saved:"))
    }
}
