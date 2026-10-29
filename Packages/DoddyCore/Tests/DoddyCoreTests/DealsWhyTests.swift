@testable import DoddyCore
import XCTest

/// ADR-664: "Dlaczego to?", a second shop only when it's worth the user's own minimum, and the start-day reminder.
final class DealsWhyTests: XCTestCase {
    private func offer(_ chain: DealsChain, _ minor: Int, perKg: Int? = nil, product: String = "Masło 200 g", from: String? = nil,
                       flags: [DealOffer.Flag] = []) -> DealOffer {
        DealOffer(chain: chain, product: product, price: Money(minor: minor), unitPrice: perKg.map { .init(minor: $0, per: .kg) },
                  validFrom: from.flatMap(DealDay.init(rawValue:)), source: .init(url: "https://\(chain.rawValue).example"), check: false, flags: flags)
    }

    func testWhyThisOne() {
        XCTAssertEqual(DealsWhy.reason([offer(.lidl, 499, perKg: 2_495), offer(.dino, 549, perKg: 2_745), offer(.aldi, 1_999, perKg: 1_999)]),
                       .lowestPerUnit(per: .kg, value: Money(minor: 1_999), next: (.lidl, Money(minor: 2_495))))
        XCTAssertEqual(DealsWhy.reason([offer(.lidl, 499), offer(.dino, 549)]), .cheapestPack(next: (.dino, Money(minor: 549))))
        XCTAssertEqual(DealsWhy.reason([offer(.lidl, 499)]), .only)
        XCTAssertNil(DealsWhy.reason([]))
        let noLidlPlus = DealsPrograms(notUsed: [.lidlPlus])
        XCTAssertEqual(DealsWhy.reason([offer(.lidl, 399, flags: [.app]), offer(.dino, 549)], programs: noLidlPlus), .only,
                       "a price the user can't get is neither the pick nor the next one")
    }

    func testASecondShopOnlyWhenItSavesTheUsersMinimum() {
        let leaflets = DealsResult(checkedAt: "2026-10-24T06:10:00Z", chains: [DealsChainReport(chain: .lidl, status: .checked), DealsChainReport(chain: .dino, status: .checked)], items: [
            DealsItemResult(query: "masło", offers: [offer(.lidl, 499), offer(.dino, 549)]),
            DealsItemResult(query: "kawa", offers: [offer(.lidl, 2_099, product: "Kawa"), offer(.dino, 1_799, product: "Kawa")]),
        ])
        XCTAssertEqual(BasketSolver.solve(leaflets).savings, Money(minor: 50), "Dino alone 23,48; Lidl's butter and Dino's coffee 22,98")
        XCTAssertNotNil(BasketSolver.solve(leaflets, minimumSaving: 50).bestPair)
        XCTAssertNil(BasketSolver.solve(leaflets, minimumSaving: 51).bestPair, "less than the user's minimum: one shop")
        let more = DealsResult(checkedAt: "x", chains: leaflets.chains, items: leaflets.items + [
            DealsItemResult(query: "cukier", offers: [offer(.dino, 399, product: "Cukier")]), DealsItemResult(query: "chleb", offers: [offer(.lidl, 299, product: "Chleb")]),
        ])
        XCTAssertNotNil(BasketSolver.solve(more, minimumSaving: 10_000).bestPair, "more items is always worth saying")
    }

    func testTheStartDayReminder() {
        let later = offer(.biedronka, 499, product: "Masło Extra 82% 200 g", from: "2026-10-30")
        XCTAssertTrue(DealStartReminder.canRemind(later, today: DealDay(rawValue: "2026-10-28")))
        XCTAssertFalse(DealStartReminder.canRemind(later, today: DealDay(rawValue: "2026-10-30")), "already on")
        XCTAssertFalse(DealStartReminder.canRemind(offer(.lidl, 499), today: DealDay(rawValue: "2026-10-28")), "no start day printed")
        let id = DealStartReminder.id(later)!
        XCTAssertTrue(id.hasPrefix("doddy.deal-start.2026-10-30."))
        XCTAssertEqual(id, DealStartReminder.id(later), "the same offer, the same reminder")
        XCTAssertNotEqual(id, DealStartReminder.id(offer(.biedronka, 549, product: "Masło Extra 82% 200 g", from: "2026-10-30")))
        XCTAssertTrue(DealStartReminder.isDealStart(notificationID: id))
        XCTAssertEqual(DealStartReminder.body(later, .polish), "Masło Extra 82% 200 g, Biedronka: 4,99\u{00A0}zł (cena z gazetki, w sklepie może być inna).")
        XCTAssertEqual(DealStartReminder.title(.english), "On offer from today")
        XCTAssertEqual(DoddyNotificationKind.dealStart.urgency, .active)
    }
}
