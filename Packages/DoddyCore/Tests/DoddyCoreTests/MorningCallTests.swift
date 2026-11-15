import Foundation
import XCTest
@testable import DoddyCore

/// Morning calls (decision 2026-11-14-morning-call): the request the agent makes, the approval the card makes, the
/// tiers, and what the agent hears. The server's half is `server/messaging/test/morningCalls.test.ts`.
final class MorningCallTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private var warsaw: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func parse(_ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: VoiceToolName.callMeEveryMorning, parametersJSON: Data(json.utf8), calendar: warsaw)
    }

    // MARK: Parsing

    func testTheAgentGivesATimeAndTheDaysAndTheIPhonesZoneIsKept() {
        guard case .callMeEveryMorning(let draft) = parse(#"{"time": "08:00"}"#) else { return XCTFail("parsed") }
        XCTAssertEqual(draft, MorningCallDraft(time: "08:00", days: .everyDay, timeZoneID: "Europe/Warsaw"), "every day when no days are given")
        guard case .callMeEveryMorning(let weekdays) = parse(#"{"time": "07:30", "days": "weekdays"}"#) else { return XCTFail("weekdays") }
        XCTAssertEqual(weekdays.days.digits, "12345")
        guard case .callMeEveryMorning(let some) = parse(#"{"time": "09:15", "days": "fri, mon,Wednesday"}"#) else { return XCTFail("names") }
        XCTAssertEqual(some.days.digits, "135", "in order, whatever order they were said in")
        XCTAssertEqual(VoiceToolRequest.parse(name: VoiceToolName.stopMorningCalls, parametersJSON: Data("{}".utf8)), .stopMorningCalls)
    }

    func testOnlyAMorningTimeAndRealDaysAreAccepted() {
        guard case .invalid = parse("{}") else { return XCTFail("a time is needed") }
        for time in ["8", "8:00", "08.00", "8am", "08:00:00", "25:00"] {
            guard case .invalid = parse(#"{"time": "\#(time)"}"#) else { return XCTFail("\(time) is not HH:MM") }
        }
        for time in ["04:59", "12:00", "20:00", "00:00"] {
            guard case .needsClarification = parse(#"{"time": "\#(time)"}"#) else { return XCTFail("\(time) is not a morning") }
        }
        for time in ["05:00", "11:59"] {
            guard case .callMeEveryMorning = parse(#"{"time": "\#(time)"}"#) else { return XCTFail("\(time) is a morning") }
        }
        for days in ["", "sometimes", "mon,funday", "8"] {
            guard case .invalid = parse(#"{"time": "08:00", "days": "\#(days)"}"#) else { return XCTFail("days \(days)") }
        }
        XCTAssertNil(MorningCallDays(digits: "21"))
        XCTAssertNil(MorningCallDays(digits: "11"))
        XCTAssertNil(MorningCallDays(digits: ""))
    }

    func testTheDaysReadAsWordsInBothLanguages() {
        XCTAssertEqual(MorningCallDays.everyDay.text(.polish), "codziennie")
        XCTAssertEqual(MorningCallDays.weekdays.text(.english), "on weekdays")
        XCTAssertEqual(MorningCallDays(digits: "135")!.text(.english), "on Mondays, Wednesdays and Fridays")
        XCTAssertEqual(MorningCallDays(digits: "135")!.text(.polish), "w poniedziałki, środy i piątki")
        XCTAssertEqual(MorningCallDays(digits: "24")!.text(.polish), "we wtorki i czwartki")
        let draft = MorningCallDraft(time: "08:00", days: .everyDay, timeZoneID: "Europe/Warsaw")
        XCTAssertEqual(draft.scheduleText(.polish), "codziennie o 08:00")
        XCTAssertEqual(draft.scheduleText(.english), "every day at 08:00")
    }

    // MARK: The approval

    private struct Vectors: Decodable {
        struct Vector: Decodable { let description: String; let fields: [String]; let sha256: String }
        let vectors: [Vector]
    }

    func testTheHashMatchesTheSharedVectorsTheServerAlsoChecks() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("contracts/phone/approval-vectors.json"))
        let morning = try JSONDecoder().decode(Vectors.self, from: data).vectors.filter { $0.fields[1] == "morning_call" }
        XCTAssertGreaterThanOrEqual(morning.count, 3)
        for vector in morning {
            let f = vector.fields
            XCTAssertEqual(ApprovalHash.morningCall(to: f[2], time: f[3], days: f[4], zone: f[5], allowQuietHours: f[6] == "1", language: f[7]),
                           vector.sha256, vector.description)
        }
    }

    func testEveryFieldTheCardShowsIsBound() {
        let to = "+48500100200"
        let draft = MorningCallDraft(time: "08:00", days: .everyDay, timeZoneID: "Europe/Warsaw")
        let approved = draft.approvalHash(to: to, allowQuietHours: false, language: .polish)
        XCTAssertEqual(approved, "c47819f157ecb5527bd7c714a5415ad1588e409592692b5d1ad5c3a43532f3b4", "the first shared vector")
        let changed = [
            draft.approvalHash(to: "+48500100201", allowQuietHours: false, language: .polish),
            MorningCallDraft(time: "08:01", days: .everyDay, timeZoneID: "Europe/Warsaw").approvalHash(to: to, allowQuietHours: false, language: .polish),
            MorningCallDraft(time: "08:00", days: .weekdays, timeZoneID: "Europe/Warsaw").approvalHash(to: to, allowQuietHours: false, language: .polish),
            MorningCallDraft(time: "08:00", days: .everyDay, timeZoneID: "Europe/London").approvalHash(to: to, allowQuietHours: false, language: .polish),
            draft.approvalHash(to: to, allowQuietHours: true, language: .polish),
            draft.approvalHash(to: to, allowQuietHours: false, language: .english),
        ]
        XCTAssertEqual(Set(changed).count, changed.count)
        XCTAssertFalse(changed.contains(approved), "a changed field is a new approval")
        // A morning call's hash can never pass for a one-off call's.
        XCTAssertNotEqual(approved, ApprovalHash.call(to: to, at: "08:00", reason: "1234567", allowQuietHours: false))
    }

    func testQuietHoursAreATimeOfDay() {
        let quiet = CallQuietHours.standard
        XCTAssertTrue(MorningCallDraft(time: "07:59", days: .everyDay, timeZoneID: "Europe/Warsaw").inQuietHours(quiet))
        XCTAssertTrue(MorningCallDraft(time: "05:00", days: .everyDay, timeZoneID: "Europe/Warsaw").inQuietHours(quiet))
        XCTAssertFalse(MorningCallDraft(time: "08:00", days: .everyDay, timeZoneID: "Europe/Warsaw").inQuietHours(quiet), "quiet hours end at 08:00")
        XCTAssertFalse(MorningCallDraft(time: "07:00", days: .everyDay, timeZoneID: "Europe/Warsaw")
            .inQuietHours(CallQuietHours(start: "23:00", end: "06:30")))
    }

    // MARK: How it asks

    func testSettingUpShowsACardAYesAnswersAndStoppingRunsAtOnce() {
        let draft = MorningCallDraft(time: "08:00", days: .everyDay, timeZoneID: "Europe/Warsaw")
        XCTAssertEqual(AskFirst.need(for: .callMeEveryMorning(draft)), .ownPayloadCard)
        XCTAssertEqual(ConfirmationTiers.tier(for: VoiceToolName.callMeEveryMorning), .spokenYes, "the same as call_me_later")
        XCTAssertEqual(ConfirmationTiers.tier(for: VoiceToolName.callMeEveryMorning, outsideContentSeen: true), .tapOnly)
        XCTAssertEqual(ToolCatalog.descriptor(VoiceToolName.callMeEveryMorning)?.approval, .card)
        XCTAssertEqual(AskFirst.need(for: .stopMorningCalls), .runsNow)
        XCTAssertTrue(AskFirst.runsAtOnce(VoiceToolName.stopMorningCalls))
        XCTAssertEqual(ConfirmationTiers.specAsk(for: VoiceToolName.stopMorningCalls), .runsNow)
        // Not while driving and not while connections are paused, as call_me_later; stopping is never held back.
        guard case .refuse = CarProfile.decision(for: .callMeEveryMorning(draft)) else { return XCTFail("waits while driving") }
        XCTAssertEqual(CarProfile.decision(for: .stopMorningCalls), .run)
        XCTAssertTrue(ConnectionPause.applies(to: .callMeEveryMorning(draft)))
        XCTAssertFalse(ConnectionPause.applies(to: .stopMorningCalls))
        XCTAssertTrue(Feature.phoneCalls.tools.contains(VoiceToolName.callMeEveryMorning))
        XCTAssertTrue(Feature.phoneCalls.tools.contains(VoiceToolName.stopMorningCalls))
    }

    // MARK: What the agent hears, and the log

    func testTheRepliesNeverSayCalledAndTheLogKeepsTheScheduleOnly() {
        let draft = MorningCallDraft(time: "08:00", days: .weekdays, timeZoneID: "Europe/Warsaw")
        let booked = VoiceToolReply.morningCallBooked(draft, next: nil, calendar: warsaw)
        XCTAssertTrue(booked.hasPrefix("booked: Doddy's server will call the user's number on weekdays at 08:00"))
        XCTAssertTrue(booked.contains("can't see their calendar or reminders"))
        XCTAssertEqual(ActivityEntry.outcome(of: booked, isLookup: false).0, .done)
        XCTAssertEqual(ActivityEntry.outcome(of: VoiceToolReply.morningCallUnknown, isLookup: false).0, .notSure)
        XCTAssertEqual(ActivityEntry.outcome(of: VoiceToolReply.morningCallsStopped(calling: false), isLookup: false).0, .done)
        XCTAssertEqual(ActivityEntry.outcome(of: VoiceToolReply.noMorningCalls, isLookup: false).0, .notDone)
        XCTAssertEqual(ActivityEntry.outcome(of: VoiceToolReply.morningStopUnknown, isLookup: false).0, .notSure)
        XCTAssertTrue(VoiceToolReply.morningCallsStopped(calling: true).contains("may still ring this once"))
        XCTAssertTrue(VoiceToolReply.morningCallRefused("quiet_hours").hasPrefix("failed: that time is inside quiet hours (21:00 to 08:00)"))
        XCTAssertTrue(VoiceToolReply.morningCallRefused("server_limit", mayBeBooked: true).contains("may already be set up"))
        for reply in [booked, VoiceToolReply.morningCallUnknown, VoiceToolReply.morningCallsStopped(calling: false)] {
            XCTAssertFalse(reply.contains("Doddy called"), reply)
        }
        let row = ActivityRequest.describe(.callMeEveryMorning(draft), calendar: warsaw)
        XCTAssertEqual(row?.title, "Call you every morning from Doddy's number")
        XCTAssertEqual(row?.logDetail, "on weekdays at 08:00")
        XCTAssertEqual(ActivityText.title("Call you every morning from Doddy's number", .polish), "Telefon do Ciebie co rano z numeru Doddy’ego")
        XCTAssertEqual(ActivityRequest.describe(.stopMorningCalls, calendar: warsaw)?.title, "Stop the morning calls from Doddy's number")
    }

    func testTheCardSaysWhatTheCallKnowsAndWhatItDoesnt() {
        XCTAssertTrue(MorningCallDraft.covers(.english).contains("can't see your calendar or reminders"))
        XCTAssertTrue(MorningCallDraft.covers(.polish).contains("Kalendarza i przypomnień serwer Doddy’ego nie zna"))
        // The server's own first words (server/messaging/src/calls.ts callOpening, kind "morning").
        XCTAssertEqual(MorningCallDraft.opening(.polish), "Dzień dobry, tu Doddy, asystent AI, z Twoim planem dnia.")
        XCTAssertEqual(MorningCallDraft.opening(.english), "Good morning, this is Doddy, an AI assistant, with your plan for the day.")
    }

    func testTheLimitsMatchTheRulesFile() throws {
        let rules = try String(contentsOf: repoRoot.appendingPathComponent("docs/trust/config/doddy_rules.yaml"), encoding: .utf8)
        for line in [
            "morning_call_earliest: \"\(MorningCallLimits.earliest)\"", "morning_call_latest: \"\(MorningCallLimits.latest)\"",
            "morning_calls_per_account: \(MorningCallLimits.perAccount)",
            "morning_calls_per_server_default: \(MorningCallLimits.perServerDefault)",
        ] {
            XCTAssertTrue(rules.contains(line), line)
        }
    }

    // MARK: The server's answers

    func testTheServersAnswersAreRead() throws {
        let status = try JSONDecoder().decode(MorningCallStatus.self, from: Data("""
            {"enabled": true, "available": true, "call": {"id": "6f1c2a3b-0000-4000-8000-000000000001", "time": "08:00", "days": "12345",
             "timeZone": "Europe/Warsaw", "allowQuietHours": false, "language": "pl", "state": "active", "stopCode": null,
             "nextCallAt": "2026-11-16T07:00:00.000Z", "createdAt": "2026-11-15T10:00:00.000Z"},
             "recent": [{"at": "2026-11-14T07:00:00Z", "state": "placed", "errorCode": null}]}
            """.utf8))
        XCTAssertEqual(status.call?.dayList, .weekdays)
        XCTAssertNotNil(status.call?.nextDate)
        XCTAssertEqual(status.recent.first?.state, "placed")
        let none = try JSONDecoder().decode(MorningCallStatus.self, from: Data(#"{"enabled": false, "available": false, "call": null, "recent": []}"#.utf8))
        XCTAssertNil(none.call)
    }
}
