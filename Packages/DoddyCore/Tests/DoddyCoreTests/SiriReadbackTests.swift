@testable import DoddyCore
import Foundation
import XCTest

/// ADR-232. What Siri says, from synthetic notes.
final class SiriReadbackTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private var now: Date { day(2026, 10, 12) }

    private func note(_ text: String, _ date: Date?, terms: [String] = ["gate"], meaning: Double? = nil) throws -> MemoryCandidate {
        let record = try MemoryRecord(id: UUID(), rawText: text, source: date == nil ? .importedLegacyUnknown : .explicitText, capturedAt: date)
        return MemoryCandidate(record: record, matchedTerms: meaning == nil ? terms : [], meaningScore: meaning)
    }

    private func say(_ candidates: [MemoryCandidate]) -> String {
        SiriReadback.reply(.matches(candidates)) { SiriReadback.savedText($0, now: self.now, calendar: self.calendar) }
    }

    func testOneNoteIsReadInItsOwnWords() throws {
        XCTAssertEqual(say([try note("Gate code 4821", day(2026, 10, 3))]), "You saved this on 3 October: “Gate code 4821”.")
    }

    func testNoMatchIsSaidPlainly() {
        XCTAssertEqual(SiriReadback.reply(.noMatch) { _ in "" }, "I couldn't find that in your saved memories.")
        XCTAssertEqual(SiriReadback.reply(.matches([])) { _ in "" }, RecallCopy.noMatch)
    }

    func testSeveralNotesReadTwoAndCountTheRest() throws {
        let spoken = say([
            try note("Gate code is on the fridge", day(2026, 10, 11), terms: ["gate", "code"]),
            try note("Gate to the garden sticks", day(2026, 9, 1)),
            try note("Gate repair Tuesday", day(2025, 4, 2)),
        ])
        XCTAssertEqual(spoken, "I found 3 notes. The closest match, saved yesterday: “Gate code is on the fridge”. Next, saved on 1 September: “Gate to the garden sticks”. There's one more. Open Doddy to see them.")
    }

    func testNotesThatDisagreeAreBothReadAndNoneIsPicked() throws {
        let spoken = say([
            try note("Gate code 4821", day(2026, 10, 3), terms: ["gate", "code"]),
            try note("Gate code 5555", day(2026, 10, 12), terms: ["gate", "code"]),
        ])
        XCTAssertEqual(spoken, "Two of your notes give different numbers. One, saved on 3 October: “Gate code 4821”. The other, saved today: “Gate code 5555”. Check which one is current.")
    }

    func testMeaningOnlyMatchIsAMaybe() throws {
        let spoken = say([try note("Kasia says the sushi spot on Mokotowska is great", day(2026, 10, 1), meaning: 0.8)])
        XCTAssertEqual(spoken, "No note uses those words. This one might be what you mean, saved on 1 October: “Kasia says the sushi spot on Mokotowska is great”.")
    }

    func testMeaningMatchesAreNeverReadNextToWordMatches() throws {
        let spoken = say([
            try note("Gate code 4821", day(2026, 10, 3)),
            try note("Fence repair man Adam", day(2026, 10, 3), meaning: 0.9),
        ])
        XCTAssertFalse(spoken.contains("Adam"))
        XCTAssertTrue(spoken.hasPrefix("You saved this"))
    }

    func testLongNotesAreCutAtAWordAndLinesBecomePauses() throws {
        let long = (1...80).map { "word\($0)" }.joined(separator: " ")
        let spoken = say([try note("Parcel locker\n\nCode 1234\n" + long, day(2026, 10, 3))])
        XCTAssertTrue(spoken.contains("“Parcel locker. Code 1234. word1 word2"))
        XCTAssertTrue(spoken.hasSuffix("…” It goes on; open Doddy for the rest."))
        XCTAssertFalse(spoken.contains("word80"))
    }

    func testSavedDates() {
        XCTAssertEqual(SiriReadback.savedText(day(2026, 10, 12), now: now, calendar: calendar), "today")
        XCTAssertEqual(SiriReadback.savedText(day(2026, 10, 11), now: now, calendar: calendar), "yesterday")
        XCTAssertEqual(SiriReadback.savedText(day(2026, 1, 5), now: now, calendar: calendar), "on 5 January")
        XCTAssertEqual(SiriReadback.savedText(day(2025, 12, 31), now: now, calendar: calendar), "on 31 December 2025")
        XCTAssertEqual(SiriReadback.savedText(nil, now: now, calendar: calendar), "at an unknown time")
    }
}
