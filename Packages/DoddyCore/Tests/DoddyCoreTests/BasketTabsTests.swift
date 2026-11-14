@testable import DoddyCore
import XCTest

/// The leaflet answer's three tabs (decision 2026-11-13-shopping-one-field): one shop, two shops only when the
/// solver offers a pair, and each item separately with the other shops in one line. Every amount is the solver's.
final class BasketTabsTests: XCTestCase {
    private func fixture() throws -> DealsResult {
        let object = try Fixtures.json("deals_search_v1.json")
        let response = try JSONSerialization.data(withJSONObject: try XCTUnwrap(object["response"]))
        return try JSONDecoder().decode(DealsResult.self, from: response)
    }

    private func offer(_ chain: DealsChain, _ minor: Int, check: Bool = false, product: String? = nil) -> DealOffer {
        DealOffer(chain: chain, product: product ?? "\(chain.rawValue) \(minor)", price: Money(minor: minor),
                  source: .init(url: "https://\(chain.rawValue).example"), check: check)
    }

    private func result(_ chains: [DealsChain], _ items: [(String, [DealOffer])]) -> DealsResult {
        DealsResult(
            checkedAt: "2026-11-13T08:00:00.000Z",
            chains: chains.map { DealsChainReport(chain: $0, status: .checked) },
            items: items.map { DealsItemResult(query: $0.0, offers: $0.1) })
    }

    func testTheFixturesTabsAreTheSolversPlans() throws {
        let answer = try fixture()
        let tabs = BasketTabs.make(answer)
        let basket = BasketSolver.solve(answer)
        XCTAssertEqual(tabs.oneShop, basket.bestSingleChain)
        XCTAssertEqual(tabs.twoShops, basket.bestPair)
        XCTAssertEqual(tabs.everything, basket.everythingCheapest)
        XCTAssertEqual(tabs.tabs, [.oneShop, .twoShops, .eachItem], "Lidl + Dino cover one more item than Lidl alone")
        XCTAssertEqual(tabs.firstTab, .oneShop)
        XCTAssertNil(tabs.noSecondShop)
        XCTAssertEqual(tabs.oneShop?.missing, ["kawa mielona"])

        XCTAssertEqual(tabs.eachItem.map(\.query), ["masło", "pieluchy rozmiar 4", "kawa mielona"])
        let butter = tabs.eachItem[0]
        XCTAssertEqual(butter.cheapest?.chain, .biedronka)
        XCTAssertEqual(butter.cheapest?.total, Money(minor: 499))
        XCTAssertEqual(butter.others.map(\.chain), [.lidl])
        XCTAssertEqual(butter.othersText(.polish), "Lidl 5,49\u{00A0}zł (sprawdź)", "Lidl's butter couldn't be confirmed")
        XCTAssertEqual(butter.othersText(.english), "Lidl PLN 5.49 (check)")
        XCTAssertNil(tabs.eachItem[1].othersText(.polish), "only Lidl has the nappies")
        XCTAssertEqual(tabs.eachItem[2].others, [], "Dino's two coffees are one shop: its cheaper line only")
    }

    func testEachItemsFirstLinesAreEverythingAtItsCheapest() throws {
        let leaflets = result([.biedronka, .lidl, .dino], [
            ("masło", [offer(.biedronka, 499), offer(.lidl, 549), offer(.dino, 600)]),
            ("kawa", [offer(.biedronka, 2_299), offer(.lidl, 1_899), offer(.dino, 2_000), offer(.lidl, 1_950)]),
            ("mleko", [offer(.biedronka, 300), offer(.lidl, 320), offer(.dino, 280)]),
        ])
        let tabs = BasketTabs.make(leaflets)
        let everything = try XCTUnwrap(tabs.everything)
        XCTAssertEqual(tabs.eachItem.compactMap(\.cheapest), everything.lines)
        XCTAssertEqual(tabs.eachItem[1].others.map(\.chain), [.dino, .biedronka], "cheapest first, one line per shop")
        XCTAssertEqual(tabs.eachItem[1].others.map(\.total.minor), [2_000, 2_299])
        XCTAssertEqual(tabs.eachItem[2].othersText(.polish), "Biedronka 3,00\u{00A0}zł · Lidl 3,20\u{00A0}zł")
        XCTAssertEqual(tabs.savings, Money(minor: (549 + 1_899 + 320) - (499 + 1_899 + 300)))
    }

    func testNoSecondShopSaysWhy() {
        // One shop 27,68 (Lidl); Biedronka + Lidl 26,98: a saving of 0,70.
        let leaflets = result([.biedronka, .lidl], [
            ("masło", [offer(.biedronka, 499), offer(.lidl, 549)]),
            ("kawa", [offer(.biedronka, 2_299), offer(.lidl, 1_899)]),
            ("mleko", [offer(.biedronka, 300), offer(.lidl, 320)]),
        ])
        XCTAssertNotNil(BasketTabs.make(leaflets).twoShops, "any saving counts with no minimum")
        let held = BasketTabs.make(leaflets, minimumSaving: 500)
        XCTAssertNil(held.twoShops)
        XCTAssertEqual(held.tabs, [.oneShop, .eachItem])
        XCTAssertEqual(held.noSecondShop, .savesTooLittle(saving: Money(minor: 70), minimum: Money(minor: 500)))

        let dinoAlone = result([.biedronka, .dino], [
            ("a", [offer(.biedronka, 500), offer(.dino, 500)]),
            ("b", [offer(.dino, 500)]),
        ])
        XCTAssertEqual(BasketTabs.make(dinoAlone, minimumSaving: 1_000).noSecondShop, .savesNothing)
        XCTAssertEqual(BasketTabs.make(dinoAlone).noSecondShop, .savesNothing)
    }

    func testOneItemIsItsRowOnly() {
        let tabs = BasketTabs.make(result([.biedronka, .lidl], [("mleko", [offer(.biedronka, 300), offer(.lidl, 280)])]))
        XCTAssertEqual(tabs.tabs, [.eachItem])
        XCTAssertNil(tabs.noSecondShop, "one item has no second shop to talk about")
        XCTAssertEqual(tabs.eachItem.first?.cheapest?.chain, .lidl)
        XCTAssertEqual(tabs.eachItem.first?.othersText(.english), "Biedronka PLN 3.00")
    }

    func testNothingCountedLeavesOnlyTheRows() {
        let tabs = BasketTabs.make(result([.biedronka], [("szafran", []), ("wanilia", [])]))
        XCTAssertEqual(tabs.tabs, [.eachItem])
        XCTAssertNil(tabs.oneShop)
        XCTAssertTrue(tabs.eachItem.allSatisfy { $0.cheapest == nil && $0.others.isEmpty })
        XCTAssertEqual(BasketTabs.make(result([], [])).tabs, [])
    }

    func testOffersTheUserCantGetArentInAnyTab() {
        let app = DealOffer(chain: .biedronka, product: "Masło z aplikacją", price: Money(minor: 399),
                            conditions: ["z aplikacją Moja Biedronka"], source: .init(url: "https://biedronka.example"),
                            check: false, flags: [.app])
        let leaflets = result([.biedronka, .lidl], [("masło", [app, offer(.lidl, 549)]), ("mleko", [offer(.lidl, 300)])])
        let programs = DealsPrograms(notUsed: [.mojaBiedronka])
        let tabs = BasketTabs.make(leaflets, programs: programs)
        XCTAssertEqual(tabs.eachItem[0].cheapest?.chain, .lidl)
        XCTAssertEqual(tabs.eachItem[0].others, [], "the app price isn't counted, so it isn't 'another shop' either")
    }

    func testALowerBoundSaysAtLeast() {
        let limited = DealOffer(chain: .dino, product: "Kawa", price: Money(minor: 1_000), source: .init(url: "https://dino.example"),
                                check: false, limit: 1)
        let leaflets = result([.lidl, .dino], [("kawa", [offer(.lidl, 900), limited])])
        let tabs = BasketTabs.make(leaflets, quantities: [ListQuantity(amount: 3, unit: nil)])
        XCTAssertEqual(tabs.eachItem[0].cheapest?.chain, .lidl)
        XCTAssertEqual(tabs.eachItem[0].othersText(.english), "Dino at least PLN 30.00")
        XCTAssertEqual(tabs.eachItem[0].othersText(.polish), "Dino co najmniej 30,00\u{00A0}zł")
    }

    // MARK: Narrowing to a kind

    func testNarrowingKeepsOnlyThePickedKind() {
        let item = DealsItemResult(query: "kawa", offers: [
            offer(.biedronka, 1_299, product: "Kawa mielona 250 g"),
            offer(.lidl, 999, product: "Kawa rozpuszczalna 100 g"),
            offer(.dino, 1_599, product: "Kawa mielona 500 g"),
        ])
        let answer = DealsResult(checkedAt: "x", chains: [], items: [item, DealsItemResult(query: "mleko", offers: [offer(.lidl, 300)])])
        let narrowed = answer.narrowed(to: [0: "mielona"])
        XCTAssertEqual(narrowed.items[0].offers.map(\.chain), [.biedronka, .dino])
        XCTAssertEqual(narrowed.items[1], answer.items[1])
        XCTAssertEqual(BasketTabs.make(narrowed).eachItem[0].cheapest?.chain, .biedronka, "instant coffee isn't counted")
        XCTAssertEqual(answer.narrowed(to: [:]), answer)
        XCTAssertEqual(answer.narrowed(to: [0: ""]), answer)
        XCTAssertEqual(answer.narrowed(to: [0: "kapsułki"]), answer, "not one of its kinds")
        XCTAssertEqual(answer.narrowed(to: [9: "mielona"]), answer)
    }
}
