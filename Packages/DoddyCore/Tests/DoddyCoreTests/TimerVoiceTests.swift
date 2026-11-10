import XCTest
@testable import DoddyCore

/// Decision 2026-11-10-timers-by-voice: the focus timer and the wind-down start, stop and (focus) read by voice.
/// Start and stop need a tap on a card that shows the exact length; reading asks "yes" first; and Doddy says only
/// what the session the app read back says.
final class TimerVoiceTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_792_000_000)
    private let names = [VoiceToolName.startFocus, VoiceToolName.stopFocus, VoiceToolName.checkFocus,
                         VoiceToolName.startWindDown, VoiceToolName.stopWindDown]

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }

    private func parse(_ name: String, _ json: String = "{}") -> VoiceToolRequest {
        VoiceToolRequest.parse(name: name, parametersJSON: Data(json.utf8))
    }

    // MARK: Parsing

    func testTheFiveToolsParse() {
        XCTAssertEqual(parse("start_focus"), .startFocus(minutes: 25, label: nil), "no length: the focus screen's 25")
        XCTAssertEqual(parse("start_focus", #"{"minutes":45,"label":"  Raport\nkwartalny "}"#), .startFocus(minutes: 45, label: "Raport kwartalny"))
        XCTAssertEqual(parse("start_focus", #"{"minutes":null,"label":"   "}"#), .startFocus(minutes: 25, label: nil), "null is left out")
        XCTAssertEqual(parse("start_focus", #"{"minutes":12.6}"#), .startFocus(minutes: 13, label: nil), "whole minutes")
        XCTAssertEqual(parse("stop_focus"), .stopFocus)
        XCTAssertEqual(parse("check_focus"), .checkFocus)
        XCTAssertEqual(parse("start_wind_down"), .startWindDown(minutes: 10), "no length: the wind-down screen's 10")
        XCTAssertEqual(parse("start_wind_down", #"{"minutes":20}"#), .startWindDown(minutes: 20))
        XCTAssertEqual(parse("stop_wind_down"), .stopWindDown)
    }

    func testALengthOutOfRangeOrNotANumberIsRefusedNotShifted() {
        let focus = VoiceToolRequest.invalid(name: "start_focus", reason: "minutes must be a number from 1 to 180")
        XCTAssertEqual(parse("start_focus", #"{"minutes":0}"#), focus)
        XCTAssertEqual(parse("start_focus", #"{"minutes":0.4}"#), focus, "rounds to 0")
        XCTAssertEqual(parse("start_focus", #"{"minutes":-5}"#), focus)
        XCTAssertEqual(parse("start_focus", #"{"minutes":181}"#), focus)
        XCTAssertEqual(parse("start_focus", #"{"minutes":"25"}"#), focus, "a string is not taken as 25 by chance")
        // Review C6: a value no Int can hold is refused, not a crash.
        XCTAssertEqual(parse("start_focus", #"{"minutes":1e300}"#), focus)
        let windDown = VoiceToolRequest.invalid(name: "start_wind_down", reason: "minutes must be a number from 1 to 60")
        XCTAssertEqual(parse("start_wind_down", #"{"minutes":61}"#), windDown)
        XCTAssertEqual(parse("start_wind_down", #"{"minutes":0}"#), windDown)
        // Review C11: a label is a line, not a page; too long is refused before it is cut to the Lock Screen's 60.
        XCTAssertEqual(parse("start_focus", "{\"label\":\"\(String(repeating: "a", count: 201))\"}"),
                       .invalid(name: "start_focus", reason: "label is longer than 200 characters"))
        guard case .startFocus(_, let label) = parse("start_focus", "{\"label\":\"\(String(repeating: "b", count: 90))\"}") else {
            return XCTFail()
        }
        XCTAssertEqual(label?.count, FocusSession.maxLabelLength, "the card shows the line exactly as the Lock Screen will")
    }

    // MARK: Asking first

    func testStartingAndStoppingNeedATapAndReadingAsksYes() throws {
        guard case .tapFirst(let card) = AskFirst.need(for: .startFocus(minutes: 45, label: "Raport")) else { return XCTFail() }
        XCTAssertEqual(card.title, "Start focus?")
        XCTAssertEqual(card.lines, ["45 min", "“Raport”"], "the card shows exactly the length and the line")
        XCTAssertEqual(card.confirmLabel, "Start")
        guard case .tapFirst(let plain) = AskFirst.need(for: .startFocus(minutes: 25, label: nil)) else { return XCTFail() }
        XCTAssertEqual(plain.lines, ["25 min"])
        guard case .tapFirst(let windDown) = AskFirst.need(for: .startWindDown(minutes: 15), polish: true) else { return XCTFail() }
        XCTAssertEqual(windDown.title, "Włączyć wyciszenie przed snem?")
        XCTAssertEqual(windDown.lines, ["15 min, potem pora odłożyć telefon"])
        for request in [VoiceToolRequest.startFocus(minutes: 25, label: nil), .stopFocus, .startWindDown(minutes: 10), .stopWindDown] {
            XCTAssertTrue(AskFirst.needsTap(AskFirst.need(for: request)), "\(request): a change needs a tap, not a spoken yes")
        }
        let read = AskFirst.need(for: .checkFocus)
        guard case .yesFirst = read else { return XCTFail("\(read)") }
        XCTAssertFalse(AskFirst.needsTap(read), "a spoken yes is enough to read it")
    }

    func testTheCatalogAgreesWithTheCards() throws {
        for (name, effect, approval) in [
            (VoiceToolName.startFocus, ToolDescriptor.Effect.localChange, ToolDescriptor.Approval.card),
            (VoiceToolName.stopFocus, .localChange, .card),
            (VoiceToolName.checkFocus, .lookup, .askFirst),
            (VoiceToolName.startWindDown, .localChange, .card),
            (VoiceToolName.stopWindDown, .localChange, .card),
        ] {
            let descriptor = try XCTUnwrap(ToolCatalog.descriptor(name), name)
            XCTAssertEqual(descriptor.effect, effect, name)
            XCTAssertEqual(descriptor.approval, approval, name)
            XCTAssertEqual(descriptor.runsOn, .phone, name)
        }
    }

    // MARK: Where they run

    func testTheyAreCoreSoEveryScopeKeepsThem() {
        for name in names {
            XCTAssertTrue(ReleaseScope.coreTools.contains(name), name)
            XCTAssertNil(ReleaseScope.shipping.hiddenFeature(forTool: name), "\(name) runs in every scope")
            XCTAssertFalse(ReleaseScope.shipping.hiddenTools.contains(name), name)
        }
    }

    func testItIsDoddysOwnToolSoPauseAllAndTheSwitchesLeaveItAlone() {
        for request in [VoiceToolRequest.startFocus(minutes: 25, label: nil), .stopFocus, .checkFocus, .startWindDown(minutes: 10), .stopWindDown] {
            XCTAssertFalse(ConnectionPause.applies(to: request), "\(request)")
        }
        for name in names { XCTAssertNil(VoiceConnection.serving(name), name) }
    }

    func testInTheCarTheReadingIsAnsweredAndStartingWaitsForATap() {
        XCTAssertEqual(CarProfile.decision(for: .checkFocus), .run)
        for request in [VoiceToolRequest.startFocus(minutes: 25, label: nil), .stopFocus, .startWindDown(minutes: 10), .stopWindDown] {
            guard case .refuse = CarProfile.decision(for: request) else { return XCTFail("\(request)") }
        }
    }

    // MARK: Replies from the session read back

    func testStartedIsSaidOnlyForARunningSession() {
        let focus = FocusSession(minutes: 25, label: "Raport", now: t0)
        let said = VoiceToolReply.countdownStarted(.focus, focus, alertConfirmed: true, calendar: calendar)
        XCTAssertTrue(said.hasPrefix("added: focus timer started, 25 minutes, ends at 2026-10-14 20:11."), said)
        XCTAssertTrue(said.contains("A notification comes when it ends."))
        XCTAssertTrue(said.contains("<<<DATA"), "the label follows as data")
        XCTAssertEqual(ActivityEntry.outcome(of: said, isLookup: false).0, .done)

        let unconfirmed = VoiceToolReply.countdownStarted(.windDown, CountdownSession(seconds: 600, purpose: .windDown, label: nil, now: t0),
                                                          alertConfirmed: false, calendar: calendar)
        XCTAssertTrue(unconfirmed.hasPrefix("added: wind-down started, 10 minutes"), unconfirmed)
        XCTAssertTrue(unconfirmed.contains("may be no alert"), "never promise a notification iOS didn't confirm")
        XCTAssertFalse(unconfirmed.contains("DATA"))

        // Nothing read back, or a session that isn't running: never "added".
        var stopped = FocusSession(minutes: 25, label: nil, now: t0)
        stopped.stop(at: t0.addingTimeInterval(60))
        for session in [nil, stopped] as [FocusSession?] {
            let reply = VoiceToolReply.countdownStarted(.focus, session, alertConfirmed: true, calendar: calendar)
            XCTAssertTrue(reply.hasPrefix("failed:"), reply)
            XCTAssertEqual(ActivityEntry.outcome(of: reply, isLookup: false).0, .notDone)
        }
    }

    func testOneAtATimeTheRunningOneIsNeverReplaced() {
        var focus = FocusSession(minutes: 25, label: nil, now: t0)
        let again = VoiceToolReply.countdownAlreadyThere(.focus, focus, now: t0.addingTimeInterval(60))
        XCTAssertEqual(again, "failed: a focus timer is already running with 24 minutes left. Nothing was started. Tell the user; for a new one, they stop this one first.")
        focus.pause(at: t0.addingTimeInterval(90))
        XCTAssertTrue(VoiceToolReply.countdownAlreadyThere(.focus, focus, now: t0.addingTimeInterval(999)).contains("paused with 23 minutes 30 seconds left"))
    }

    func testStoppedIsSaidOnlyWhenTheSessionReadsStopped() {
        let before = FocusSession(minutes: 25, label: nil, now: t0)
        var after = before
        after.stop(at: t0.addingTimeInterval(300))
        let said = VoiceToolReply.countdownStopped(.focus, before: before, after: after, now: t0.addingTimeInterval(300))
        XCTAssertEqual(said, "changed: focus timer stopped with 20 minutes left. Tell the user.")
        XCTAssertEqual(ActivityEntry.outcome(of: said, isLookup: false).0, .done)

        // Nothing to stop, or already over: nothing changed.
        XCTAssertTrue(VoiceToolReply.countdownStopped(.windDown, before: nil, after: nil, now: t0).hasPrefix("failed: there is no wind-down running"))
        XCTAssertTrue(VoiceToolReply.countdownStopped(.focus, before: after, after: after, now: t0).hasPrefix("failed: the focus timer was already stopped"))
        var ranOut = before
        ranOut.finishIfDue(at: t0.addingTimeInterval(25 * 60))
        XCTAssertTrue(VoiceToolReply.countdownStopped(.focus, before: ranOut, after: ranOut, now: t0).hasPrefix("failed: the focus timer had already ended"))
        // The time ran out between the card and the tap: stopping found it finished, not stopped.
        var lateStop = before
        lateStop.stop(at: t0.addingTimeInterval(26 * 60))
        XCTAssertTrue(VoiceToolReply.countdownStopped(.focus, before: before, after: lateStop, now: t0.addingTimeInterval(26 * 60))
            .hasPrefix("failed: the focus timer's time had already run out"))
        // Read back still running: never "changed".
        let stuck = VoiceToolReply.countdownStopped(.focus, before: before, after: before, now: t0)
        XCTAssertTrue(stuck.hasPrefix("failed:") && stuck.contains("may not have stopped"), stuck)
    }

    func testTheReadingComesFromTheSessionNeverFromAGuess() {
        XCTAssertTrue(VoiceToolReply.focusReading(nil, now: t0, calendar: calendar).contains("Never guess"))
        var focus = FocusSession(minutes: 25, label: nil, now: t0)
        let running = VoiceToolReply.focusReading(focus, now: t0.addingTimeInterval(727), calendar: calendar)
        XCTAssertTrue(running.hasPrefix("The focus timer is running: 12 minutes 53 seconds left, it ends at 2026-10-14 20:11."), running)
        // Past its end but not yet noticed by the app: over, never a negative or a zero "left".
        XCTAssertEqual(VoiceToolReply.focusReading(focus, now: t0.addingTimeInterval(26 * 60), calendar: calendar), "The focus timer is over: its time is up.")
        focus.pause(at: t0.addingTimeInterval(60))
        XCTAssertEqual(VoiceToolReply.focusReading(focus, now: t0.addingTimeInterval(9_999), calendar: calendar), "The focus timer is paused with 24 minutes left.")
        focus.resume(at: t0.addingTimeInterval(100))
        focus.stop(at: t0.addingTimeInterval(130))
        XCTAssertEqual(VoiceToolReply.focusReading(focus, now: t0.addingTimeInterval(9_999), calendar: calendar),
                       "The focus timer is stopped: it was stopped before its time was up.")
        let labelled = VoiceToolReply.focusReading(FocusSession(minutes: 5, label: "Raport", now: t0), now: t0, calendar: calendar)
        XCTAssertTrue(labelled.contains("<<<DATA"), "the user's line follows as data")
    }

    // MARK: What Doddy did

    func testTheActivityRowsAreWrittenInPolishToo() throws {
        let row = try XCTUnwrap(ActivityRequest.describe(.startFocus(minutes: 25, label: "Raport"), calendar: calendar))
        XCTAssertEqual(row.title, "Start focus")
        XCTAssertEqual(row.detail, "25 min · “Raport”")
        XCTAssertEqual(row.app, .timers)
        XCTAssertFalse(row.isLookup)
        XCTAssertEqual(try XCTUnwrap(ActivityRequest.describe(.startWindDown(minutes: 10), calendar: calendar)).detail, "10 min")
        XCTAssertTrue(try XCTUnwrap(ActivityRequest.describe(.checkFocus, calendar: calendar)).isLookup)
        for (english, polish) in [("Start focus", "Włącz skupienie"), ("Stop focus", "Zatrzymaj skupienie"), ("Read focus", "Odczytano skupienie"),
                                  ("Start wind-down", "Włącz wyciszenie"), ("Stop wind-down", "Zatrzymaj wyciszenie")] {
            XCTAssertEqual(ActivityText.title(english, .polish), polish)
        }
    }

    // MARK: What I can do

    func testWhatICanDoSaysTheyStartByVoice() {
        let english = WhatICanDo.text(.reminders, .english)
        XCTAssertEqual(english.title, "Reminders, calendar and timers")
        XCTAssertTrue(english.does.contains("Focus, the stopwatch and a wind-down"))
        let polish = WhatICanDo.text(.reminders, .polish)
        XCTAssertEqual(polish.title, "Przypomnienia, kalendarz i minutniki")
        XCTAssertTrue(polish.does.contains("skupienie, stoper i wyciszenie przed snem"))
    }
}
