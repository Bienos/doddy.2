import XCTest
@testable import DoddyCore

/// Step 2b of decision `2026-11-14-spoken-yes-and-fewer-cards`: Doddy's own changes on this iPhone that have Undo in
/// "What Doddy did", and the drafts and hand-overs that change nothing anywhere, run when asked, with no card. Those
/// still without Undo keep their card (a spoken yes or a tap) until they have one (step 2c); an undo keeps its card,
/// because nothing undoes an undo.
final class AtOnceOwnChangesTests: XCTestCase {
    private let atOnce: Set<String> = [
        "save_memory", "create_reminder", "add_ingredients", "open_map", "open_camera", "open_food_app", "lost_wallet",
        "draft_message", "draft_blik_transfer", "draft_invoice", "make_presentation",
    ]
    private let waitingForUndo: Set<String> = [
        "set_timer", "set_alarm", "create_list", "remind_me_about_note", "remind_when_to_leave", "parking_spot",
    ]

    private func request(_ name: String, _ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: name, parametersJSON: Data(json.utf8))
    }

    private var requests: [(String, VoiceToolRequest)] {
        [("save_memory", request("save_memory", #"{"text":"Kod do bramy 4821"}"#)),
         ("create_reminder", request("create_reminder", #"{"title":"Kupić mleko"}"#)),
         ("add_ingredients", request("add_ingredients", #"{"list":"Zakupy","dish":"Naleśniki","items":["mąka","mleko"]}"#)),
         ("open_map", request("open_map", #"{"place":"Dworzec Centralny"}"#)),
         ("open_camera", request("open_camera", "{}")),
         ("open_food_app", request("open_food_app", #"{"app":"Wolt","search":"pizza"}"#)),
         ("lost_wallet", request("lost_wallet", #"{"lost":["bank_cards"]}"#)),
         ("draft_message", request("draft_message", #"{"to":"Marta","body":"Będę o 18"}"#)),
         ("draft_blik_transfer", request("draft_blik_transfer", #"{"to":"Marta","amount":50}"#)),
         ("draft_invoice", request("draft_invoice", #"{"start_new":true}"#)),
         ("make_presentation", request("make_presentation", #"{"title":"Plan","slides":[{"title":"Jeden","bullets":["a"]}]}"#))]
    }

    func testTheListIsExactlyDoddysUndoableChangesAndHandOvers() {
        XCTAssertEqual(AskFirst.ownChangesAtOnce, atOnce)
        XCTAssertEqual(Set(requests.map(\.0)), atOnce, "every one is exercised below")
    }

    func testEachRunsAtOnceEverywhereTheRuleIsWritten() {
        for name in atOnce {
            XCTAssertTrue(AskFirst.runsAtOnce(name), name)
            XCTAssertEqual(ToolCatalog.descriptor(name)?.approval, .runsNow, name)
            XCTAssertEqual(ConfirmationTiers.tier(for: name), .atOnce, name)
            XCTAssertEqual(ConfirmationTiers.specAsk(for: name), .runsNow, name)
        }
        for (name, request) in requests {
            if case .invalid(_, let reason) = request { XCTFail("\(name): \(reason)") }
            XCTAssertEqual(AskFirst.need(for: request), .runsNow, name)
            XCTAssertEqual(AskFirst.need(for: request, polish: true), .runsNow, name)
        }
    }

    func testTextFromOutsideDoesntPutTheirCardBack() {
        // Doddy's own undoable things stay at once (the table, step 1); the person sees each result and can undo it.
        var afterEmail = OutsideContentSession()
        afterEmail.noteRun(of: "read_email")
        for (name, request) in requests {
            XCTAssertEqual(AskFirst.need(for: request, in: afterEmail), .runsNow, name)
        }
    }

    func testTheFourThatOpenAnotherAppOrTheCameraAreNamedForTheOnScreenRule() {
        // The app runs these at once only while Doddy is on screen: iOS opens nothing from the background, and
        // "opened" must never be said of something that didn't open. Otherwise their card stays.
        XCTAssertEqual(AskFirst.opensSomethingElse, ["open_map", "open_camera", "draft_message", "open_food_app"])
        XCTAssertTrue(AskFirst.opensSomethingElse.isSubset(of: AskFirst.ownChangesAtOnce))
    }

    func testThoseWithoutUndoKeepTheirCardAndTakeASpokenYes() {
        for name in waitingForUndo {
            XCTAssertFalse(AskFirst.runsAtOnce(name), name)
            XCTAssertEqual(ToolCatalog.descriptor(name)?.approval, .card, name)
            XCTAssertEqual(ConfirmationTiers.specAsk(for: name), .yesOrTap, name)
            XCTAssertTrue(ConfirmationTiers.tier(for: name).acceptsSpokenYes, name)
        }
        XCTAssertEqual(AskFirst.need(for: .parkingSpot(.save(note: nil))), .ownPayloadCard)
        XCTAssertEqual(AskFirst.need(for: .parkingSpot(.find)), .runsNow)
    }

    func testAnUndoKeepsItsCardBecauseNothingUndoesAnUndo() {
        XCTAssertEqual(ConfirmationTiers.tier(for: "undo_last"), .spokenYes)
        XCTAssertFalse(AskFirst.runsAtOnce("undo_last"))
        XCTAssertEqual(AskFirst.need(for: request("undo_last", "{}")), .ownPayloadCard)
        XCTAssertEqual(ConfirmationTiers.specAsk(for: "undo_last"), .yesOrTap)
    }

    func testMoneyAndBookingsAreNeverAmongThem() {
        XCTAssertTrue(AskFirst.ownChangesAtOnce.isDisjoint(with: ConfirmationTiers.tapOnly))
    }
}
