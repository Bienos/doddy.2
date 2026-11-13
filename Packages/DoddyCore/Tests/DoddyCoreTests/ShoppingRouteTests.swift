@testable import DoddyCore
import XCTest

/// One field for shopping (decision 2026-11-13-shopping-one-field): code decides whether typed words go to this
/// week's leaflets, to "Find me this" in online shops, or to both, and a link goes to "Check this".
final class ShoppingRouteTests: XCTestCase {
    // MARK: One item's kind

    func testGroceriesAndEverydayGoodsAreEveryday() {
        for item in ["mleko", "masło", "Masło Łaciate", "jajka", "kawa mielona", "pieluchy 4", "Pampers 4", "karma dla kota",
                     "papier toaletowy", "proszek do prania", "tabletki do zmywarki", "sól do zmywarki", "szampon", "Coca-Cola",
                     "milk", "butter", "nappies size 4", "dishwasher tablets", "toilet paper", "cat food"] {
            XCTAssertEqual(ShoppingRoute.kind(of: item), .everyday, item)
        }
    }

    func testThingsToCompareOnlineAreOnline() {
        for item in ["słuchawki Apple", "AirPods Pro 2", "zmywarka", "zmywarka 45 cm do 2000 zł", "ekspres do kawy", "telewizor 55 cali",
                     "iPhone 15", "laptop", "odkurzacz bezprzewodowy", "pralka", "sofa", "rower dla dziecka", "wózek spacerowy",
                     "szczoteczka elektryczna", "a quiet 45 cm dishwasher under 2000 zł", "headphones", "washing machine", "Apple Watch"] {
            XCTAssertEqual(ShoppingRoute.kind(of: item), .online, item)
        }
    }

    func testThingsInBetweenAreBoth() {
        for item in ["buty do biegania", "czajnik elektryczny", "patelnia", "kurtka zimowa", "pościel", "ręcznik", "młynek do kawy",
                     "spieniacz do mleka", "drapak dla kota", "dywan", "wiertarka", "klocki LEGO", "kettle", "trainers", "suszarka do prania"] {
            XCTAssertEqual(ShoppingRoute.kind(of: item), .both, item)
        }
    }

    func testTheLongestPhraseDecides() {
        XCTAssertEqual(ShoppingRoute.kind(of: "tabletki do zmywarki"), .everyday, "three words beat 'zmywarka'")
        XCTAssertEqual(ShoppingRoute.kind(of: "zmywarka"), .online)
        XCTAssertEqual(ShoppingRoute.kind(of: "ekspres do kawy"), .online, "'ekspres do kawy' beats 'kawa'")
        XCTAssertEqual(ShoppingRoute.kind(of: "ręcznik papierowy"), .everyday, "two words beat 'ręcznik'")
        XCTAssertEqual(ShoppingRoute.kind(of: "suszarka do prania"), .both, "beats 'do prania'")
        XCTAssertEqual(ShoppingRoute.kind(of: "woda perfumowana"), .both, "beats 'woda'")
    }

    func testAnUnknownWordWithAModelABrandABudgetOrASizeIsOnline() {
        XCTAssertEqual(ShoppingRoute.kind(of: "Sony WH-1000XM5"), .online, "brand and model")
        XCTAssertEqual(ShoppingRoute.kind(of: "Galaxy S24"), .online, "a model")
        XCTAssertEqual(ShoppingRoute.kind(of: "coś ładnego do 300 zł"), .online, "a budget")
        XCTAssertEqual(ShoppingRoute.kind(of: "Dyson"), .online, "a brand of appliances")
        XCTAssertEqual(ShoppingRoute.kind(of: "coś 256 GB"), .online, "a size people compare")
    }

    func testAnUnknownWordIsUnknownAndAPackSizeIsNoModel() {
        XCTAssertEqual(ShoppingRoute.kind(of: "Kinder Bueno"), .unknown)
        XCTAssertEqual(ShoppingRoute.kind(of: "Activia 4x120g"), .unknown, "a multipack is no model")
        XCTAssertEqual(ShoppingRoute.kind(of: "Danio 500g"), .unknown, "a pack size is no model")
        XCTAssertEqual(ShoppingRoute.kind(of: ""), .unknown)
        XCTAssertEqual(ShoppingRoute.kind(of: "  ,  "), .unknown)
    }

    // MARK: A whole text

    func testEverydayItemsGoToTheLeaflets() {
        let route = ShoppingRoute.route("mleko, masło, kawa mielona")
        XCTAssertEqual(route.place, .leaflets)
        XCTAssertEqual(route.leaflets, ["mleko", "masło", "kawa mielona"])
        XCTAssertEqual(route.online, [])
    }

    func testOneThingToCompareGoesOnlineWithItsWordsExactlyAsTyped() {
        let words = "  a quiet 45 cm dishwasher, under 2000 zł "
        let route = ShoppingRoute.route(words)
        XCTAssertEqual(route.place, .online)
        XCTAssertEqual(route.online, ["a quiet 45 cm dishwasher, under 2000 zł"], "trimmed only: what the yes card shows")
        XCTAssertEqual(route.leaflets, [])
    }

    func testAThingInBetweenGetsBoth() {
        let route = ShoppingRoute.route("czajnik elektryczny")
        XCTAssertEqual(route.place, .both)
        XCTAssertEqual(route.leaflets, ["czajnik elektryczny"])
        XCTAssertEqual(route.online, ["czajnik elektryczny"])
    }

    func testAMixedListSplitsByKind() {
        let route = ShoppingRoute.route("mleko\nsłuchawki bezprzewodowe, z ANC, do 400 zł; buty do biegania, Kinder Bueno")
        XCTAssertEqual(route.place, .both)
        XCTAssertEqual(route.leaflets, ["mleko", "buty do biegania", "Kinder Bueno"], "an unknown item is tried in the leaflets")
        XCTAssertEqual(route.online, ["słuchawki bezprzewodowe, z ANC, do 400 zł", "buty do biegania"],
                       "the qualifiers stay with their item")
    }

    func testQualifiersStayWithTheItemAndABudgetIsLeftOutOfTheLeaflets() {
        let route = ShoppingRoute.route("kawa ziarnista, do 60 zł, bez kofeiny")
        XCTAssertEqual(route.leaflets, ["kawa ziarnista bez kofeiny"], "the budget isn't a leaflet word; 'bez' narrows")
        XCTAssertEqual(route.online, [])
        XCTAssertEqual(ShoppingRoute.route("pieluchy, rozmiar 4").leaflets, ["pieluchy rozmiar 4"])
        XCTAssertEqual(ShoppingRoute.route("telewizor, 55 cali").online, ["telewizor, 55 cali"])
    }

    func testTheSameItemTwiceIsOnce() {
        XCTAssertEqual(ShoppingRoute.route("Mleko, mleko, MLEKO").leaflets, ["Mleko"])
    }

    func testALinkGoesToCheckThis() {
        let route = ShoppingRoute.route(" https://www.example-shop.pl/p/123 ")
        XCTAssertEqual(route.place, .link)
        XCTAssertEqual(route.link, "https://www.example-shop.pl/p/123")
        XCTAssertEqual(ShoppingRoute.route("look https://shop.example/x mleko").place, .link)
        XCTAssertEqual(ShoppingRoute.route("http://shop.example/x").place, .leaflets, "not https: no link Doddy reads")
    }

    func testNothingTypedIsNothing() {
        XCTAssertEqual(ShoppingRoute.route("").place, .nothing)
        XCTAssertEqual(ShoppingRoute.route(" ,\n; ").place, .nothing)
    }

    func testThePersonsOwnPickWins() {
        let leaflets = ShoppingRoute.route("słuchawki, mleko", to: .leaflets)
        XCTAssertEqual(leaflets.place, .leaflets)
        XCTAssertEqual(leaflets.leaflets, ["słuchawki", "mleko"])
        let online = ShoppingRoute.route("mleko", to: .online)
        XCTAssertEqual(online.place, .online)
        XCTAssertEqual(online.online, ["mleko"])
        XCTAssertEqual(ShoppingRoute.route("laptop, monitor", to: .online).online, ["laptop", "monitor"], "one task per thing")
        XCTAssertEqual(ShoppingRoute.route("https://shop.example/x", to: .leaflets).place, .link)
        XCTAssertEqual(ShoppingRoute.route("mleko", to: .both), ShoppingRoute.route("mleko"), "no pick: the code decides")
    }

    // MARK: After a leaflet answer

    private func offer(_ chain: DealsChain, _ minor: Int) -> DealOffer {
        DealOffer(chain: chain, product: "\(chain.rawValue) \(minor)", price: Money(minor: minor),
                  source: .init(url: "https://\(chain.rawValue).example"))
    }

    func testOnlineNextOffersInBetweenAndOnlineThingsAndUnknownOnesTheLeafletsLacked() {
        let result = DealsResult(checkedAt: "2026-11-13T08:00:00.000Z", chains: [], items: [
            DealsItemResult(query: "mleko", offers: []),
            DealsItemResult(query: "czajnik", offers: [offer(.lidl, 5_999)]),
            DealsItemResult(query: "Kinder Bueno", offers: [offer(.biedronka, 399)]),
            DealsItemResult(query: "hulajnoga elektryczna", offers: []),
            DealsItemResult(query: "Zyx Qwerty", offers: []),
            DealsItemResult(query: "Abc Def", offers: [], promotions: [
                DealPromotion(chain: .dino, text: "Wszystkie Abc", mechanic: "1+1", source: .init(url: "https://dino.example")),
            ]),
        ])
        XCTAssertEqual(ShoppingRoute.onlineNext(result, also: ["laptop", "Czajnik "]),
                       ["laptop", "Czajnik", "hulajnoga elektryczna", "Zyx Qwerty"],
                       "milk isn't offered; an unknown item with an offer or a promotion isn't either; each thing once")
        XCTAssertEqual(ShoppingRoute.onlineNext(DealsResult(checkedAt: "x", chains: [], items: [])), [])
    }

    func testOnlineNextCountsTheSameWordsOnce() {
        // The field sent "buty do biegania, rozmiar 42" to both; the leaflets read it without the comma.
        let route = ShoppingRoute.route("buty do biegania, rozmiar 42")
        XCTAssertEqual(route.place, .both)
        let result = DealsResult(checkedAt: "x", chains: [], items: route.leaflets.map { DealsItemResult(query: $0, offers: []) })
        XCTAssertEqual(ShoppingRoute.onlineNext(result, also: route.online), ["buty do biegania, rozmiar 42"])
        // The leaflets read "czajnik 1,7 l" as "czajnik" with a quantity.
        let kettle = DealsResult(checkedAt: "x", chains: [], items: [DealsItemResult(query: "czajnik", offers: [])])
        XCTAssertEqual(ShoppingRoute.onlineNext(kettle, also: ["czajnik 1,7 l"]), ["czajnik 1,7 l"])
    }
}
