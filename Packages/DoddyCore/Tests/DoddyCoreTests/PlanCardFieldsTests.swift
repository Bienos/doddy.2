import Foundation
import XCTest
@testable import DoddyCore

/// ADR-718: a plan card's step line shows everything the step will write. An event's place and
/// notes and a reminder's notes were saved but not on the line; "What Doddy did" still keeps only
/// what it always kept (it stays for 30 days).
final class PlanCardFieldsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))! }

    private func step(_ json: String) throws -> PlanStep {
        let data = try JSONSerialization.data(withJSONObject: ["steps": json])
        guard case .plan(let steps) = PlanProposal.parse(parametersJSON: data, now: now, calendar: calendar), let first = steps.first else {
            XCTFail("not a plan: \(json)")
            throw CocoaError(.coderInvalidValue)
        }
        return first
    }

    func testAnEventStepNamesItsPlaceAndNotesInFull() throws {
        let notes = "Zabierz umowę.\nZapytaj o fakturę za październik i o termin płatności.\n" + String(repeating: "x", count: 900)
        let json = #"[{"tool":"create_calendar_event","title":"Lunch","start":"2026-11-06T13:00","end":"2026-11-06T14:00","location":"Café Roma, Via Appia 12","notes":"#
            + "\"" + notes.replacingOccurrences(of: "\n", with: "\\n") + "\"}]"
        let request = try XCTUnwrap(try step(json).activity(calendar: calendar))
        let detail = try XCTUnwrap(request.detail)
        XCTAssertTrue(detail.hasPrefix("“Lunch” · 2026-11-06 13:00"), detail)
        XCTAssertTrue(detail.contains(" · place “Café Roma, Via Appia 12”"), detail)
        XCTAssertTrue(detail.contains(" · notes “\(notes)”"), "the notes are on the line whole, line breaks and all")
        // The 30-day log keeps what it always kept.
        let kept = try XCTUnwrap(request.logDetail)
        XCTAssertEqual(kept, "“Lunch” · 2026-11-06 13:00")
        XCTAssertFalse(kept.contains("Café"))
        XCTAssertFalse(kept.contains("umowę"))
        let entry = ActivityEntry(request: request, reply: "added: an event on 2026-11-06 13:00 to 2026-11-06 14:00.", at: now)
        XCTAssertEqual(entry.detail, kept)
        let started = ActivityEntry.started(request, at: now)
        XCTAssertEqual(started.detail, kept)
    }

    func testAReminderStepNamesItsNotesInFull() throws {
        let notes = "Dzwoń po 9:00, numer w notatce 'Bank'."
        let json = #"[{"tool":"create_reminder","title":"Zadzwoń do banku","due":"2026-11-06T09:30","notes":"\#(notes)"}]"#
        let request = try XCTUnwrap(try step(json).activity(calendar: calendar))
        let detail = try XCTUnwrap(request.detail)
        XCTAssertTrue(detail.hasPrefix("“Zadzwoń do banku” · due "), detail)
        XCTAssertTrue(detail.hasSuffix(" · notes “\(notes)”"), detail)
        XCTAssertFalse(detail.contains("place"), "a reminder has no place")
        let kept = try XCTUnwrap(request.logDetail)
        XCTAssertFalse(kept.contains("notes"))
        XCTAssertFalse(kept.contains("Bank"))
        XCTAssertEqual(ActivityEntry(request: request, reply: "added: a reminder.", at: now).detail, kept)
        XCTAssertNotNil(request.reminderKey, "the retry key is still there")
    }

    func testAStepWithNothingExtraReadsAsItAlwaysDid() throws {
        let event = try XCTUnwrap(try step(#"[{"tool":"create_calendar_event","title":"Lunch","start":"2026-11-06T13:00","end":"2026-11-06T14:00"}]"#)
            .activity(calendar: calendar))
        XCTAssertEqual(event.detail, "“Lunch” · 2026-11-06 13:00")
        XCTAssertEqual(event.detail, event.logDetail)
        let reminder = try XCTUnwrap(try step(#"[{"tool":"create_reminder","title":"Mleko","due":"2026-11-06T09:30"}]"#).activity(calendar: calendar))
        XCTAssertEqual(reminder.detail, reminder.logDetail)
        XCTAssertFalse(try XCTUnwrap(reminder.detail).contains("notes"))
        // Empty strings aren't fields.
        XCTAssertEqual(WrittenFields.line(place: "", notes: ""), "")
        XCTAssertEqual(WrittenFields.line(), "")
        XCTAssertEqual(WrittenFields.line(place: "Dom"), " · place “Dom”")
        XCTAssertEqual(WrittenFields.line(notes: "Kod 1234"), " · notes “Kod 1234”")
    }

    func testTheEventDraftTheWriteUsesIsTheOneTheLineDescribes() throws {
        let plan = try step(#"[{"tool":"create_calendar_event","title":"Lunch","start":"2026-11-06T13:00","end":"2026-11-06T14:00","location":"Biuro","notes":"Pokój 4"}]"#)
        guard case .createCalendarEvent(let draft) = plan.request else { return XCTFail("not an event") }
        // The place and notes saved (DeviceConnections.saveEvent) are these two fields, and the line carries both.
        let detail = try XCTUnwrap(plan.activity(calendar: calendar)?.detail)
        XCTAssertTrue(detail.contains(try XCTUnwrap(draft.location)))
        XCTAssertTrue(detail.contains(try XCTUnwrap(draft.notes)))
    }
}
