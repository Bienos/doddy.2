import XCTest
@testable import DoddyCore

/// ADR-652: the stopwatch by voice. Start and stop need a tap, reading asks "yes" first, and
/// Doddy says only what the clock says.
final class StopwatchVoiceTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    private func parse(_ name: String, _ json: String = "{}") -> VoiceToolRequest {
        VoiceToolRequest.parse(name: name, parametersJSON: Data(json.utf8))
    }

    func testTheThreeToolsParse() {
        XCTAssertEqual(parse("start_stopwatch"), .startStopwatch(label: nil))
        XCTAssertEqual(parse("start_stopwatch", #"{"label":"  Bieg\nwieczorny "}"#), .startStopwatch(label: "Bieg wieczorny"))
        XCTAssertEqual(parse("start_stopwatch", #"{"label":"   "}"#), .startStopwatch(label: nil))
        XCTAssertEqual(parse("stop_stopwatch"), .stopStopwatch)
        XCTAssertEqual(parse("check_stopwatch"), .checkStopwatch)
    }

    func testStartingAndStoppingNeedATapAndReadingAsksYes() throws {
        let start = AskFirst.need(for: .startStopwatch(label: "Bieg"))
        guard case .tapFirst(let card) = start else { return XCTFail("\(start)") }
        XCTAssertEqual(card.title, "Start a stopwatch?")
        XCTAssertEqual(card.lines, ["“Bieg”"], "the card shows exactly the label")
        XCTAssertTrue(AskFirst.needsTap(start))
        guard case .tapFirst(let plain) = AskFirst.need(for: .startStopwatch(label: nil)) else { return XCTFail() }
        XCTAssertEqual(plain.lines, ["It counts up until you stop it"])
        XCTAssertTrue(AskFirst.needsTap(AskFirst.need(for: .stopStopwatch)))
        let read = AskFirst.need(for: .checkStopwatch)
        guard case .yesFirst = read else { return XCTFail("\(read)") }
        XCTAssertFalse(AskFirst.needsTap(read), "a spoken yes is enough to read it")
    }

    func testTheCatalogAgreesWithTheCards() throws {
        for (name, effect, approval) in [
            (VoiceToolName.startStopwatch, ToolDescriptor.Effect.localChange, ToolDescriptor.Approval.card),
            (VoiceToolName.stopStopwatch, .localChange, .card),
            (VoiceToolName.checkStopwatch, .lookup, .askFirst),
        ] {
            let descriptor = try XCTUnwrap(ToolCatalog.descriptor(name), name)
            XCTAssertEqual(descriptor.effect, effect, name)
            XCTAssertEqual(descriptor.approval, approval, name)
        }
    }

    func testItIsDoddysOwnToolSoPauseAllAndTheSwitchesLeaveItAlone() {
        for request in [VoiceToolRequest.startStopwatch(label: nil), .stopStopwatch, .checkStopwatch] {
            XCTAssertFalse(ConnectionPause.applies(to: request), "\(request)")
        }
        XCTAssertNil(VoiceConnection.serving(VoiceToolName.startStopwatch))
    }

    func testInTheCarTheReadingIsAnsweredAndStartingWaitsForATap() {
        XCTAssertEqual(CarProfile.decision(for: .checkStopwatch), .run)
        for request in [VoiceToolRequest.startStopwatch(label: nil), .stopStopwatch] {
            guard case .refuse = CarProfile.decision(for: request) else { return XCTFail("\(request)") }
        }
    }

    func testTheRepliesAreClassifiedAndSayOnlyWhatIsTrue() {
        let started = VoiceToolReply.stopwatchStarted(label: "Bieg")
        XCTAssertTrue(started.hasPrefix("added: stopwatch started"))
        XCTAssertEqual(ActivityEntry.outcome(of: started, isLookup: false).0, .done)
        XCTAssertTrue(started.contains("<<<DATA"), "the label follows as data")
        XCTAssertFalse(VoiceToolReply.stopwatchStarted(label: nil).contains("DATA"))

        let again = VoiceToolReply.stopwatchAlreadyThere(elapsed: 727, paused: false)
        XCTAssertTrue(again.hasPrefix("failed:") && again.contains("12 minutes 7 seconds"))
        XCTAssertEqual(ActivityEntry.outcome(of: again, isLookup: false).0, .notDone)
        XCTAssertTrue(VoiceToolReply.stopwatchAlreadyThere(elapsed: 5, paused: true).contains("paused"))

        let stopped = VoiceToolReply.stopwatchStopped(elapsed: 3_727)
        XCTAssertTrue(stopped.hasPrefix("changed: stopwatch stopped at 1 hour 2 minutes 7 seconds"))
        XCTAssertEqual(ActivityEntry.outcome(of: stopped, isLookup: false).0, .done)

        XCTAssertTrue(VoiceToolReply.noStopwatchToStop(stoppedAt: nil).hasPrefix("failed:"))
        XCTAssertTrue(VoiceToolReply.noStopwatchToStop(stoppedAt: 61).contains("1 minute 1 second"))
    }

    func testTheReadingComesFromTheStopwatchNeverFromAGuess() {
        XCTAssertTrue(VoiceToolReply.stopwatchReading(nil, now: t0).contains("Never guess"))
        var watch = Stopwatch(label: nil, now: t0)
        XCTAssertEqual(VoiceToolReply.stopwatchReading(watch, now: t0.addingTimeInterval(727)), "The stopwatch is running: 12 minutes 7 seconds so far.")
        watch.pause(at: t0.addingTimeInterval(60))
        XCTAssertEqual(VoiceToolReply.stopwatchReading(watch, now: t0.addingTimeInterval(9_999)), "The stopwatch is paused at 1 minute.")
        watch.resume(at: t0.addingTimeInterval(100))
        watch.stop(at: t0.addingTimeInterval(130))
        XCTAssertEqual(VoiceToolReply.stopwatchReading(watch, now: t0.addingTimeInterval(9_999)), "The stopwatch is stopped at 1 minute 30 seconds.")
    }

    func testTheActivityRowIsWrittenInPolishToo() throws {
        let row = try XCTUnwrap(ActivityRequest.describe(.startStopwatch(label: "Bieg"), calendar: .current))
        XCTAssertEqual(row.title, "Start stopwatch")
        XCTAssertEqual(row.detail, "“Bieg”")
        XCTAssertEqual(row.app, .timers)
        XCTAssertFalse(row.isLookup)
        XCTAssertEqual(ActivityText.title("Start stopwatch", .polish), "Włącz stoper")
        XCTAssertTrue(try XCTUnwrap(ActivityRequest.describe(.checkStopwatch, calendar: .current)).isLookup)
    }
}
