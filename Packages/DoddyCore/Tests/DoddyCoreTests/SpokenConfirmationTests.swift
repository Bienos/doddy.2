import XCTest
@testable import DoddyCore

/// A spoken yes on a card (decision `2026-11-14-spoken-yes-and-fewer-cards`, step 2): the person's own short "tak",
/// said at least a second after the card appeared and while it still waits, runs exactly what the card shows. Never
/// for money or bookings, never once text from outside is in the conversation, and never while the card waits for
/// the person to choose something on it.
final class SpokenConfirmationTests: XCTestCase {
    private let shown = Date(timeIntervalSince1970: 1_800_000_000)

    private func runs(_ words: String, _ tier: ConfirmationTier = .spokenYes, after seconds: TimeInterval = 4,
                      waitsForAChoice: Bool = false) -> Bool {
        SpokenConfirmation.runs(words, tier: tier, cardShownAt: shown, now: shown.addingTimeInterval(seconds),
                                waitsForAChoice: waitsForAChoice)
    }

    // MARK: The yes

    func testAShortYesSaidAfterTheCardRunsIt() {
        for said in ["tak", "Tak.", "tak, proszę", "jasne", "zrób to", "yes", "Yes please", "ok", "go ahead"] {
            XCTAssertTrue(runs(said), said)
        }
    }

    func testWordsThatAreNotOnlyAYesNeverRunIt() {
        for said in ["tak, ale o piątej", "nie", "czekaj", "tak czekaj", "yes but change the time", "ok wait", "no", "",
                     "tak tak tak tak tak tak", "a może jutro?", "ustaw timer"] {
            XCTAssertFalse(runs(said), said)
        }
    }

    // MARK: When it was said

    func testAYesInTheFirstSecondIsNotAnAnswerToTheCard() {
        // Doddy is still reading the card out, or the words were said before it appeared.
        XCTAssertFalse(runs("tak", after: 0))
        XCTAssertFalse(runs("tak", after: 0.5))
        XCTAssertFalse(runs("tak", after: SpokenConfirmation.earliest - 0.001))
        XCTAssertTrue(runs("tak", after: SpokenConfirmation.earliest))
    }

    func testAYesAfterTheCardsTimeIsTooLate() {
        XCTAssertTrue(runs("tak", after: SpokenConfirmation.latest))
        XCTAssertFalse(runs("tak", after: SpokenConfirmation.latest + 0.001))
        XCTAssertEqual(SpokenConfirmation.latest, AskLedger().window, "the same time a card waits for a tap")
    }

    func testAClockThatReadsBeforeTheCardOrNoClockIsNotAYes() {
        XCTAssertFalse(runs("tak", after: -5))
        XCTAssertFalse(SpokenConfirmation.runs("tak", tier: .spokenYes, cardShownAt: shown, now: Date(timeIntervalSince1970: .nan)))
        XCTAssertFalse(SpokenConfirmation.runs("tak", tier: .spokenYes, cardShownAt: Date(timeIntervalSince1970: .infinity), now: shown))
    }

    // MARK: Which cards

    func testMoneyAndBookingsNeverRunOnWords() {
        XCTAssertFalse(runs("tak", .tapOnly))
        for tool in ["pay_for_page", "book_flight", "call_places"] {
            XCTAssertFalse(runs("tak", ConfirmationTiers.tier(for: tool)), tool)
        }
    }

    func testEveryOtherCardTakesASpokenYes() {
        XCTAssertTrue(runs("tak", .spokenYes))
        // A card for a tool the table runs at once, while it still has its card: a yes is enough there too.
        XCTAssertTrue(runs("tak", .atOnce))
        for tool in ["send_email", "create_calendar_event", "remove_from_list", "call_me_now", "set_timer", "save_memory"] {
            XCTAssertTrue(runs("tak", ConfirmationTiers.tier(for: tool)), tool)
        }
    }

    func testOnceTextFromOutsideIsInTheConversationACardNeedsAFinger() {
        let afterEmail = ConfirmationTiers.tier(for: "reply_to_email", outsideContentSeen: true)
        XCTAssertEqual(afterEmail, .tapOnly)
        XCTAssertFalse(runs("tak", afterEmail))
    }

    func testACardWaitingForThePersonToChooseNeedsATap() {
        // Several places Maps found for a note's reminder: "tak" doesn't say which one.
        XCTAssertFalse(runs("tak", waitsForAChoice: true))
        XCTAssertTrue(runs("tak", waitsForAChoice: false))
    }

    func testTheTierFollowsThePropertyThatSaysSo() {
        XCTAssertTrue(ConfirmationTier.atOnce.acceptsSpokenYes)
        XCTAssertTrue(ConfirmationTier.spokenYes.acceptsSpokenYes)
        XCTAssertFalse(ConfirmationTier.tapOnly.acceptsSpokenYes)
    }

    // MARK: The tier of a call as it came in

    func testTheParkingSpotsTierIsItsActions() {
        XCTAssertEqual(ConfirmationTiers.tier(for: .parkingSpot(.find), toolName: "parking_spot"), .atOnce)
        XCTAssertEqual(ConfirmationTiers.tier(for: .parkingSpot(.clear), toolName: "parking_spot"), .spokenYes)
        XCTAssertEqual(ConfirmationTiers.tier(for: .parkingSpot(.clear), toolName: "parking_spot", outsideContentSeen: true), .tapOnly)
        XCTAssertEqual(ConfirmationTiers.tier(for: .parkingSpot(.save(note: nil)), toolName: "parking_spot"),
                       ConfirmationTiers.tier(for: "parking_spot"))
    }

    func testAnyOtherCallIsTieredByItsName() {
        let call = VoiceToolRequest.parse(name: "remove_from_list", parametersJSON: Data(#"{"list":"Zakupy","items":["mleko"]}"#.utf8))
        XCTAssertEqual(ConfirmationTiers.tier(for: call, toolName: "remove_from_list"), .spokenYes)
        XCTAssertEqual(ConfirmationTiers.tier(for: call, toolName: "remove_from_list", outsideContentSeen: true), .tapOnly)
        XCTAssertEqual(ConfirmationTiers.tier(for: call, toolName: "no_such_tool"), .tapOnly, "the name decides, and an unknown one fails safe")
    }

    // MARK: AskFirst's own cards follow the table

    private let removeMilk = VoiceToolRequest.removeFromList(ListVoiceRequest(list: "Zakupy", items: ["mleko"]))
    private var asks: [(String, VoiceToolRequest)] {
        [("remove_from_list", removeMilk),
         ("parking_spot", .parkingSpot(.clear)),
         ("hand_over_errand", .handOverErrand(ErrandDraft(words: "znajdź lot do Rzymu", brief: "Lot do Rzymu", title: "Rzym"))),
         ("make_something", .makeSomething(StudioJob(topic: "Pompy ciepła"))),
         ("open_food_app", .openFoodApp(try! FoodHandoff.parse(app: "Wolt", search: "pizza").get()))]
    }

    func testAsksOnTheSpokenYesTierTakeASpokenYes() {
        for (tool, request) in asks {
            XCTAssertEqual(ConfirmationTiers.tier(for: request, toolName: tool) == .tapOnly, false, tool)
            let need = AskFirst.need(for: request)
            guard case .yesFirst = need else { return XCTFail("\(tool): \(need)") }
            XCTAssertFalse(AskFirst.needsTap(need), tool)
        }
    }

    func testAfterTextFromOutsideTheSameCardsNeedATapAndShowTheSameWords() {
        var session = OutsideContentSession()
        XCTAssertEqual(AskFirst.need(for: removeMilk, in: session), AskFirst.need(for: removeMilk), "nothing from outside yet")
        session.noteRun(of: "read_email")
        for (tool, request) in asks where tool != "open_food_app" {
            guard case .yesFirst(let card) = AskFirst.need(for: request) else { return XCTFail(tool) }
            XCTAssertEqual(AskFirst.need(for: request, in: session), .tapFirst(card), tool)
            XCTAssertEqual(ConfirmationTiers.tier(for: request, toolName: tool, outsideContentSeen: true), .tapOnly, tool)
        }
        // Opening a food app is on the at-once tier: nothing is ordered, and Doddy's own hand-overs stay as they are.
        let food = VoiceToolRequest.openFoodApp(try! FoodHandoff.parse(app: "Wolt", search: "pizza").get())
        XCTAssertEqual(AskFirst.need(for: food, in: session), AskFirst.need(for: food))
        XCTAssertEqual(ConfirmationTiers.tier(for: food, toolName: "open_food_app", outsideContentSeen: true), .atOnce)
    }

    func testEveryCardMadeHereHasATierAndAnUnnamedOneIsTapOnly() {
        for (tool, request) in asks {
            XCTAssertEqual(AskFirst.ownCardTier(request, outsideContentSeen: false), ConfirmationTiers.tier(for: request, toolName: tool), tool)
        }
        XCTAssertNil(AskFirst.ownCardTier(.saveMemory(text: "x"), outsideContentSeen: false), "not a card made by AskFirst")
    }

    func testTheLedgerTakesAYesForThemAndStillRunsItOnceForExactlyThatRequest() {
        var ledger = AskLedger()
        let need = AskFirst.need(for: removeMilk)
        ledger.asked("c1", request: removeMilk, needsTap: AskFirst.needsTap(need), at: shown)
        XCTAssertEqual(ledger.answer(.userSaid("tak"), for: "c1", at: shown.addingTimeInterval(3)), .granted)
        let other = VoiceToolRequest.removeFromList(ListVoiceRequest(list: "Zakupy", items: ["mleko", "piwo"]))
        XCTAssertFalse(ledger.mayRun("c1", request: other, at: shown.addingTimeInterval(4)), "another payload needs its own yes")
        ledger.asked("c2", request: removeMilk, needsTap: AskFirst.needsTap(need), at: shown)
        XCTAssertEqual(ledger.answer(.userSaid("tak"), for: "c2", at: shown.addingTimeInterval(3)), .granted)
        XCTAssertTrue(ledger.mayRun("c2", request: removeMilk, at: shown.addingTimeInterval(4)))
        XCTAssertFalse(ledger.mayRun("c2", request: removeMilk, at: shown.addingTimeInterval(5)), "once")
    }
}
