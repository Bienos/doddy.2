@testable import DoddyCore
import XCTest

/// The rules for buying through Doddy (docs/implementation/SHOPPING_CHECKOUT.md, ADR-613), held before any
/// provider exists: the yes is bound to the exact cart, the order is sent at most once, "ordered" is said only
/// after the shop's confirmation, and an order with no trustworthy answer is `unknown` and is never sent again.
final class CheckoutTests: XCTestCase {
    private let before = ServerDates.parse("2026-10-24T12:10:00.000Z")!
    private let after = ServerDates.parse("2026-10-24T12:31:00.000Z")!

    private func fixture() throws -> [String: Any] { try Fixtures.json("checkout_draft_v1.json") }

    private func draft(_ edit: ([String: Any]) -> [String: Any] = { $0 }) throws -> CheckoutDraft {
        let raw = edit(try XCTUnwrap(fixture()["draft"] as? [String: Any]))
        let lines = try XCTUnwrap(raw["lines"] as? [[String: Any]]).map {
            CheckoutLine(title: $0["title"] as! String, quantity: $0["quantity"] as! Int, unitMinor: $0["unitMinor"] as! Int)
        }
        return CheckoutDraft(shop: raw["shop"] as! String, shopHost: raw["shopHost"] as! String, shopReference: raw["shopReference"] as! String,
                             currency: raw["currency"] as! String, lines: lines, shippingMinor: raw["shippingMinor"] as! Int,
                             totalMinor: raw["totalMinor"] as! Int, quoteExpiresAt: raw["quoteExpiresAt"] as! String)
    }

    private func sent() throws -> CheckoutSession {
        var session = CheckoutSession(draft: try draft())
        try session.approve(shownDigest: session.draft.digest, now: before)
        return session
    }

    // MARK: The cart and its digest

    func testTheDigestIsTheFixturesCanonicalStringHashedAndTheFixtureCartIsValid() throws {
        let cart = try draft()
        XCTAssertEqual(cart.canonicalJSON, try fixture()["canonical"] as? String)
        XCTAssertEqual(cart.digest, try fixture()["digest"] as? String, "SHA-256 over the same bytes, computed by Python")
        XCTAssertEqual(cart.validationIssues(), [])
    }

    func testAnyChangeToTheCartIsADifferentDigest() throws {
        let base = try draft().digest
        let edits: [(String, ([String: Any]) -> [String: Any])] = [
            ("quantity", { var d = $0; var l = d["lines"] as! [[String: Any]]; l[0]["quantity"] = 2; d["lines"] = l; d["totalMinor"] = 379_800; return d }),
            ("price", { var d = $0; var l = d["lines"] as! [[String: Any]]; l[0]["unitMinor"] = 189_800; d["lines"] = l; d["totalMinor"] = 189_800; return d }),
            ("shipping", { var d = $0; d["shippingMinor"] = 1_500; d["totalMinor"] = 191_400; return d }),
            ("shop", { var d = $0; d["shop"] = "x-kom"; return d }),
            ("host", { var d = $0; d["shopHost"] = "x-kom.pl"; return d }),
            ("reference", { var d = $0; d["shopReference"] = "cs_test_other"; return d }),
            ("quote", { var d = $0; d["quoteExpiresAt"] = "2026-10-24T12:45:00.000Z"; return d }),
        ]
        for (name, edit) in edits {
            XCTAssertNotEqual(try draft(edit).digest, base, name)
        }
    }

    func testACartThatCantBeShownIsRefusedWithTheReason() throws {
        func issues(_ edit: @escaping ([String: Any]) -> [String: Any]) throws -> [CheckoutIssue] { try draft(edit).validationIssues() }
        XCTAssertEqual(try issues { var d = $0; d["lines"] = [[String: Any]](); d["totalMinor"] = 0; return d }, [.noLines, .badShippingOrTotal])
        XCTAssertEqual(try issues { var d = $0; d["totalMinor"] = 189_000; return d }, [.totalDoesNotAddUp])
        XCTAssertEqual(try issues { var d = $0; var l = d["lines"] as! [[String: Any]]; l[0]["quantity"] = 0; d["lines"] = l; return d }.contains(.badQuantity(line: 1)), true)
        XCTAssertEqual(try issues { var d = $0; var l = d["lines"] as! [[String: Any]]; l[0]["unitMinor"] = -5; d["lines"] = l; return d }.contains(.badPrice(line: 1)), true)
        XCTAssertEqual(try issues { var d = $0; d["shippingMinor"] = -1; return d }, [.badShippingOrTotal])
        XCTAssertEqual(try issues { var d = $0; var l = d["lines"] as! [[String: Any]]; l[0]["unitMinor"] = 600_000; d["lines"] = l; d["totalMinor"] = 600_000; return d }, [.overTheLimit])
        XCTAssertEqual(try issues { var d = $0; d["shopHost"] = "https://mediaexpert.pl/p"; return d }, [.badShopHost])
        XCTAssertEqual(try issues { var d = $0; d["currency"] = "zł"; return d }, [.badCurrency])
        XCTAssertEqual(try issues { var d = $0; d["shopReference"] = "  "; return d }, [.emptyField("shopReference")])
        XCTAssertEqual(try issues { var d = $0; d["quoteExpiresAt"] = "tomorrow"; return d }, [.badExpiry])
    }

    // MARK: The yes

    func testApprovalNeedsTheDigestOfTheCartThatWasShown() throws {
        var session = CheckoutSession(draft: try draft())
        XCTAssertThrowsError(try session.approve(shownDigest: String(repeating: "0", count: 64), now: before)) {
            XCTAssertEqual($0 as? CheckoutError, .digestDoesNotMatch)
        }
        XCTAssertEqual(session.status, .needsApproval)
        XCTAssertEqual(session.timesSent, 0)
        // The card showed an older cart; the cart changed since: the old digest doesn't approve the new one.
        let older = try draft()
        let newer = try draft { var d = $0; d["shippingMinor"] = 1_500; d["totalMinor"] = 191_400; return d }
        var changed = CheckoutSession(draft: newer)
        XCTAssertThrowsError(try changed.approve(shownDigest: older.digest, now: before))
        try session.approve(shownDigest: older.digest, now: before)
        XCTAssertEqual(session.status, .executing)
        XCTAssertEqual(session.timesSent, 1)
    }

    func testAnExpiredQuoteAnInvalidCartAndASecondYesAreRefused() throws {
        var late = CheckoutSession(draft: try draft())
        XCTAssertThrowsError(try late.approve(shownDigest: late.draft.digest, now: after)) { XCTAssertEqual($0 as? CheckoutError, .quoteExpired) }
        XCTAssertEqual(late.status, .needsApproval)
        XCTAssertEqual(late.timesSent, 0)

        var broken = CheckoutSession(draft: try draft { var d = $0; d["totalMinor"] = 1; return d })
        XCTAssertThrowsError(try broken.approve(shownDigest: broken.draft.digest, now: before)) {
            XCTAssertEqual($0 as? CheckoutError, .notValid([.totalDoesNotAddUp]))
        }
        XCTAssertEqual(broken.timesSent, 0)

        var twice = try sent()
        XCTAssertThrowsError(try twice.approve(shownDigest: twice.draft.digest, now: before)) { XCTAssertEqual($0 as? CheckoutError, .notWaitingForApproval) }
        XCTAssertEqual(twice.timesSent, 1, "a second yes never sends a second order")
    }

    func testANoBeforeTheTapSendsNothingAndAfterTheTapItCantBeTaken() throws {
        var no = CheckoutSession(draft: try draft())
        no.cancel()
        XCTAssertEqual(no.status, .cancelled)
        XCTAssertThrowsError(try no.approve(shownDigest: no.draft.digest, now: before))
        XCTAssertEqual(no.timesSent, 0)
        var running = try sent()
        running.cancel()
        XCTAssertEqual(running.status, .executing, "once sent, the order can't be cancelled from here")
    }

    // MARK: What came back

    func testOnlyAConfirmationWithAnOrderReferenceIsOrdered() throws {
        var ok = try sent()
        try ok.sendFinished(.confirmed(reference: "  ME-2026-481516 "))
        XCTAssertEqual(ok.status, .confirmed(reference: "ME-2026-481516"))
        XCTAssertTrue(ok.agentWords.hasPrefix("confirmed:"))
        XCTAssertTrue(ok.agentWords.contains("Only now may you say it is ordered"))

        var noReference = try sent()
        try noReference.sendFinished(.confirmed(reference: "   "))
        XCTAssertEqual(noReference.status, .unknown, "a confirmation with nothing to show for it is not trusted")
    }

    func testNoTrustworthyAnswerIsUnknownNeverSuccessAndNeverSentAgain() throws {
        var session = try sent()
        try session.sendFinished(.noTrustworthyAnswer)
        XCTAssertEqual(session.status, .unknown)
        let words = session.agentWords
        XCTAssertTrue(words.hasPrefix("unknown:"))
        XCTAssertTrue(words.contains("Don't say it is ordered and don't say it failed"))
        XCTAssertTrue(words.contains("won't send it again"))
        // No move sends it again, however it is asked.
        XCTAssertThrowsError(try session.approve(shownDigest: session.draft.digest, now: before)) { XCTAssertEqual($0 as? CheckoutError, .notWaitingForApproval) }
        XCTAssertThrowsError(try session.sendFinished(.confirmed(reference: "X"))) { XCTAssertEqual($0 as? CheckoutError, .notSent) }
        XCTAssertEqual(session.timesSent, 1)
        // A look-up with no answer leaves it unknown; one with a confirmation settles it; one that says declined settles it as failed.
        try session.reconcile(.noTrustworthyAnswer)
        XCTAssertEqual(session.status, .unknown)
        var settledYes = session
        try settledYes.reconcile(.confirmed(reference: "ME-1"))
        XCTAssertEqual(settledYes.status, .confirmed(reference: "ME-1"))
        var settledNo = session
        try settledNo.reconcile(.declined)
        XCTAssertEqual(settledNo.status, .failed)
        XCTAssertEqual(settledNo.timesSent, 1)
    }

    func testReconcilingOnlyAppliesToAnUnknownOrder() throws {
        var fresh = CheckoutSession(draft: try draft())
        XCTAssertThrowsError(try fresh.reconcile(.confirmed(reference: "X"))) { XCTAssertEqual($0 as? CheckoutError, .notUnknown) }
        var running = try sent()
        XCTAssertThrowsError(try running.reconcile(.confirmed(reference: "X")))
        try running.sendFinished(.declined)
        XCTAssertEqual(running.status, .failed)
        XCTAssertThrowsError(try running.reconcile(.confirmed(reference: "X")), "a failed order isn't revived by a later look-up")
    }

    func testOnlyConfirmedWordsAllowOrdered() throws {
        var statuses: [CheckoutSession] = []
        statuses.append(CheckoutSession(draft: try draft()))                    // needs approval
        statuses.append(try sent())                                              // executing
        var failed = try sent(); try failed.sendFinished(.declined); statuses.append(failed)
        var unknown = try sent(); try unknown.sendFinished(.noTrustworthyAnswer); statuses.append(unknown)
        var cancelled = CheckoutSession(draft: try draft()); cancelled.cancel(); statuses.append(cancelled)
        for session in statuses {
            XCTAssertFalse(session.agentWords.contains("Only now may you say it is ordered"), session.agentWords)
        }
        XCTAssertTrue(statuses[1].agentWords.contains("not ordered yet"))
    }
}
