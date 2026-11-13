@testable import DoddyCore
import XCTest

/// The Shopping screens at a glance (the look-and-motion pass of 13 Nov 2026): which chip a condition becomes, the
/// one day chip, the plan behind each tab, the savings line, and which leaflets an answer read. No amount is made
/// here; every one is the solver's.
final class ShoppingGlanceTests: XCTestCase {
    private func day(_ text: String) -> DealDay { DealDay(rawValue: text)! }

    private func offer(_ chain: DealsChain, _ minor: Int, conditions: [String] = [], from: String? = nil, to: String? = nil) -> DealOffer {
        DealOffer(chain: chain, product: "\(chain.rawValue) \(minor)", price: Money(minor: minor), conditions: conditions,
                  validFrom: from.map(day), validTo: to.map(day), source: .init(url: "https://\(chain.rawValue).example"))
    }

    private func result(_ chains: [DealsChain], _ items: [(String, [DealOffer])]) -> DealsResult {
        DealsResult(checkedAt: "2026-11-13T08:00:00.000Z",
                    chains: chains.map { DealsChainReport(chain: $0, status: .checked) },
                    items: items.map { DealsItemResult(query: $0.0, offers: $0.1) })
    }

    // MARK: Conditions as chips

    func testEveryConditionTheServerWritesHasItsKind() {
        // The server's own words (conditionText in server/messaging/src/deals/service.ts), Polish then English.
        let cases: [(String, DealChip.Kind)] = [
            ("z aplikacją Moja Biedronka", .app), ("z Lidl Plus", .app), ("z aplikacją Żappka", .app), ("z aplikacją sieci", .app),
            ("with the Moja Biedronka app", .app), ("with Lidl Plus", .app), ("with the chain's app", .app),
            ("z kartą Moja Biedronka", .card), ("z kartą lojalnościową", .card), ("with the Moja Biedronka card", .card),
            ("with a loyalty card", .card),
            ("przy zakupie 2 szt.", .minimum), ("when buying 3", .minimum),
            ("max 2 szt.", .limit), ("max 4 per customer", .limit),
            ("2+1", .multiBuy), ("1 + 1 gratis", .multiBuy), ("druga sztuka za 4,99 zł", .multiBuy),
            ("co druga sztuka −50%", .multiBuy), ("the second for 4,99 zł", .multiBuy), ("every third one −30%", .multiBuy),
            ("plus kaucja za opakowanie", .deposit), ("plus a container deposit", .deposit),
            ("do wyczerpania zapasów", .stock), ("while stocks last", .stock),
            ("w wybranych sklepach", .someShops), ("in selected stores", .someShops),
            ("tylko online", .other), ("", .other),
        ]
        for (words, kind) in cases {
            XCTAssertEqual(DealChip.kind(of: words), kind, words)
        }
    }

    func testChipsKeepTheServersWordsInOrderOnceEach() {
        let line = offer(.biedronka, 499, conditions: ["z aplikacją Moja Biedronka", " 2+1 ", "Z aplikacją Moja Biedronka", "  "])
        let chips = DealChip.chips(for: line, today: nil)
        XCTAssertEqual(chips, [DealChip(kind: .app, text: "z aplikacją Moja Biedronka"), DealChip(kind: .multiBuy, text: "2+1")])
        XCTAssertFalse(chips.contains(where: \.isDay), "no printed last day, no day chip")
    }

    func testOneDayChipFollowsTheChecklist() {
        let friday = day("2026-11-13")
        // Until Thursday: the printed last day.
        XCTAssertEqual(DealChip.chips(for: offer(.lidl, 300, to: "2026-11-19"), today: friday),
                       [DealChip(kind: .until, day: day("2026-11-19"))])
        // Its last day is today.
        XCTAssertEqual(DealChip.chips(for: offer(.lidl, 300, to: "2026-11-13"), today: friday), [DealChip(kind: .lastDay)])
        // Not on until Monday: that, and not its last day.
        XCTAssertEqual(DealChip.chips(for: offer(.lidl, 300, from: "2026-11-16", to: "2026-11-21"), today: friday),
                       [DealChip(kind: .startsOn, day: day("2026-11-16"))])
        // Its last day is a closed Sunday: buy by Saturday.
        XCTAssertEqual(DealChip.chips(for: offer(.lidl, 300, to: "2026-11-15"), today: friday),
                       [DealChip(kind: .buyBy, day: day("2026-11-14"))])
        // On that Saturday, it is the last day.
        XCTAssertEqual(DealChip.chips(for: offer(.lidl, 300, to: "2026-11-15"), today: day("2026-11-14")), [DealChip(kind: .lastDay)])
        // Over already: no chip says anything about it.
        XCTAssertEqual(DealChip.chips(for: offer(.lidl, 300, to: "2026-11-10"), today: friday), [])
        // With no calendar, the printed last day as printed.
        XCTAssertEqual(DealChip.chips(for: offer(.lidl, 300, to: "2026-11-10"), today: nil),
                       [DealChip(kind: .until, day: day("2026-11-10"))])
        // The conditions first, then the day.
        XCTAssertEqual(DealChip.chips(for: offer(.lidl, 300, conditions: ["z Lidl Plus"], to: "2026-11-19"), today: friday).map(\.kind),
                       [.app, .until])
    }

    // MARK: The tabs

    func testEachTabsPlanIsTheSolversPlan() {
        let leaflets = result([.biedronka, .lidl, .dino], [
            ("masło", [offer(.biedronka, 499), offer(.lidl, 549), offer(.dino, 600)]),
            ("kawa", [offer(.biedronka, 2_299), offer(.lidl, 1_899), offer(.dino, 2_000)]),
            ("mleko", [offer(.biedronka, 300), offer(.lidl, 320), offer(.dino, 280)]),
        ])
        let tabs = BasketTabs.make(leaflets)
        XCTAssertEqual(tabs.plan(for: .oneShop), tabs.oneShop)
        XCTAssertEqual(tabs.plan(for: .twoShops), tabs.twoShops)
        XCTAssertEqual(tabs.plan(for: .eachItem), tabs.everything)
        XCTAssertEqual(tabs.plan(for: .eachItem)?.total, Money(minor: 499 + 1_899 + 280))
        XCTAssertFalse(tabs.plan(for: .oneShop)?.totalIsLowerBound ?? true)
    }

    func testTheSavingsLineIsTheSolversSaving() {
        // One shop: Lidl 27,68. Two: Biedronka + Lidl 26,98. A saving of 0,70 on the same items.
        let leaflets = result([.biedronka, .lidl], [
            ("masło", [offer(.biedronka, 499), offer(.lidl, 549)]),
            ("kawa", [offer(.biedronka, 2_299), offer(.lidl, 1_899)]),
            ("mleko", [offer(.biedronka, 300), offer(.lidl, 320)]),
        ])
        let tabs = BasketTabs.make(leaflets)
        XCTAssertEqual(tabs.secondShopGain, .saves(Money(minor: 70)))
        XCTAssertEqual(tabs.savingsLine(.polish), "Oszczędzasz 0,70\u{00A0}zł w dwóch sklepach")
        XCTAssertEqual(tabs.savingsLine(.english), "You save PLN 0.70 in two shops")

        // Held back by the person's minimum: no pair, no line.
        let held = BasketTabs.make(leaflets, minimumSaving: 500)
        XCTAssertNil(held.secondShopGain)
        XCTAssertNil(held.savingsLine(.polish))
    }

    func testMoreItemsIsAGainButNotASaving() {
        // Lidl has two of three items; Lidl + Dino have all three.
        let leaflets = result([.lidl, .dino], [
            ("masło", [offer(.lidl, 549)]),
            ("pieluchy", [offer(.lidl, 3_999)]),
            ("kawa", [offer(.dino, 1_999)]),
        ])
        let tabs = BasketTabs.make(leaflets)
        XCTAssertEqual(tabs.secondShopGain, .moreItems(pair: 3, single: 2))
        XCTAssertNil(tabs.savingsLine(.polish), "more items for more money isn't a saving")
    }

    func testALowerBoundTotalIsMarked() {
        let limited = DealOffer(chain: .dino, product: "Kawa", price: Money(minor: 1_000), source: .init(url: "https://dino.example"),
                                limit: 1)
        let tabs = BasketTabs.make(result([.dino], [("kawa", [limited])]), quantities: [ListQuantity(amount: 3, unit: nil)])
        XCTAssertEqual(tabs.plan(for: .eachItem)?.totalIsLowerBound, true)
    }

    // MARK: What was read

    func testWhichLeafletsWereRead() {
        let answer = DealsResult(checkedAt: "x", chains: [
            DealsChainReport(chain: .biedronka, status: .checked),
            DealsChainReport(chain: .lidl, status: .noMatch),
            DealsChainReport(chain: .aldi, status: .blocked),
            DealsChainReport(chain: .dino, status: .failed),
            DealsChainReport(chain: .kaufland, status: .linkOnly),
            DealsChainReport(chain: .zabka, status: .unknown),
        ], items: [])
        XCTAssertEqual(answer.chainsRead, [.biedronka, .lidl], "a leaflet with nothing that matched was still read")
        XCTAssertEqual(answer.chainsNotRead, [.aldi, .dino, .kaufland, .zabka], "a status the app doesn't know is never read as read")
        XCTAssertEqual(answer.chainsRead.count, answer.readChainCount)
    }

    func testFoundNothingOnlyWhenEveryItemIsEmpty() {
        XCTAssertTrue(result([.lidl], [("szafran", []), ("wanilia", [])]).foundNothing)
        XCTAssertFalse(result([.lidl], [("szafran", []), ("mleko", [offer(.lidl, 300)])]).foundNothing)
        XCTAssertFalse(DealsResult(checkedAt: "x", chains: [], items: []).foundNothing, "no items: not an empty answer")
        let promotion = DealPromotion(chain: .lidl, text: "Wszystkie przyprawy", mechanic: "−30%", source: .init(url: "https://lidl.example"))
        XCTAssertFalse(DealsResult(checkedAt: "x", chains: [], items: [DealsItemResult(query: "szafran", offers: [], promotions: [promotion])]).foundNothing)
        let similar = DealsResult(checkedAt: "x", chains: [], items: [DealsItemResult(query: "kawa", offers: [], similar: [offer(.lidl, 999)])])
        XCTAssertFalse(similar.foundNothing, "a similar product is something to show")
    }

    func testTheLeafletsAskedForAreTheRequestsReadChains() {
        let request = DealsRequest(items: ["mleko"], chains: [.biedronka, .kaufland, .lidl])
        XCTAssertEqual(request.leafletsAsked, [.biedronka, .lidl], "Kaufland is a link only")
        XCTAssertEqual(DealsRequest(items: ["mleko"]).leafletsAsked, DealsChain.defaultRead)
    }
}
