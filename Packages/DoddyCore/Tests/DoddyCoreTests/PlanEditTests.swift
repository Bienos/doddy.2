import XCTest
@testable import DoddyCore

/// "Change" on a plan step (ADR-205): an edit goes through the same checks as the agent's call.
final class PlanEditTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private var now: Date { date(10, 12) }

    private func date(_ day: Int, _ hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func step(_ tool: String, _ args: [String: Any]) -> PlanStep {
        let data = try! JSONSerialization.data(withJSONObject: args)
        return PlanStep(number: 2, toolName: tool, request: VoiceToolRequest.parse(name: tool, parametersJSON: data, now: now, calendar: calendar))
    }

    private func edited(_ form: PlanStepForm, _ original: PlanStep) -> PlanStep? {
        guard case .step(let step) = form.apply(to: original, now: now, calendar: calendar) else { return nil }
        return step
    }

    func testAReminderFormStartsFromTheProposalAndKeepsItsNumber() throws {
        let original = step(VoiceToolName.createReminder, ["title": "Bring the key", "due": "2026-10-17T12:00"])
        var form = PlanStepForm(original, now: now, calendar: calendar)
        XCTAssertEqual(form.kind, .reminder)
        XCTAssertEqual(form.text, "Bring the key")
        XCTAssertTrue(form.hasDate)
        XCTAssertTrue(form.hasTime)
        XCTAssertEqual(form.start, date(17, 12))

        form.text = "Bring the key and an umbrella"
        form.start = date(17, 11, minute: 30)
        let changed = try XCTUnwrap(edited(form, original))
        XCTAssertEqual(changed.number, 2)
        guard case .createReminder(let draft) = changed.request else { return XCTFail("not a reminder") }
        XCTAssertEqual(draft.title, "Bring the key and an umbrella")
        XCTAssertEqual(draft.due?.hour, 11)
        XCTAssertEqual(draft.due?.minute, 30)
        XCTAssertEqual(draft.due?.timeZoneID, "Europe/Warsaw")
    }

    func testAReminderCanLoseItsTimeOrItsDate() throws {
        let original = step(VoiceToolName.createReminder, ["title": "Rent", "due": "2026-10-17T12:00"])
        var form = PlanStepForm(original, now: now, calendar: calendar)
        form.hasTime = false
        guard case .createReminder(let dayOnly) = try XCTUnwrap(edited(form, original)).request else { return XCTFail() }
        XCTAssertEqual(dayOnly.due?.day, 17)
        XCTAssertNil(dayOnly.due?.hour)
        form.hasDate = false
        guard case .createReminder(let undated) = try XCTUnwrap(edited(form, original)).request else { return XCTFail() }
        XCTAssertNil(undated.due)
    }

    func testAnEditKeepsTheYearOnABuddhistOrJapaneseCalendar() throws {
        for identifier in [Calendar.Identifier.buddhist, .japanese] {
            var local = Calendar(identifier: identifier)
            local.timeZone = calendar.timeZone
            let data = try JSONSerialization.data(withJSONObject: ["title": "Rent", "due": "2026-10-17T12:00"])
            let original = PlanStep(number: 2, toolName: VoiceToolName.createReminder,
                                    request: VoiceToolRequest.parse(name: VoiceToolName.createReminder, parametersJSON: data, now: now, calendar: local))
            var form = PlanStepForm(original, now: now, calendar: local)
            form.text = "Rent and water"
            guard case .step(let changed) = form.apply(to: original, now: now, calendar: local),
                  case .createReminder(let draft) = changed.request else { return XCTFail("\(identifier): edit refused") }
            XCTAssertEqual(draft.due?.year, 2026, "\(identifier)")
            XCTAssertEqual(draft.due?.day, 17, "\(identifier)")
        }
    }

    func testAnEditToAPastTimeIsRefusedWithAScreenLine() {
        let original = step(VoiceToolName.createReminder, ["title": "Rent", "due": "2026-10-17T12:00"])
        var form = PlanStepForm(original, now: now, calendar: calendar)
        form.start = date(10, 9)
        guard case .problem(let text) = form.apply(to: original, now: now, calendar: calendar) else { return XCTFail("a past time was accepted") }
        XCTAssertFalse(text.isEmpty)
    }

    func testEventsKeepTheEndAfterTheStartAndCanBeAllDay() throws {
        let original = step(VoiceToolName.createCalendarEvent, ["title": "Mom's", "start": "2026-10-17T14:00", "location": "Ochota"])
        var form = PlanStepForm(original, now: now, calendar: calendar)
        XCTAssertEqual(form.location, "Ochota")
        XCTAssertEqual(form.end, date(17, 15))
        form.end = date(17, 13)
        XCTAssertEqual(form.apply(to: original, now: now, calendar: calendar), .problem("The end has to be after the start."))

        form.hasTime = false
        guard case .createCalendarEvent(let draft) = try XCTUnwrap(edited(form, original)).request else { return XCTFail() }
        XCTAssertTrue(draft.allDay)
        XCTAssertEqual(draft.location, "Ochota")
    }

    func testTimersAndNotesAreCheckedToo() throws {
        let timer = step(VoiceToolName.setTimer, ["minutes": 10, "label": "pasta"])
        var form = PlanStepForm(timer, now: now, calendar: calendar)
        XCTAssertEqual(form.minutes, 10)
        form.minutes = 0
        form.seconds = 0
        XCTAssertEqual(form.apply(to: timer, now: now, calendar: calendar), .problem("Set a time of at least one second."))
        form.minutes = 12
        guard case .setTimer(let draft) = try XCTUnwrap(edited(form, timer)).request else { return XCTFail() }
        XCTAssertEqual(draft.seconds, 720)
        XCTAssertEqual(draft.label, "pasta")

        let note = step(VoiceToolName.saveMemory, ["text": "Key in the blue tin"])
        var noteForm = PlanStepForm(note, now: now, calendar: calendar)
        noteForm.text = "   "
        XCTAssertEqual(noteForm.apply(to: note, now: now, calendar: calendar), .problem("Write something first."))
    }

    func testTheAgentIsToldWhichStepsTheUserChanged() {
        let reminder = step(VoiceToolName.createReminder, ["title": "Rent"])
        let reply = PlanReply.summary([(reminder, "added: reminder \"Rent\".")], changed: [2])
        XCTAssertTrue(reply.contains("2. added: reminder \"Rent\". (The user changed this step on screen"), reply)
        XCTAssertFalse(PlanReply.summary([(reminder, "added: x")]).contains("changed this step"))
    }
}
