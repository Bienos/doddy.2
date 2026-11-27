import XCTest
@testable import DoddyCore

/// How each voice tool is confirmed (decision `2026-11-14-spoken-yes-and-fewer-cards`): at once, on a
/// spoken yes (or a tap), or on a tap only. The owner's choice of 14 Nov 2026: a spoken yes is enough
/// for everything but money and bookings.
final class ConfirmationTierTests: XCTestCase {
    private let everyTool = ToolCatalog.all.map(\.name)

    func testEveryToolHasATierAndOnlyMoneyAndBookingsNeedATap() {
        XCTAssertEqual(everyTool.count, Set(everyTool).count)
        let tapOnly = Set(everyTool.filter { ConfirmationTiers.tier(for: $0) == .tapOnly })
        XCTAssertEqual(tapOnly, ["pay_for_page"])
        // Bookings and orders take the person's own words naming the action, or a tap (decision 2026-11-27-voice-first-doddy, step 3).
        let strong = Set(everyTool.filter { ConfirmationTiers.tier(for: $0) == .strongSpokenYes })
        XCTAssertEqual(strong, ["book_flight", "call_places"])
        XCTAssertEqual(strong, ConfirmationTiers.strongYes)
    }

    func testNothingThatRunsAtOnceTodayStartsAskingAgain() {
        for tool in everyTool where AskFirst.runsAtOnce(tool) {
            XCTAssertEqual(ConfirmationTiers.tier(for: tool), .atOnce, tool)
        }
    }

    func testDoddysOwnUndoableThingsOnThePhoneRunAtOnce() {
        for tool in ["set_timer", "set_alarm", "create_reminder", "save_memory", "remind_me_about_note", "remind_when_to_leave",
                     "parking_spot", "create_list", "add_ingredients", "open_map", "open_camera", "open_food_app",
                     "lost_wallet", "draft_message", "draft_blik_transfer", "draft_invoice", "make_presentation"] {
            XCTAssertEqual(ConfirmationTiers.tier(for: tool), .atOnce, tool)
        }
        // Step 2b: nothing undoes an undo, so "undo that" keeps its card and a spoken yes.
        XCTAssertEqual(ConfirmationTiers.tier(for: "undo_last"), .spokenYes)
    }

    func testChangesSendsCallsAndDeletionsGoOnASpokenYes() {
        for tool in ["create_calendar_event", "change_calendar_event", "delete_calendar_event", "delete_calendar_events",
                     "change_reminder", "delete_reminder", "move_reminders", "cancel_alarm", "remove_from_list",
                     "send_email", "reply_to_email", "forward_email", "trash_email", "send_outlook_email",
                     "call_me_every_morning", "control_home", "run_shortcut", "propose_plan",
                     "hand_over_errand", "make_something", "add_todoist_task", "create_google_event"] {
            XCTAssertEqual(ConfirmationTiers.tier(for: tool), .spokenYes, tool)
        }
    }

    func testEveryNameInTheListsIsARealTool() {
        let known = Set(everyTool)
        XCTAssertEqual(ConfirmationTiers.tapOnly.subtracting(known), [], "a tap-only name that is no tool")
        XCTAssertEqual(ConfirmationTiers.ownUndoableAtOnce.subtracting(known), [], "an at-once name that is no tool")
        XCTAssertTrue(ConfirmationTiers.tapOnly.isDisjoint(with: ConfirmationTiers.ownUndoableAtOnce))
    }

    func testAToolNobodyClassifiedNeedsATap() {
        XCTAssertEqual(ConfirmationTiers.tier(for: "wire_money_somewhere"), .tapOnly, "a new or unknown tool fails safe")
        XCTAssertEqual(ConfirmationTiers.tier(for: ""), .tapOnly)
    }

    func testForgettingTheParkingSpotIsASpokenYesNotAtOnce() {
        XCTAssertEqual(ConfirmationTiers.tier(forParking: .save(note: nil)), .atOnce)
        XCTAssertEqual(ConfirmationTiers.tier(forParking: .find), .atOnce)
        XCTAssertEqual(ConfirmationTiers.tier(forParking: .clear), .spokenYes, "nothing brings a forgotten spot back")
    }

    func testCallsToTheUsersOwnPhoneRunAtOnce() {
        // Owner, 25 Nov 2026: "zadzwoń do mnie" is the yes. Only the user's own verified number can be rung; the server
        // checks consent, the number and its limits again. A standing morning call still shows its card.
        for tool in ["call_me_now", "call_me_later"] {
            XCTAssertEqual(ConfirmationTiers.tier(for: tool), .atOnce, tool)
            XCTAssertEqual(ConfirmationTiers.tier(for: tool, outsideContentSeen: true), .atOnce, tool)
            XCTAssertEqual(ConfirmationTiers.specAsk(for: tool), .runsNow, tool)
        }
        XCTAssertEqual(ConfirmationTiers.tier(for: "call_me_every_morning"), .spokenYes)
        XCTAssertEqual(ConfirmationTiers.tier(for: "call_places"), .strongSpokenYes, "calling other people for a booking: a tap or \"tak, zarezerwuj\" (step 3)")
    }

    func testOutsideTextNoLongerMakesDoddysOwnThingsAsk() {
        // Owner, 25 Nov 2026 (decision 2026-11-25-doddy-acts-without-asking), replacing option 2 of 15 Nov: after an email,
        // a page or a document, Doddy's own things keep running at once. The text stays data, never an instruction.
        for own in ConfirmationTiers.ownUndoableAtOnce {
            XCTAssertEqual(ConfirmationTiers.tier(for: own, outsideContentSeen: true), .atOnce, own)
            XCTAssertEqual(ConfirmationTiers.tier(for: own, outsideContentSeen: false), .atOnce, own)
        }
        XCTAssertEqual(ConfirmationTiers.tier(forParking: .save(note: nil), outsideContentSeen: true), .atOnce)
        // A change that already asks keeps asking; forgetting the parking spot still asks.
        XCTAssertEqual(ConfirmationTiers.tier(for: "send_email", outsideContentSeen: true), .spokenYes)
        XCTAssertEqual(ConfirmationTiers.tier(for: "send_email", outsideContentSeen: false), .spokenYes)
        XCTAssertEqual(ConfirmationTiers.tier(forParking: .clear, outsideContentSeen: true), .spokenYes)
        // Looks and reads run at once; money and bookings stay a tap, and an unknown tool fails safe.
        XCTAssertEqual(ConfirmationTiers.tier(forParking: .find, outsideContentSeen: true), .atOnce, "finding the car is a look")
        XCTAssertEqual(ConfirmationTiers.tier(for: "web_search", outsideContentSeen: true), .atOnce)
        XCTAssertEqual(ConfirmationTiers.tier(for: "read_email", outsideContentSeen: true), .atOnce)
        for money in ConfirmationTiers.tapOnly {
            XCTAssertEqual(ConfirmationTiers.tier(for: money, outsideContentSeen: true), .tapOnly, money)
        }
        for booking in ConfirmationTiers.strongYes {
            XCTAssertEqual(ConfirmationTiers.tier(for: booking, outsideContentSeen: true), .tapOnly, "after outside text a booking is a tap: \(booking)")
        }
        XCTAssertEqual(ConfirmationTiers.tier(for: "wire_money_somewhere", outsideContentSeen: true), .tapOnly)
    }

    func testTheTierSaysWhetherASpokenYesMayRunIt() {
        XCTAssertTrue(ConfirmationTier.spokenYes.acceptsSpokenYes)
        XCTAssertFalse(ConfirmationTier.tapOnly.acceptsSpokenYes)
        XCTAssertTrue(ConfirmationTier.strongSpokenYes.acceptsSpokenYes, "only its own phrase, StrongSpokenYesTests")
        XCTAssertTrue(ConfirmationTier.strongSpokenYes.showsCard)
        XCTAssertFalse(ConfirmationTier.atOnce.showsCard)
        XCTAssertTrue(ConfirmationTier.spokenYes.showsCard)
        XCTAssertTrue(ConfirmationTier.tapOnly.showsCard)
    }
}
