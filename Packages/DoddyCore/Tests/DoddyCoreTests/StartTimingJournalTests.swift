@testable import DoddyCore
import XCTest

final class StartTimingJournalTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-11-14 13:05:41 UTC.
    private let noon = Date(timeIntervalSince1970: 1_794_920_741)

    private func line(opening: String = "talk start timing: ", rest: String = "island shown 0.03 s · total 0.40 s") -> String {
        opening + rest
    }

    // MARK: What is kept

    func testLinesAreKeptInOrderWithTheirTimes() {
        var journal = StartTimingJournal()
        XCTAssertTrue(journal.isEmpty)
        XCTAssertTrue(journal.record("talk start launch: process age 1.20 s (fresh launch)", at: noon))
        XCTAssertTrue(journal.record(line(), at: noon.addingTimeInterval(2)))
        XCTAssertEqual(journal.entries.map(\.text), ["talk start launch: process age 1.20 s (fresh launch)", line()])
        XCTAssertEqual(journal.entries.map(\.at), [noon, noon.addingTimeInterval(2)])
        XCTAssertFalse(journal.isEmpty)
    }

    func testTheOldestLinesGoWhenThereAreTooMany() {
        var journal = StartTimingJournal()
        for number in 0 ..< (StartTimingJournal.capacity + 5) {
            journal.record(line(rest: "total \(number).00 s"), at: noon.addingTimeInterval(Double(number)))
        }
        XCTAssertEqual(journal.entries.count, StartTimingJournal.capacity)
        XCTAssertEqual(journal.entries.first?.text, line(rest: "total 5.00 s"))
        XCTAssertEqual(journal.entries.last?.text, line(rest: "total \(StartTimingJournal.capacity + 4).00 s"))
    }

    // MARK: What is refused

    func testOnlyTheThreeFixedOpeningsAreKept() {
        var journal = StartTimingJournal()
        XCTAssertFalse(journal.record("hello 0.03 s", at: noon))
        XCTAssertFalse(journal.record("talk start: island shown 0.03 s", at: noon))
        XCTAssertFalse(journal.record(" talk start timing: total 0.40 s", at: noon))
        XCTAssertFalse(journal.record("", at: noon))
        XCTAssertTrue(journal.isEmpty)
        for opening in StartTimingJournal.openings {
            XCTAssertTrue(journal.record(opening + "total 0.40 s", at: noon), opening)
        }
        XCTAssertEqual(journal.entries.count, 3)
    }

    func testNothingThatCouldBeAPersonsIsKept() {
        var journal = StartTimingJournal()
        for rest in ["see https://example.com", "mail me@example.com", "he said \"hi\"", "a/b", "line\nbreak", "tab\there",
                     "name = Pat", "100%", "ąę", "emoji 😀", "<script>", "{}", "x_y", "a;b", "a'b"] {
            XCTAssertFalse(journal.record(line(rest: rest), at: noon), rest)
        }
        XCTAssertTrue(journal.isEmpty)
    }

    func testALineThatIsTooLongIsRefused() {
        var journal = StartTimingJournal()
        let room = StartTimingJournal.maxLineLength - "talk start timing: ".count
        XCTAssertTrue(journal.record(line(rest: String(repeating: "a", count: room)), at: noon))
        XCTAssertFalse(journal.record(line(rest: String(repeating: "a", count: room + 1)), at: noon))
        XCTAssertEqual(journal.entries.count, 1)
    }

    // MARK: The lines the app really writes are accepted

    func testEveryLineTheAppWritesIsAccepted() {
        var timeline = VoiceStartTimeline(startedAt: 0)
        timeline.mark(.islandShown, at: 0.04)
        timeline.mark(.account, at: 0.05)
        timeline.mark(.profile, at: 0.2)
        timeline.mark(.island, at: 0.5)
        timeline.mark(.connect, at: 2.4)
        var written = [
            "talk start timing: " + timeline.line(at: 2.5),
            "talk start launch: " + TalkLaunchTiming(processAge: 1.2, beforeAppInit: 0.6, appInit: 0.15).line(),
            "talk start launch: " + TalkLaunchTiming(processAge: 600, beforeAppInit: nil, appInit: nil).line(),
            "talk start launch: " + TalkLaunchTiming(processAge: nil, beforeAppInit: nil, appInit: nil).line(),
            "voice first audible sound after start: " + VoiceAudibleOnset.Result(sound: 2.84, listeningFrom: 2.79).line(outputLatency: 0.05),
            "voice first audible sound after start: " + VoiceAudibleOnset.Result(sound: 2.84, listeningFrom: 2.79).line(),
        ]
        for token in [VoiceTokenSource.shelf, .warming, .fetched] {
            written.append("talk start timing: " + timeline.line(at: 2.5, token: token))
        }
        var journal = StartTimingJournal()
        for text in written {
            XCTAssertTrue(StartTimingJournal.accepts(text), text)
            XCTAssertTrue(journal.record(text, at: noon), text)
        }
        XCTAssertEqual(journal.entries.count, written.count)
    }

    // MARK: Text to paste

    func testTheTextToPasteIsOneLinePerEntryWithTheTimeOfDay() {
        var journal = StartTimingJournal()
        XCTAssertEqual(journal.copyText(timeZone: utc), "")
        journal.record("talk start launch: process age 1.20 s (fresh launch)", at: noon)
        journal.record(line(), at: noon.addingTimeInterval(75))
        XCTAssertEqual(
            journal.copyText(timeZone: utc),
            "13:05:41  talk start launch: process age 1.20 s (fresh launch)\n13:06:56  " + line())
    }

    func testTheTimeOfDayFollowsTheTimeZoneGiven() {
        var journal = StartTimingJournal()
        journal.record(line(), at: noon)
        let warsaw = TimeZone(identifier: "Europe/Warsaw")!
        XCTAssertEqual(journal.copyText(timeZone: warsaw), "14:05:41  " + line())
    }

    // MARK: Storage

    func testWhatIsStoredReadsBackTheSame() throws {
        var journal = StartTimingJournal()
        journal.record("talk start launch: process age 1.20 s (fresh launch)", at: noon)
        journal.record(line(), at: noon.addingTimeInterval(2))
        let data = try XCTUnwrap(journal.encoded())
        XCTAssertEqual(StartTimingJournal.decode(data), journal)
    }

    func testNothingOrDamagedStorageIsAnEmptyJournal() {
        XCTAssertTrue(StartTimingJournal.decode(nil).isEmpty)
        XCTAssertTrue(StartTimingJournal.decode(Data()).isEmpty)
        XCTAssertTrue(StartTimingJournal.decode(Data("not json".utf8)).isEmpty)
        XCTAssertTrue(StartTimingJournal.decode(Data("{\"entries\":3}".utf8)).isEmpty)
    }

    func testAStoredLineThatIsNotOursIsDroppedWhenItIsRead() throws {
        // A value written by hand or by something else: only the lines that pass `accepts` come back.
        let stored = """
        {"entries":[{"at":0,"text":"talk start timing: total 0.40 s"},{"at":1,"text":"call me on 555 0100"},\
        {"at":2,"text":"talk start timing: see https://example.com"}]}
        """
        let journal = StartTimingJournal.decode(Data(stored.utf8))
        XCTAssertEqual(journal.entries.map(\.text), ["talk start timing: total 0.40 s"])
    }

    func testAStoredJournalLongerThanTheLimitIsCutOnRead() throws {
        let rows = (0 ..< 40).map { "{\"at\":\($0),\"text\":\"talk start timing: total \($0).00 s\"}" }.joined(separator: ",")
        let journal = StartTimingJournal.decode(Data("{\"entries\":[\(rows)]}".utf8))
        XCTAssertEqual(journal.entries.count, StartTimingJournal.capacity)
        XCTAssertEqual(journal.entries.last?.text, "talk start timing: total 39.00 s")
    }

    // MARK: Erase everything

    func testEraseEverythingRemovesTheJournalsPreference() {
        XCTAssertTrue(DevicePreferences.erasedKeys.contains("startTimingJournal"))
        XCTAssertNil(DevicePreferences.keptKeys["startTimingJournal"])
        for scope in DeviceErasureScope.allCases {
            XCTAssertEqual(DevicePreferences.rule(for: "startTimingJournal", scope: scope), .erase, scope.rawValue)
        }
    }
}
