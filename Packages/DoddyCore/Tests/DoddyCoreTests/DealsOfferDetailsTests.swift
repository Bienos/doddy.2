@testable import DoddyCore
import XCTest

/// ADR-661 in the app: what an offer carries beyond its price (flags, the price per piece under a
/// multi-buy, the real cut, the limit) and the promotions printed without a price; the basket costed
/// for the list's quantities and the user's programs; trading Sundays and holidays; "Przed wyjściem";
/// and the kinds an item's offers span. All of it code, from the answer; nothing guessed.
final class DealsOfferDetailsTests: XCTestCase {
    private func fixture() throws -> DealsResult {
        let object = try Fixtures.json("deals_search_v1.json")
        let response = try JSONSerialization.data(withJSONObject: try XCTUnwrap(object["response"]))
        return try JSONDecoder().decode(DealsResult.self, from: response)
    }

    private func day(_ text: String) -> DealDay { DealDay(rawValue: text)! }

    private func offer(_ minor: Int, product: String? = nil, regular: Int? = nil, flags: [DealOffer.Flag] = [],
                       effective: (Int, Int)? = nil, limit: Int? = nil, to: String? = nil) -> DealOffer {
        offer(.lidl, minor, product: product, regular: regular, flags: flags, effective: effective, limit: limit, to: to)
    }

    private func offer(_ chain: DealsChain, _ minor: Int, product: String? = nil, regular: Int? = nil, flags: [DealOffer.Flag] = [],
                       effective: (Int, Int)? = nil, limit: Int? = nil, size: DealOffer.Size? = nil,
                       from: String? = nil, to: String? = nil) -> DealOffer {
        DealOffer(chain: chain, product: product ?? "\(chain.rawValue) \(minor)", price: Money(minor: minor), size: size,
                  regularPrice: regular.map { Money(minor: $0) }, validFrom: from.flatMap(DealDay.init(rawValue:)),
                  validTo: to.flatMap(DealDay.init(rawValue:)), source: .init(url: "https://\(chain.rawValue).example"),
                  flags: flags, effective: effective.map { DealOffer.Effective(price: Money(minor: $0.0), quantity: $0.1) }, limit: limit)
    }

    private func result(_ items: [(String, [DealOffer])]) -> DealsResult {
        let chains = Array(Set(items.flatMap { $0.1.map(\.chain) })).sorted { $0.rawValue < $1.rawValue }
        return DealsResult(checkedAt: "2026-10-24T06:10:00.000Z", chains: chains.map { DealsChainReport(chain: $0, status: .checked) },
                           items: items.map { DealsItemResult(query: $0.0, offers: $0.1) })
    }

    // MARK: Decoding

    func testTheNewFieldsDecodeFromTheFixture() throws {
        let result = try fixture()
        let butter = result.items[0].offers[0]
        XCTAssertEqual(butter.flags, [.app])
        XCTAssertEqual(butter.limit, 4)
        XCTAssertTrue(butter.needsProgram)
        XCTAssertNil(butter.effective)
        XCTAssertEqual(result.items[1].offers[0].flags, [.app])
        let coffee = result.items[2].offers[0]
        XCTAssertEqual(coffee.cut, 13)
        XCTAssertEqual(coffee.lowest30d, Money(minor: 2_299))
        let lavazza = result.items[2].offers[1]
        XCTAssertEqual(lavazza.effective, DealOffer.Effective(price: Money(minor: 1_733), quantity: 3, unitPrice: .init(minor: 6_932, per: .kg)))
        XCTAssertTrue(lavazza.isMultiBuy)
        XCTAssertFalse(lavazza.needsMinimumQuantity)
        XCTAssertEqual(result.items[2].promotions, [DealPromotion(
            chain: .biedronka, text: "Wszystkie kawy mielone Jacobs", mechanic: "1+1", conditions: ["z aplikacją Moja Biedronka", "max 2 szt."],
            flags: [.app], validFrom: day("2026-10-23"), validTo: day("2026-10-29"),
            source: .init(url: "https://www.biedronka.pl/pl/press,id,example,title,gazetka-od-czwartku", page: 9))])
        XCTAssertEqual(result.items[0].promotions, [])
    }

    func testValuesThatDontMakeSenseAreDroppedNeverTrusted() throws {
        func decode(_ extra: String) throws -> DealOffer {
            try JSONDecoder().decode(DealOffer.self, from: Data("""
            {"chain":"lidl","product":"Masło","price":{"minor":500,"currency":"PLN"},"source":{"url":"https://l"},"check":false\(extra)}
            """.utf8))
        }
        let older = try decode("")
        XCTAssertEqual(older.flags, [])
        XCTAssertNil(older.effective)
        XCTAssertNil(older.cut)
        XCTAssertNil(older.limit)
        XCTAssertEqual(try decode(#","flags":["app","loyalty_v2","stock"]"#).flags, [.app, .stock], "a flag this app doesn't know is dropped")
        XCTAssertNil(try decode(#","flags":"app""#).flags.first, "a wrong shape is dropped, not a failed answer")
        let bad = [
            #","effective":{"price":{"minor":400,"currency":"PLN"},"quantity":1}"#, // one piece isn't a mechanic
            #","effective":{"price":{"minor":600,"currency":"PLN"},"quantity":2}"#, // dearer than the price
            #","effective":{"price":{"minor":400,"currency":"EUR"},"quantity":2}"#,
            #","effective":{"price":{"minor":0,"currency":"PLN"},"quantity":2}"#,
        ]
        for json in bad { XCTAssertNil(try decode(json).effective, json) }
        XCTAssertNil(try decode(#","cut":{"percent":0}"#).cut)
        XCTAssertNil(try decode(#","cut":{"percent":100}"#).cut)
        XCTAssertNil(try decode(#","cut":13"#).cut)
        XCTAssertEqual(try decode(#","cut":{"percent":13}"#).cut, 13)
        XCTAssertNil(try decode(#","limit":0"#).limit)
        XCTAssertEqual(try decode(#","limit":4"#).limit, 4)
        let item = try JSONDecoder().decode(DealsItemResult.self, from: Data(#"{"query":"kawa","offers":[],"promotions":[{"chain":"lidl"}]}"#.utf8))
        XCTAssertEqual(item.promotions, [], "a promotion missing its fields is dropped with the rest")
    }

    // MARK: Costing a line

    func testAMultiBuyCostsWholeGroupsAndSaysWhenTheNextPieceIsFree() {
        let twoPlusOne = offer(600, effective: (400, 3)) // 2+1 at 6,00: 4,00 each when taking 3
        XCTAssertEqual(BasketSolver.cost(twoPlusOne, quantity: 1), LineCost(quantity: 1, total: Money(minor: 600)))
        XCTAssertEqual(BasketSolver.cost(twoPlusOne, quantity: 2), LineCost(quantity: 2, total: Money(minor: 1_200), notes: [.takeMore(to: 3)]))
        XCTAssertEqual(BasketSolver.cost(twoPlusOne, quantity: 3), LineCost(quantity: 3, total: Money(minor: 1_200), notes: [.groups(1, size: 3)]))
        XCTAssertEqual(BasketSolver.cost(twoPlusOne, quantity: 4), LineCost(quantity: 4, total: Money(minor: 1_800), notes: [.groups(1, size: 3)]))
        // 1+1 at 9,99: the server's 5,00 each is rounded up, so the second piece is "free" within a grosz.
        XCTAssertEqual(BasketSolver.cost(offer(999, effective: (500, 2)), quantity: 1).notes, [.takeMore(to: 2)])
        // A second for 1 zł: taking two costs more than one, so nothing is suggested.
        XCTAssertEqual(BasketSolver.cost(offer(999, effective: (550, 2)), quantity: 1).notes, [])
    }

    func testAMinimumQuantityIsCountedAndSaid() {
        let fromTwo = offer(559, effective: (559, 2))
        XCTAssertTrue(fromTwo.needsMinimumQuantity)
        XCTAssertEqual(BasketSolver.cost(fromTwo, quantity: 1), LineCost(quantity: 2, total: Money(minor: 1_118), notes: [.raisedToMinimum(2)]))
        XCTAssertEqual(BasketSolver.cost(fromTwo, quantity: 3), LineCost(quantity: 3, total: Money(minor: 1_677)))
    }

    func testBeyondTheLimitTheRestIsAtTheRegularPriceOrSaidToBeUnknown() {
        let limited = offer(499, regular: 649, limit: 4)
        XCTAssertEqual(BasketSolver.cost(limited, quantity: 6), LineCost(quantity: 6, total: Money(minor: 4 * 499 + 2 * 649), notes: [.overLimit(4)]))
        let unpriced = BasketSolver.cost(offer(499, limit: 4), quantity: 6)
        XCTAssertEqual(unpriced, LineCost(quantity: 6, total: Money(minor: 6 * 499), notes: [.overLimitUnpriced(4)]))
        XCTAssertTrue(unpriced.isLowerBound)
        let groupsAndLimit = BasketSolver.cost(offer(600, regular: 800, effective: (400, 3), limit: 3), quantity: 6)
        XCTAssertEqual(groupsAndLimit.total, Money(minor: 1_200 + 3 * 800))
        XCTAssertEqual(BasketSolver.cost(offer(499), quantity: 500).quantity, BasketSolver.maxPieces)
        XCTAssertEqual(BasketSolver.cost(offer(499), quantity: 0).quantity, 1)
    }

    func testTheListsQuantityBecomesPacks() {
        func pieces(_ words: String, _ size: DealOffer.Size?) -> Int {
            BasketSolver.pieces(for: ListItemWords.read(words).quantity, size: size)
        }
        XCTAssertEqual(pieces("mleko", nil), 1)
        XCTAssertEqual(pieces("3 jajka", nil), 3)
        XCTAssertEqual(pieces("2 op. masła", .init(value: 200, unit: .g)), 2)
        XCTAssertEqual(pieces("2 kg mąki", .init(value: 1, unit: .kg)), 2)
        XCTAssertEqual(pieces("500 g masła", .init(value: 200, unit: .g)), 3, "2,5 packs is 3")
        XCTAssertEqual(pieces("1,5 l mleka", .init(value: 1, unit: .l)), 2)
        XCTAssertEqual(pieces("2 l mleka", .init(value: 500, unit: .g)), 1, "litres of a pack sized in grams aren't converted")
        XCTAssertEqual(pieces("2 kg mąki", nil), 1, "no size read: one")
    }

    func testTheBasketBuysTheQuantitiesAndCountsOnlyPricesTheUserCanGet() {
        let leaflets = result([("cukier", [offer(.biedronka, 600, effective: (400, 3)), offer(.lidl, 450)])])
        XCTAssertEqual(BasketSolver.solve(leaflets).everythingCheapest?.lines.first?.chain, .lidl, "one: 4,50 beats 6,00")
        let three = BasketSolver.solve(leaflets, quantities: [.pieces(3)]).everythingCheapest
        XCTAssertEqual(three?.lines.first?.chain, .biedronka, "three: 12,00 beats 13,50")
        XCTAssertEqual(three?.total, Money(minor: 1_200))
        XCTAssertEqual(three?.lines.first?.quantity, 3)

        let app = result([("masło", [offer(.lidl, 449, flags: [.app]), offer(.dino, 499, flags: [.app]), offer(.biedronka, 519)])])
        XCTAssertEqual(BasketSolver.solve(app).everythingCheapest?.lines.first?.chain, .lidl)
        let noLidlPlus = DealsPrograms(notUsed: [.lidlPlus])
        XCTAssertEqual(BasketSolver.solve(app, programs: noLidlPlus).everythingCheapest?.lines.first?.chain, .dino,
                       "Dino's app flag counts: Doddy knows no Dino program, so nothing is ruled out on a guess")
        XCTAssertEqual(BasketSolver.bestValue(app.items[0].offers, programs: noLidlPlus)?.chain, .dino)
        XCTAssertNil(BasketSolver.solve(result([("x", [offer(.lidl, 449, flags: [.card])])]), programs: noLidlPlus).bestSingleChain)
    }

    func testANearTieGoesToThePriceAnyoneGets() {
        let kg: (Int) -> DealOffer.UnitPrice = { .init(minor: $0, per: .kg) }
        let plain = DealOffer(chain: .dino, product: "a", price: Money(minor: 500), unitPrice: kg(2_500), source: .init(url: "https://d"), check: false)
        let app = DealOffer(chain: .lidl, product: "b", price: Money(minor: 490), unitPrice: kg(2_450), source: .init(url: "https://l"), check: false, flags: [.app])
        let multi = DealOffer(chain: .biedronka, product: "c", price: Money(minor: 600), unitPrice: kg(3_000), source: .init(url: "https://b"), check: false,
                              effective: .init(price: Money(minor: 400), quantity: 3, unitPrice: kg(2_000)))
        XCTAssertEqual(try XCTUnwrap(BasketSolver.rankValue(app, per: .kg)), 2_572.5, accuracy: 0.001)
        XCTAssertEqual(BasketSolver.bestValue([app, plain]), plain, "24,50 with the app is 25,73 against 25,00 without")
        XCTAssertEqual(BasketSolver.bestValue([app, plain, multi]), multi, "20,00 a kilo at three is still clearly better")
    }

    // MARK: Programs

    func testProgramsAreStoredAsTheUsersOwnChoice() {
        XCTAssertEqual(DealsPrograms.all.stored, "")
        let choice = DealsPrograms.all.setting(.zappka, used: false).setting(.lidlPlus, used: false)
        XCTAssertEqual(choice.stored, "lidl_plus,zappka")
        XCTAssertEqual(DealsPrograms(stored: "zappka, lidl_plus,new_program"), choice, "an identifier this version doesn't know is ignored")
        XCTAssertEqual(choice.setting(.lidlPlus, used: true).notUsed, [.zappka])
        XCTAssertEqual(DealsProgram.of(.biedronka), .mojaBiedronka)
        XCTAssertNil(DealsProgram.of(.dino))
        let lidl = offer(.lidl, 449, flags: [.app])
        XCTAssertEqual(choice.missing(for: lidl), .lidlPlus)
        XCTAssertNil(choice.missing(for: offer(.lidl, 449)), "a price that needs no app")
    }

    // MARK: Shops' days

    func testWeekdaysEasterAndDayArithmetic() {
        XCTAssertEqual(ShoppingCalendar.weekday(day("2026-10-28")), 3)
        XCTAssertEqual(ShoppingCalendar.weekday(day("2000-02-29")), 2)
        XCTAssertEqual(ShoppingCalendar.weekday(day("2199-12-31")), 2)
        XCTAssertEqual(ShoppingCalendar.easter(2025), day("2025-04-20"))
        XCTAssertEqual(ShoppingCalendar.easter(2026), day("2026-04-05"))
        XCTAssertEqual(ShoppingCalendar.easter(2027), day("2027-03-28"))
        XCTAssertEqual(ShoppingCalendar.adding(4, to: day("2026-12-29")), day("2027-01-02"))
        XCTAssertEqual(ShoppingCalendar.adding(-1, to: day("2028-03-01")), day("2028-02-29"))
        XCTAssertEqual(ShoppingCalendar.days(from: day("2026-10-24"), to: day("2026-11-01")), 8)
    }

    func testTradingSundaysHolidaysAndHolySaturday() {
        for sunday in ["2026-01-25", "2026-03-29", "2026-04-26", "2026-06-28", "2026-08-30", "2026-12-06", "2026-12-13", "2026-12-20"] {
            XCTAssertEqual(ShoppingCalendar.kind(day(sunday)), .open, sunday)
        }
        XCTAssertEqual(ShoppingCalendar.kind(day("2026-10-25")), .closedSunday)
        XCTAssertEqual(ShoppingCalendar.kind(day("2026-11-01")), .closedHoliday(.allSaints), "a holiday on a Sunday")
        XCTAssertEqual(ShoppingCalendar.kind(day("2026-11-11")), .closedHoliday(.independenceDay))
        XCTAssertEqual(ShoppingCalendar.kind(day("2026-12-24")), .closedHoliday(.christmasEve))
        XCTAssertEqual(ShoppingCalendar.kind(day("2026-04-06")), .closedHoliday(.easterMonday))
        XCTAssertEqual(ShoppingCalendar.kind(day("2026-06-04")), .closedHoliday(.corpusChristi))
        XCTAssertEqual(ShoppingCalendar.kind(day("2026-05-24")), .closedHoliday(.pentecost))
        XCTAssertEqual(ShoppingCalendar.kind(day("2026-04-04")), .closesEarly(hour: 14))
        XCTAssertEqual(ShoppingCalendar.kind(day("2026-11-02")), .open)
        XCTAssertFalse(ShoppingCalendar.isClosed(day("2026-11-01"), for: .zabka), "owner-run Żabka shops may open")
        XCTAssertEqual(ShoppingCalendar.lastOpenDay(from: day("2026-10-28"), through: day("2026-11-01"), for: .lidl), day("2026-10-31"))
        XCTAssertEqual(ShoppingCalendar.lastOpenDay(from: day("2026-10-28"), through: day("2026-11-01"), for: .zabka), day("2026-11-01"))
        XCTAssertNil(ShoppingCalendar.lastOpenDay(from: day("2026-11-01"), through: day("2026-11-01"), for: .lidl))
        XCTAssertEqual(ShoppingCalendar.closedDays(from: day("2026-12-23"), through: day("2026-12-27"), for: .biedronka),
                       [day("2026-12-24"), day("2026-12-25"), day("2026-12-26"), day("2026-12-27")])
        XCTAssertEqual(ShoppingCalendar.today(ISO8601DateFormatter().date(from: "2026-10-27T23:30:00Z")!), day("2026-10-28"), "Poland is an hour ahead")
    }

    // MARK: Przed wyjściem

    func testTheChecklistSaysWhatTheTillNeeds() throws {
        let basket = BasketSolver.solve(try fixture())
        // Lidl's nappies run until Sunday 25 October, a closed Sunday: on Saturday the 24th that is today.
        let lidl = DealsChecklist.sections(try XCTUnwrap(basket.bestSingleChain), today: day("2026-10-24"))
        XCTAssertEqual(lidl, [DealsChecklistSection(chain: .lidl, entries: [
            DealsChecklistEntry(chain: .lidl, kind: .openApp(.lidlPlus)),
            DealsChecklistEntry(chain: .lidl, product: "Masło ekstra 82% 200 g", kind: .lastDay),
            DealsChecklistEntry(chain: .lidl, product: "Pieluchy rozmiar 4, 50 szt.", kind: .lastDay),
        ])])
        let everything = DealsChecklist.sections(try XCTUnwrap(basket.everythingCheapest), today: day("2026-10-22"))
        XCTAssertEqual(everything.first, DealsChecklistSection(chain: .biedronka, entries: [
            DealsChecklistEntry(chain: .biedronka, kind: .openApp(.mojaBiedronka)),
            DealsChecklistEntry(chain: .biedronka, product: "Masło Extra 82% 200 g", kind: .atMost(4)),
            DealsChecklistEntry(chain: .biedronka, product: "Masło Extra 82% 200 g", kind: .startsOn(day("2026-10-23"))),
        ]))
        XCTAssertEqual(everything[1].entries.last, DealsChecklistEntry(chain: .lidl, product: "Pieluchy rozmiar 4, 50 szt.", kind: .lastOpenDay(day("2026-10-24"))))
    }

    func testTheChecklistsOtherEntries() {
        let o = offer(.biedronka, 600, product: "Woda", flags: [.card, .deposit, .stock, .selectedStores], effective: (400, 3))
        XCTAssertEqual(DealsChecklist.entries(for: o, today: nil).map(\.kind), [.take(3), .deposit, .whileStocksLast, .selectedStores])
        XCTAssertEqual(DealsChecklist.entries(for: offer(559, effective: (559, 2)), today: nil).map(\.kind), [.take(2)])
        let plan = BasketSolver.solve(result([("woda", [o])])).bestSingleChain!
        XCTAssertEqual(DealsChecklist.sections(plan, today: day("2026-10-25")).first?.entries.prefix(2).map(\.kind),
                       [.showCard(.mojaBiedronka), .closedToday(.closedSunday)])
        XCTAssertEqual(DealsChecklist.sections(plan, today: day("2026-04-04")).first?.entries[1].kind, .closesEarlyToday(hour: 14))
        let zabka = BasketSolver.solve(result([("hot dog", [offer(.zabka, 599)])])).bestSingleChain!
        XCTAssertEqual(DealsChecklist.sections(zabka, today: day("2026-10-25")), [], "Żabka isn't called closed")
    }

    // MARK: Kinds

    func testKindsOnlyWhenTheItemDoesntSayAndTheOffersDiffer() {
        let coffees = DealsItemResult(query: "kawa", offers: [
            offer(.lidl, 1_999, product: "Kawa mielona 500 g"), offer(.dino, 2_999, product: "Kawa ziarnista 1 kg"),
            offer(.aldi, 1_599, product: "Kawa rozpuszczalna 200 g"), offer(.biedronka, 1_799, product: "Kawa MIELONA Jacobs"),
            offer(.zabka, 999, product: "Kawa"),
        ])
        XCTAssertEqual(DealsVariants.split(coffees), [
            DealsVariant(label: "mielona", offerIndices: [0, 3]), DealsVariant(label: "ziarnista", offerIndices: [1]),
            DealsVariant(label: "rozpuszczalna", offerIndices: [2]),
        ])
        XCTAssertNil(DealsVariants.split(DealsItemResult(query: "kawa mielona", offers: coffees.offers)), "the item says which")
        XCTAssertNil(DealsVariants.split(DealsItemResult(query: "kawa", offers: [coffees.offers[0], coffees.offers[3]])), "one kind only")
        XCTAssertNil(DealsVariants.split(DealsItemResult(query: "masło", offers: coffees.offers)), "no known group")
        let water = DealsItemResult(query: "woda", offers: [offer(.lidl, 199, product: "Woda niegazowana 1,5 l"), offer(.dino, 179, product: "Woda lekko gazowana")])
        XCTAssertEqual(DealsVariants.split(water)?.map(\.label), ["niegazowana", "gazowana"], "\"niegazowana\" isn't \"gazowana\"")
        let text = DealsResultText.forAgent(result([("kawa", coffees.offers)]))
        XCTAssertTrue(text.contains("The offers for \"kawa\" are of different kinds: mielona (2), ziarnista (1), rozpuszczalna (1). If it matters, ask the user once which they mean; ask nothing else."), text)
    }

    // MARK: What the agent hears

    func testTheAgentHearsTheRealPriceLineAndWhatTheUserCantGet() throws {
        let nbsp = "\u{00A0}"
        let text = DealsResultText.forAgent(try fixture(), programs: DealsPrograms(notUsed: [.lidlPlus]), quantities: [nil, nil, .pieces(3)], today: day("2026-10-21"))
        XCTAssertTrue(text.contains("- \"pieluchy rozmiar 4\": only offers the user can't get · left out: 1 offer needing Lidl Plus, which the user said they don't use"), text)
        XCTAssertTrue(text.contains("not on yet: from 2026-10-23"), "Biedronka's butter starts on Thursday")
        XCTAssertTrue(text.contains("Basket (summed by Doddy's code): one shop: Biedronka, 1 of 3 items, 4,99\(nbsp)zł"), text)
        let coffeeOnly = DealsResultText.forAgent(result([("kawa", [offer(.dino, 2_599, product: "Lavazza 250 g", effective: (1_733, 3), to: "2026-11-01")])]),
                                                  quantities: [.pieces(3)], today: day("2026-10-28"))
        XCTAssertTrue(coffeeOnly.contains("when buying 3: 17,33\(nbsp)zł each (one alone: 25,99\(nbsp)zł) · until 2026-11-01 (shops are closed that day; the last day to shop is 2026-10-31)"), coffeeOnly)
        XCTAssertTrue(coffeeOnly.contains("one shop: Dino, 1 of 1 items, 51,99\(nbsp)zł for the quantities on the list"), coffeeOnly)
        XCTAssertTrue(coffeeOnly.contains("Before going (one-shop basket): Dino: \"Lavazza 250 g\": take 3 to get the offer; Dino: \"Lavazza 250 g\": the last day to shop for it is 2026-10-31"), coffeeOnly)
        let notACut = DealOffer(chain: .lidl, product: "Masło", price: Money(minor: 499), lowest30d: Money(minor: 499), source: .init(url: "https://l"), check: false, flags: [.notACut])
        XCTAssertTrue(DealsResultText.forAgent(result([("masło", [notACut])])).contains("not lower than its lowest price in the last 30 days, so not a real cut"))
    }
}

/// "Sprawdź moją listę": a list's items become the request's items and the basket's quantities.
final class DealsListItemsTests: XCTestCase {
    func testTheProductsGoOutAndTheQuantitiesStay() {
        let read = DealsListItems.read(["2 l mleka", "jajka 10 szt.", "masło", "Masło", "  ", "mleko 1 l", "kawa mielona"])
        XCTAssertEqual(read.items, ["mleka", "jajka", "masło", "mleko", "kawa mielona"])
        XCTAssertEqual(read.quantities, [ListQuantity(amount: 2, unit: .litre), ListQuantity(amount: 10, unit: .piece), nil, ListQuantity(amount: 1, unit: .litre), nil])
        XCTAssertEqual(read.leftOut, [])
        let twice = DealsListItems.read(["mleko", "2 l mleko", "mleko 500 ml"])
        XCTAssertEqual(twice.items, ["mleko"])
        XCTAssertEqual(twice.quantities, [ListQuantity(amount: 2.5, unit: .litre)])
    }

    func testWhatDoesntFitIsCountedNeverCut() {
        let long = String(repeating: "a", count: 61)
        let read = DealsListItems.read((1...13).map { "rzecz \($0)" } + [long])
        XCTAssertEqual(read.items.count, DealsRequest.maxItems)
        XCTAssertEqual(read.leftOut, ["rzecz 13", long])
        XCTAssertTrue(DealsRequest(items: read.items).validationIssues().isEmpty)
    }
}
