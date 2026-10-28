@testable import DoddyCore
import XCTest

/// The basket (SHOPPING.md section 3): one shop, two shops, every item at its cheapest, summed in
/// integer grosze by code, with the coverage, the conditions and "needs checking" carried along,
/// and the same answer for the same leaflets every time.
final class BasketSolverTests: XCTestCase {
    private func fixture() throws -> DealsResult {
        let object = try Fixtures.json("deals_search_v1.json")
        let response = try JSONSerialization.data(withJSONObject: try XCTUnwrap(object["response"]))
        return try JSONDecoder().decode(DealsResult.self, from: response)
    }

    private func offer(_ chain: DealsChain, _ minor: Int, check: Bool = false, conditions: [String] = [], product: String? = nil,
                       currency: String = "PLN") -> DealOffer {
        DealOffer(chain: chain, product: product ?? "\(chain.rawValue) \(minor)", price: Money(minor: minor, currency: currency),
                  conditions: conditions, source: .init(url: "https://\(chain.rawValue).example"), check: check)
    }

    private func result(_ chains: [DealsChain], _ items: [(String, [DealOffer])]) -> DealsResult {
        DealsResult(
            checkedAt: "2026-10-24T06:10:00.000Z",
            chains: chains.map { DealsChainReport(chain: $0, status: .checked) },
            items: items.map { DealsItemResult(query: $0.0, offers: $0.1) })
    }

    // MARK: Best value per item

    private func sized(_ chain: DealsChain, _ minor: Int, perUnit: Int?, _ per: DealOffer.UnitPer = .kg, check: Bool = false) -> DealOffer {
        DealOffer(chain: chain, product: "\(chain.rawValue) \(minor)", price: Money(minor: minor),
                  unitPrice: perUnit.map { DealOffer.UnitPrice(minor: $0, per: per) }, source: .init(url: "https://\(chain.rawValue).example"), check: check)
    }

    func testBestValueIsTheLowestPricePerKgNotTheCheapestPack() {
        let offers = [sized(.biedronka, 499, perUnit: 2_495), sized(.lidl, 1_999, perUnit: 1_999), sized(.dino, 449, perUnit: nil)]
        XCTAssertEqual(BasketSolver.bestValue(offers)?.chain, .lidl, "the kilo pack at 19,99 zł/kg beats 200 g at 24,95 zł/kg")
        XCTAssertEqual(BasketSolver.bestValueIndex(offers)?.per, .kg)
        XCTAssertEqual(BasketSolver.cheapest(offers)?.chain, .dino, "the basket still buys the cheapest pack")
    }

    func testAPackWithoutASizeIsNeverTheBestValueWhileOneWithASizeIsThere() {
        let offers = [sized(.dino, 199, perUnit: nil), sized(.lidl, 549, perUnit: 2_745)]
        XCTAssertEqual(BasketSolver.bestValue(offers)?.chain, .lidl)
    }

    func testWithoutUnitPricesBestValueIsTheCheapestPack() {
        let offers = [sized(.biedronka, 599, perUnit: nil), sized(.lidl, 549, perUnit: nil)]
        XCTAssertEqual(BasketSolver.bestValue(offers)?.chain, .lidl)
        XCTAssertNil(BasketSolver.bestValueIndex(offers)?.per, "no unit was compared")
    }

    func testBestValueComparesInTheUnitMostOffersHaveAndBreaksTiesLikeTheBasket() {
        let mixed = [sized(.biedronka, 999, perUnit: 90, .szt), sized(.lidl, 1_200, perUnit: 2_000), sized(.dino, 1_100, perUnit: 2_200)]
        XCTAssertEqual(BasketSolver.bestValue(mixed)?.chain, .lidl, "two offers per kg, one per piece: compared per kg")
        let tie = [sized(.lidl, 500, perUnit: 2_500, check: true), sized(.dino, 500, perUnit: 2_500)]
        XCTAssertEqual(BasketSolver.bestValue(tie)?.chain, .dino, "same price per kg and pack: the confirmed one")
        XCTAssertNil(BasketSolver.bestValue([]))
        XCTAssertNil(BasketSolver.bestValue([offer(.lidl, 500, currency: "EUR")]), "only PLN counts")
    }

    // MARK: The fixture

    func testTheFixturesBasket() throws {
        let basket = BasketSolver.solve(try fixture())
        // Lidl has butter (5,49, needs checking) and nappies (44,99): 2 of 3, the most of any shop.
        let single = try XCTUnwrap(basket.bestSingleChain)
        XCTAssertEqual(single.chains, [.lidl])
        XCTAssertEqual(single.covered, 2)
        XCTAssertEqual(single.itemCount, 3)
        XCTAssertEqual(single.coverage(.polish), "2 z 3")
        XCTAssertEqual(single.coverage(.english), "2 of 3")
        XCTAssertEqual(single.total, Money(minor: 549 + 4_499))
        XCTAssertEqual(single.missing, ["kawa mielona"])
        XCTAssertTrue(single.needsChecking, "Lidl's butter couldn't be confirmed")
        XCTAssertEqual(single.lines.map(\.query), ["masło", "pieluchy rozmiar 4"])
        XCTAssertEqual(single.lines[1].conditions, ["z Lidl Plus"])

        // Two shops: Lidl and Dino cover all three; butter only at Lidl in that pair.
        let pair = try XCTUnwrap(basket.bestPair)
        XCTAssertEqual(pair.chains, [.lidl, .dino])
        XCTAssertEqual(pair.covered, 3)
        XCTAssertTrue(pair.coversAll)
        XCTAssertEqual(pair.total, Money(minor: 549 + 4_499 + 1_999))
        XCTAssertNil(basket.savings, "3 items for more money than 2 isn't a saving")

        // Every item at its cheapest: butter at Biedronka (4,99 with the app), nappies at Lidl, coffee at Dino.
        let everything = try XCTUnwrap(basket.everythingCheapest)
        XCTAssertEqual(everything.chains, [.biedronka, .lidl, .dino])
        XCTAssertEqual(everything.lines.map(\.chain), [.biedronka, .lidl, .dino])
        XCTAssertEqual(everything.total, Money(minor: 499 + 4_499 + 1_999))
        XCTAssertEqual(everything.lines[0].conditions, ["z aplikacją Moja Biedronka", "max 4 szt."])
        XCTAssertFalse(everything.needsChecking, "the cheapest butter is the confirmed one")
        XCTAssertEqual(everything.coverage(.polish), "3 z 3")
    }

    func testOnlyTheChainsAsked() throws {
        let basket = BasketSolver.solve(try fixture(), chains: [.biedronka, .dino])
        XCTAssertEqual(basket.bestSingleChain?.chains, [.biedronka], "1 item each: Biedronka's 4,99 is less than Dino's 19,99")
        XCTAssertEqual(basket.bestSingleChain?.total.minor, 499)
        XCTAssertEqual(basket.bestPair?.chains, [.biedronka, .dino])
        XCTAssertEqual(basket.bestPair?.missing, ["pieluchy rozmiar 4"])
        XCTAssertEqual(basket.bestPair?.total.minor, 499 + 1_999)
        XCTAssertEqual(basket.everythingCheapest?.covered, 2)
        XCTAssertFalse(basket.everythingCheapest?.lines.contains { $0.chain == .lidl } ?? true)
    }

    // MARK: Shapes

    func testAnItemNoShopHasIsMissingEverywhere() {
        let leaflets = result([.biedronka, .lidl], [
            ("mleko", [offer(.biedronka, 300), offer(.lidl, 280)]),
            ("szafran", []),
        ])
        let basket = BasketSolver.solve(leaflets)
        XCTAssertEqual(basket.bestSingleChain?.chains, [.lidl])
        XCTAssertEqual(basket.bestSingleChain?.missing, ["szafran"])
        XCTAssertEqual(basket.bestSingleChain?.coverage(.english), "1 of 2")
        XCTAssertNil(basket.bestPair, "a second shop changes nothing: Lidl is cheaper for the one item")
        XCTAssertNil(BasketSolver.solve(leaflets).bestPair?.chains)
        XCTAssertEqual(basket.everythingCheapest?.missing, ["szafran"])
        XCTAssertNil(basket.savings)
    }

    func testOneChainHasNoPair() {
        let leaflets = result([.dino], [("kawa", [offer(.dino, 1_999)]), ("cukier", [offer(.dino, 399)])])
        let basket = BasketSolver.solve(leaflets)
        XCTAssertEqual(basket.bestSingleChain?.chains, [.dino])
        XCTAssertEqual(basket.bestSingleChain?.total.minor, 2_398)
        XCTAssertNil(basket.bestPair)
        XCTAssertEqual(basket.everythingCheapest, basket.bestSingleChain)
    }

    func testNothingFoundHasNoBasket() {
        let basket = BasketSolver.solve(result([.biedronka], [("szafran", [])]))
        XCTAssertNil(basket.bestSingleChain)
        XCTAssertNil(basket.bestPair)
        XCTAssertNil(basket.everythingCheapest)
        XCTAssertNil(basket.savings)
        XCTAssertNil(BasketSolver.solve(result([], [])).bestSingleChain)
    }

    func testThePairsSavingWhenBothCoverTheSame() {
        let leaflets = result([.biedronka, .lidl, .dino], [
            ("masło", [offer(.biedronka, 499), offer(.lidl, 549), offer(.dino, 600)]),
            ("kawa", [offer(.biedronka, 2_299), offer(.lidl, 1_899), offer(.dino, 2_000)]),
            ("mleko", [offer(.biedronka, 300), offer(.lidl, 320), offer(.dino, 280)]),
        ])
        let basket = BasketSolver.solve(leaflets)
        // One shop: Biedronka 30,98, Lidl 27,68, Dino 28,80.
        XCTAssertEqual(basket.bestSingleChain?.chains, [.lidl])
        XCTAssertEqual(basket.bestSingleChain?.total.minor, 549 + 1_899 + 320)
        // Two: Biedronka + Lidl 4,99 + 18,99 + 3,00 = 26,98; Lidl + Dino 5,49 + 18,99 + 2,80 = 27,28.
        XCTAssertEqual(basket.bestPair?.chains, [.biedronka, .lidl])
        XCTAssertEqual(basket.bestPair?.total.minor, 499 + 1_899 + 300)
        XCTAssertEqual(basket.savings, Money(minor: (549 + 1_899 + 320) - (499 + 1_899 + 300)))
        XCTAssertEqual(basket.everythingCheapest?.total.minor, 499 + 1_899 + 280)
        XCTAssertEqual(basket.everythingCheapest?.chains, [.biedronka, .lidl, .dino])
    }

    func testAPairNoBetterThanTheBestSingleShopIsntOffered() {
        // Dino alone has both for 10,00. Biedronka + Lidl is two trips for 12,00, and Biedronka +
        // Dino costs the same 10,00 as Dino alone.
        let leaflets = result([.biedronka, .lidl, .dino], [
            ("a", [offer(.biedronka, 500), offer(.dino, 500)]),
            ("b", [offer(.lidl, 700), offer(.dino, 500)]),
        ])
        let basket = BasketSolver.solve(leaflets)
        XCTAssertEqual(basket.bestSingleChain?.chains, [.dino])
        XCTAssertEqual(basket.bestSingleChain?.total.minor, 1_000)
        XCTAssertNil(basket.bestPair)
        XCTAssertNil(basket.savings)
    }

    func testMoreItemsBeatsALowerTotal() {
        let leaflets = result([.biedronka, .lidl], [
            ("masło", [offer(.biedronka, 100), offer(.lidl, 900)]),
            ("kawa", [offer(.lidl, 900)]),
        ])
        let single = BasketSolver.solve(leaflets).bestSingleChain
        XCTAssertEqual(single?.chains, [.lidl], "2 of 2 for 18,00 beats 1 of 2 for 1,00")
        XCTAssertEqual(single?.total.minor, 1_800)
    }

    // MARK: Ties, deterministic

    func testTiesGoToTheConfirmedOfferThenTheChainOrder() {
        // Same price at both: the confirmed one wins, whatever the order it came in.
        let checked = result([.biedronka, .lidl], [("masło", [offer(.biedronka, 499, check: true), offer(.lidl, 499)])])
        XCTAssertEqual(BasketSolver.solve(checked).everythingCheapest?.lines.first?.chain, .lidl)
        XCTAssertEqual(BasketSolver.solve(checked).bestSingleChain?.chains, [.lidl], "the same total, fewer to check")
        // Same price, both confirmed: the chain the answer lists first.
        let even = result([.lidl, .biedronka], [("masło", [offer(.biedronka, 499), offer(.lidl, 499)])])
        XCTAssertEqual(BasketSolver.solve(even).everythingCheapest?.lines.first?.chain, .lidl)
        XCTAssertEqual(BasketSolver.solve(even).bestSingleChain?.chains, [.lidl])
        XCTAssertNil(BasketSolver.solve(even).bestPair, "the second shop is never used")
        // Two offers in one chain at the same price: the server's first.
        let twice = result([.dino], [("kawa", [offer(.dino, 1_999, product: "first"), offer(.dino, 1_999, product: "second")])])
        XCTAssertEqual(BasketSolver.solve(twice).bestSingleChain?.lines.first?.offer.product, "first")
        // The same answer, the same basket, however often it's solved.
        let leaflets = result([.biedronka, .lidl, .dino, .rossmann], [
            ("a", [offer(.biedronka, 100), offer(.lidl, 100), offer(.dino, 100), offer(.rossmann, 100)]),
            ("b", [offer(.biedronka, 200), offer(.lidl, 200), offer(.dino, 150), offer(.rossmann, 150)]),
        ])
        let first = BasketSolver.solve(leaflets)
        for _ in 0..<20 { XCTAssertEqual(BasketSolver.solve(leaflets), first) }
        XCTAssertEqual(first.bestSingleChain?.chains, [.dino], "Dino and Rossmann tie at 2,50; Dino is listed first")
        XCTAssertNil(first.bestPair, "no pair costs less than Dino alone; a pair that ties is a second trip for nothing")
    }

    func testAChainSeenOnlyInOffersComesAfterTheListedOnes() {
        let aldi = DealsChain(rawValue: "aldi")
        let leaflets = DealsResult(checkedAt: "x", chains: [DealsChainReport(chain: .lidl, status: .checked)],
                                   items: [DealsItemResult(query: "a", offers: [offer(aldi, 100), offer(.lidl, 100)])])
        XCTAssertEqual(BasketSolver.chainOrder(leaflets), [.lidl, aldi])
        XCTAssertEqual(BasketSolver.solve(leaflets).bestSingleChain?.chains, [.lidl])
        XCTAssertEqual(aldi.name, "aldi", "a chain this app doesn't know keeps its own name")
    }

    // MARK: Integer sums

    func testTotalsAreIntegerSumsNotFloatingPoint() {
        // 0,10 + 0,20 is 0,30 exactly; in Double it is 0.30000000000000004.
        XCTAssertNotEqual(0.1 + 0.2, 0.3)
        let small = result([.biedronka], [("a", [offer(.biedronka, 10)]), ("b", [offer(.biedronka, 20)])])
        let total = BasketSolver.solve(small).bestSingleChain?.total
        XCTAssertEqual(total, Money(minor: 30))
        XCTAssertEqual(total?.text(.english), "PLN 0.30")
        // Twelve items at 19,99: 239,88 to the grosz.
        let twelve = result([.dino], (0..<12).map { ("item \($0)", [offer(.dino, 1_999)]) })
        XCTAssertEqual(BasketSolver.solve(twelve).bestSingleChain?.total.minor, 23_988)
        var asDouble = 0.0
        for _ in 0..<12 { asDouble += 19.99 }
        XCTAssertNotEqual(asDouble, 239.88, "why money is never a Double")
    }

    func testOffersThatCantBeSummedArentCounted() {
        let leaflets = result([.biedronka, .lidl], [
            ("masło", [offer(.biedronka, 450, currency: "EUR"), offer(.lidl, 549)]),
            ("kawa", [offer(.biedronka, 0), offer(.lidl, -5), offer(.lidl, BasketSolver.maxPrice + 1)]),
        ])
        let basket = BasketSolver.solve(leaflets)
        XCTAssertEqual(basket.everythingCheapest?.lines.map(\.chain), [.lidl], "another currency, nothing or a negative price isn't summed")
        XCTAssertEqual(basket.everythingCheapest?.missing, ["kawa"])
        XCTAssertEqual(BasketSolver.solve(leaflets, currency: "EUR").bestSingleChain?.total, Money(minor: 450, currency: "EUR"))
    }
}
