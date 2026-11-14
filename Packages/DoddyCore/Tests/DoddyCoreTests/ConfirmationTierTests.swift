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
        XCTAssertEqual(tapOnly, ["pay_for_page", "book_flight", "call_places"])
    }

    func testNothingThatRunsAtOnceTodayStartsAskingAgain() {
        for tool in everyTool where AskFirst.runsAtOnce(tool) {
            XCTAssertEqual(ConfirmationTiers.tier(for: tool), .atOnce, tool)
        }
    }

    func testDoddysOwnUndoableThingsOnThePhoneRunAtOnce() {
        for tool in ["set_timer", "set_alarm", "create_reminder", "save_memory", "remind_me_about_note", "remind_when_to_leave",
                     "parking_spot", "create_list", "add_ingredients", "open_map", "open_camera", "open_food_app", "undo_last",
                     "lost_wallet", "draft_message", "draft_blik_transfer", "draft_invoice", "make_presentation"] {
            XCTAssertEqual(ConfirmationTiers.tier(for: tool), .atOnce, tool)
        }
    }

    func testChangesSendsCallsAndDeletionsGoOnASpokenYes() {
        for tool in ["create_calendar_event", "change_calendar_event", "delete_calendar_event", "delete_calendar_events",
                     "change_reminder", "delete_reminder", "move_reminders", "cancel_alarm", "remove_from_list",
                     "send_email", "reply_to_email", "forward_email", "trash_email", "send_outlook_email",
                     "call_me_now", "call_me_later", "control_home", "run_shortcut", "propose_plan",
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

    func testOnceOutsideTextIsInTheConversationASpokenYesIsNoLongerEnough() {
        // An email, a page or a document can put words in the conversation; a yes after them needs a finger.
        XCTAssertEqual(ConfirmationTiers.tier(for: "send_email", outsideContentSeen: true), .tapOnly)
        XCTAssertEqual(ConfirmationTiers.tier(for: "call_me_now", outsideContentSeen: true), .tapOnly)
        XCTAssertEqual(ConfirmationTiers.tier(forParking: .clear, outsideContentSeen: true), .tapOnly)
        XCTAssertEqual(ConfirmationTiers.tier(for: "set_timer", outsideContentSeen: true), .atOnce, "Doddy's own undoable things stay at once")
        XCTAssertEqual(ConfirmationTiers.tier(for: "pay_for_page", outsideContentSeen: true), .tapOnly)
        XCTAssertEqual(ConfirmationTiers.tier(for: "send_email", outsideContentSeen: false), .spokenYes)
    }

    func testTheTierSaysWhetherASpokenYesMayRunIt() {
        XCTAssertTrue(ConfirmationTier.spokenYes.acceptsSpokenYes)
        XCTAssertFalse(ConfirmationTier.tapOnly.acceptsSpokenYes)
        XCTAssertFalse(ConfirmationTier.atOnce.showsCard)
        XCTAssertTrue(ConfirmationTier.spokenYes.showsCard)
        XCTAssertTrue(ConfirmationTier.tapOnly.showsCard)
    }
}
