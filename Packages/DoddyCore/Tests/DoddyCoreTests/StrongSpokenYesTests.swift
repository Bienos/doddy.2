import XCTest
@testable import DoddyCore

/// Bookings and orders by voice (decision 2026-11-27-voice-first-doddy, step 3): a tap, or the person's own words naming
/// the action. A plain yes never; after outside text a tap only; paying for a page stays a tap and Face ID.
final class StrongSpokenYesTests: XCTestCase {
    private let shown = Date(timeIntervalSince1970: 1_000)

    func testOnlyWordsNamingTheActionCount() {
        for said in ["tak, zarezerwuj", "Zarezerwuj", "tak zarezerwuj proszę", "yes, book it", "book it now", "okej, rezerwuj"] {
            XCTAssertTrue(StrongSpokenYes.isYes(said, for: .book), said)
        }
        for said in ["tak, zamów", "zamów", "yes, order it"] {
            XCTAssertTrue(StrongSpokenYes.isYes(said, for: .order), said)
        }
        XCTAssertTrue(StrongSpokenYes.isYes("tak, dzwoń", for: .call))
    }

    func testAPlainYesAnotherActionOrAnythingMoreRunsNothing() {
        let refused: [(String, StrongSpokenYes.Action)] = [
            ("tak", .book), ("yes", .book), ("ok", .order), ("jasne", .book),  // a plain yes
            ("tak, zamów", .book), ("tak, zarezerwuj", .order), ("tak, dzwoń", .book),  // another action
            ("zarezerwuj, ale na ósmą", .book), ("nie, nie zamawiaj", .order), ("czekaj, zamów", .order),  // a veto
            ("zarezerwuj na jutro", .book), ("zamów dwie pizze", .order),  // a change, not an answer
            ("zarezerwuj 20:00", .book),  // a number the card didn't ask for
            ("tak zarezerwuj ten stolik dla nas teraz", .book),  // too long to be a plain answer
            ("", .book),
        ]
        for (said, action) in refused {
            XCTAssertFalse(StrongSpokenYes.isYes(said, for: action), "\(said) for \(action)")
        }
    }

    func testBookingsAndOrdersTakeTheStrongYesPaymentsATap() {
        XCTAssertEqual(ConfirmationTiers.tier(for: "call_places"), .strongSpokenYes)
        XCTAssertEqual(ConfirmationTiers.tier(for: "book_flight"), .strongSpokenYes)
        XCTAssertEqual(ConfirmationTiers.tier(for: "pay_for_page"), .tapOnly, "Face ID follows the tap anyway")
        XCTAssertEqual(ConfirmationTiers.tier(for: "a_tool_nobody_classified"), .tapOnly, "fails safe")
        XCTAssertEqual(ConfirmationTiers.specAsk(for: "call_places"), .strongYesOrTap)
        XCTAssertEqual(ConfirmationTiers.specAsk(for: "pay_for_page"), .tap)
    }

    func testAfterOutsideTextOnlyATapBooks() {
        XCTAssertEqual(ConfirmationTiers.tier(for: "call_places", outsideContentSeen: true), .tapOnly)
        XCTAssertEqual(ConfirmationTiers.tier(for: "book_flight", outsideContentSeen: true), .tapOnly)
    }

    func testTheCardRunsOnlyOnItsOwnPhraseInTime() {
        let tier = ConfirmationTier.strongSpokenYes
        XCTAssertTrue(SpokenConfirmation.runs("tak, zarezerwuj", tier: tier, cardShownAt: shown, now: shown + 5, action: .book))
        XCTAssertFalse(SpokenConfirmation.runs("tak", tier: tier, cardShownAt: shown, now: shown + 5, action: .book))
        XCTAssertFalse(SpokenConfirmation.runs("tak, zarezerwuj", tier: tier, cardShownAt: shown, now: shown + 5), "no action named: never")
        XCTAssertFalse(SpokenConfirmation.runs("tak, zarezerwuj", tier: tier, cardShownAt: shown, now: shown + 0.5, action: .book), "too soon")
        XCTAssertFalse(SpokenConfirmation.runs("tak, zarezerwuj", tier: tier, cardShownAt: shown, now: shown + 121, action: .book), "too late")
        XCTAssertFalse(SpokenConfirmation.runs("tak, zarezerwuj", tier: .tapOnly, cardShownAt: shown, now: shown + 5, action: .book))
        // A plain yes still answers every other card.
        XCTAssertTrue(SpokenConfirmation.runs("tak", tier: .spokenYes, cardShownAt: shown, now: shown + 5))
    }

    func testACallSaysWhichActionItIs() {
        let place = CallTaskPlace(name: "Roma", phone: "+48221234567")
        let question = CallTaskDraft(places: [place], question: "Czy macie stolik?", goal: "stolik", textResult: false)
        XCTAssertEqual(ConfirmationTiers.strongAction(for: .callPlaces(question), toolName: "call_places"), .call)
        XCTAssertEqual(ConfirmationTiers.strongAction(for: .cloudTool(CloudToolCall(name: "book_flight", arguments: [:])), toolName: "book_flight"), .book)
        XCTAssertNil(ConfirmationTiers.strongAction(for: .deleteNote(quote: "x"), toolName: VoiceToolName.deleteNote))
        XCTAssertEqual(StrongSpokenYes.Action.order.phrase(polish: true), "tak, zamów")
    }
}
