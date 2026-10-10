import XCTest
@testable import DoddyCore

/// The plan card (ADR-204): every step is checked as if it had been asked on its own, and the
/// agent hears one result per step.
final class PlanTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))! }

    private func parse(_ steps: Any) -> PlanParse {
        let data = try! JSONSerialization.data(withJSONObject: ["steps": steps])
        return PlanProposal.parse(parametersJSON: data, now: now, calendar: calendar)
    }

    private func steps(_ result: PlanParse, file: StaticString = #filePath, line: UInt = #line) -> [PlanStep] {
        guard case .plan(let steps) = result else {
            XCTFail("expected a plan, got \(result)", file: file, line: line)
            return []
        }
        return steps
    }

    private func refusal(_ result: PlanParse, file: StaticString = #filePath, line: UInt = #line) -> String {
        guard case .refused(let text) = result else {
            XCTFail("expected a refusal, got \(result)", file: file, line: line)
            return ""
        }
        return text
    }

    private let saturdayAtMoms = #"[{"tool":"create_reminder","title":"Bring the spare key and an umbrella","due":"2026-10-17T12:00"},{"tool":"create_calendar_event","title":"Mom's","start":"2026-10-17T14:00"}]"#

    func testStepsSentAsAJSONStringAreParsedInOrder() {
        let parsed = steps(parse(saturdayAtMoms))
        XCTAssertEqual(parsed.map(\.number), [1, 2])
        XCTAssertEqual(parsed.map(\.toolName), [VoiceToolName.createReminder, VoiceToolName.createCalendarEvent])
        XCTAssertEqual(parsed.map(\.connection), [.reminders, .calendar])
        guard case .createReminder(let draft) = parsed[0].request else { return XCTFail("not a reminder") }
        XCTAssertEqual(draft.title, "Bring the spare key and an umbrella")
        XCTAssertEqual(draft.due?.hour, 12)
        XCTAssertEqual(parsed[1].activity(calendar: calendar)?.title, "Add event")
    }

    func testARealArrayIsAcceptedToo() {
        let parsed = steps(parse([["tool": "set_timer", "minutes": 10, "label": "pasta"], ["tool": "save_memory", "text": "Pasta takes 10 minutes"]]))
        XCTAssertEqual(parsed.count, 2)
        XCTAssertNil(parsed[1].connection, "notes are always on")
    }

    func testAnUnclearTimeRefusesTheWholePlanWithTheQuestion() {
        // 09:00 today has passed at noon: the agent must ask, and no other step runs meanwhile.
        let text = refusal(parse(#"[{"tool":"save_memory","text":"Key in the blue tin"},{"tool":"create_reminder","title":"Take the key","due":"2026-10-10T09:00"}]"#))
        XCTAssertTrue(text.hasPrefix("failed: not added yet: step 2 (create_reminder)"), text)
        XCTAssertTrue(text.contains("call propose_plan again"), text)
        XCTAssertTrue(text.hasSuffix("Nothing was done."), text)
    }

    func testToolsThatLeaveDoddyOrNeedTheServerAreNotSteps() {
        for tool in [VoiceToolName.openMap, VoiceToolName.draftMessage, VoiceToolName.runShortcut, "draft_email", "add_todoist_task", VoiceToolName.proposePlan] {
            let text = refusal(parse([["tool": tool, "place": "Hala Koszyki"]]))
            XCTAssertTrue(text.contains("step 1 (\(tool)) can't be part of a plan"), text)
        }
    }

    func testBrokenPlansAreRefusedNotGuessed() {
        XCTAssertTrue(refusal(parse("not json")).contains("steps must be a JSON array"))
        XCTAssertTrue(refusal(parse([Any]())).contains("no steps"))
        XCTAssertTrue(refusal(parse([["title": "no tool"]])).contains("step 1 of the plan has no tool"))
        XCTAssertTrue(refusal(parse([["tool": "create_reminder"]])).contains("step 1 (create_reminder) was incomplete (missing title)"))
        let six = Array(repeating: ["tool": "save_memory", "text": "x"], count: 6)
        XCTAssertTrue(refusal(parse(six)).contains("at most 5 steps"))
        XCTAssertTrue(refusal(PlanProposal.parse(parametersJSON: Data("{}".utf8))).contains("steps must be a JSON array"))
    }

    func testTheButtonCountsWhatWillHappen() {
        let reminder = PlanStep(number: 1, toolName: VoiceToolName.createReminder, request: .createReminder(ReminderDraft(title: "a", due: nil, notes: nil)))
        let note = PlanStep(number: 2, toolName: VoiceToolName.saveMemory, request: .saveMemory(text: "b"))
        XCTAssertEqual(PlanProposal.confirmTitle([reminder]), "Add 1 reminder")
        XCTAssertEqual(PlanProposal.confirmTitle([reminder, reminder]), "Add 2 reminders")
        XCTAssertEqual(PlanProposal.confirmTitle([note]), "Save 1 note")
        XCTAssertEqual(PlanProposal.confirmTitle([reminder, note]), "Do 2 things")
        XCTAssertEqual(PlanProposal.confirmTitle([]), "Nothing ticked")
    }

    func testTheReplyKeepsEachStepsOwnResult() {
        let parsed = steps(parse(saturdayAtMoms))
        let reply = PlanReply.summary([
            (parsed[0], VoiceToolReply.addUnconfirmed),
            (parsed[1], PlanReply.unticked),
        ])
        let lines = reply.components(separatedBy: "\n")
        XCTAssertTrue(lines[0].hasPrefix("plan:"))
        XCTAssertTrue(lines[1].hasPrefix("1. unknown:"), lines[1])
        XCTAssertEqual(lines[2], "2. \(PlanReply.unticked)")
    }

    func testEachStepIsLoggedWithItsOwnOutcome() {
        let parsed = steps(parse(saturdayAtMoms))
        let plan = UUID()
        func logged(_ step: PlanStep, _ reply: String) -> ActivityEntry {
            ActivityEntry(request: step.activity(calendar: calendar)!, reply: reply, at: now, plan: ActivityPlanRef(id: plan, step: step.number, count: 2))
        }
        XCTAssertEqual(logged(parsed[0], PlanBlock.paused.reply).outcome, .notDone)
        XCTAssertEqual(logged(parsed[0], PlanBlock.notConnected(.reminders).reply).note, "Reminders isn't connected.")
        XCTAssertEqual(logged(parsed[1], PlanReply.unticked).outcome, .declined)
        XCTAssertEqual(logged(parsed[1], PlanReply.unticked).plan?.text, "Step 2 of 2 in one plan")
    }

    func testOlderActivityFilesWithoutPlansStillLoad() throws {
        let old = ActivityEntry(at: now, app: .reminders, title: "Add reminder", detail: nil, outcome: .done)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json["plan"] = nil
        let decoded = try JSONDecoder().decode(ActivityEntry.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.plan)
        XCTAssertEqual(decoded.outcome, .done)
    }
}
