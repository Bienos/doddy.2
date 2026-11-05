@testable import DoddyCore
import XCTest

/// "Moje sklepy" (ADR-663): Apple Maps results judged by code, kept on the iPhone as the user's own choice.
final class MyShopsTests: XCTestCase {
    private let warsaw = (latitude: 52.2297, longitude: 21.0122)

    func testOnlyTheChainsShopsNearestFirstWithinReach() {
        let results = [
            ShopSearchResult(name: "Lidl", address: "Marszałkowska 104", latitude: 52.2330, longitude: 21.0090),
            ShopSearchResult(name: "Lidl sp. z o.o.", address: "Grójecka 1", latitude: 52.2200, longitude: 20.9800),
            ShopSearchResult(name: "Lidl", address: "Marszałkowska 104", latitude: 52.2330, longitude: 21.0090),
            ShopSearchResult(name: "Lidlowy Bar", address: "Nowy Świat 5", latitude: 52.2310, longitude: 21.0200),
            ShopSearchResult(name: "Lidl", address: "Kraków", latitude: 50.0647, longitude: 19.9450),
        ]
        let nearby = MyShops.nearby(results, chain: .lidl, here: warsaw)
        XCTAssertEqual(nearby.map(\.shop.address), ["Marszałkowska 104", "Grójecka 1"], "the bar isn't a Lidl, Kraków is too far, a repeat once")
        XCTAssertEqual(nearby[0].kilometres, 0.43, accuracy: 0.05)
        XCTAssertTrue(MyShops.names(ShopSearchResult(name: "Dino Polska S.A.", address: "", latitude: 0, longitude: 0), chain: .dino))
        XCTAssertFalse(MyShops.names(ShopSearchResult(name: "Dinozaur Park", address: "", latitude: 0, longitude: 0), chain: .dino))
        XCTAssertTrue(MyShops.names(ShopSearchResult(name: "Żabka", address: "", latitude: 0, longitude: 0), chain: .zabka))
        XCTAssertTrue(MyShops.names(ShopSearchResult(name: "ALDI", address: "", latitude: 0, longitude: 0), chain: .aldi))
    }

    func testTheUsersShopsSetTheChainsAndStayAsStored() {
        let lidl = MyShop(chain: .lidl, name: "Lidl", address: "Marszałkowska 104", latitude: 52.233, longitude: 21.009)
        let biedronka = MyShop(chain: .biedronka, name: "Biedronka", address: "Złota 59", latitude: 52.230, longitude: 21.003)
        let kaufland = MyShop(chain: .kaufland, name: "Kaufland", address: "Ostrobramska 75", latitude: 52.236, longitude: 21.095)
        let shops = MyShops().adding(lidl).adding(biedronka).adding(lidl).adding(kaufland)
        XCTAssertEqual(shops.shops, [lidl, biedronka, kaufland], "a shop is kept once")
        XCTAssertEqual(shops.chains, [.lidl, .biedronka, .kaufland])
        XCTAssertEqual(MyShops(stored: shops.stored), shops)
        XCTAssertEqual(MyShops(stored: "not json").shops, [])
        XCTAssertEqual(MyShops(stored: #"[{"chain":"lidl","name":"x","address":"y","latitude":500,"longitude":0}]"#).shops, [], "an impossible place is dropped")
        XCTAssertEqual(shops.removing(lidl).chains, [.biedronka, .kaufland])
        XCTAssertEqual(MyShops(shops: (0..<20).map { MyShop(chain: .zabka, name: "Żabka", address: "\($0)", latitude: 52, longitude: 21) }).shops.count, MyShops.maxShops)
    }

    func testAppleMapsLinkAndDistances() {
        let shop = MyShop(chain: .biedronka, name: "Biedronka", address: "Złota 59", latitude: 52.23, longitude: 21.003)
        XCTAssertEqual(shop.mapsURL?.absoluteString, "https://maps.apple.com/?q=Biedronka&ll=52.230000,21.003000")
        XCTAssertEqual(MyShops.distanceText(0.43, polish: true), "450 m")
        XCTAssertEqual(MyShops.distanceText(0.01, polish: true), "50 m")
        XCTAssertEqual(MyShops.distanceText(2.36, polish: true), "2,4 km")
        XCTAssertEqual(MyShops.distanceText(2.36, polish: false), "2.4 km")
        XCTAssertEqual(MyShops.kilometres(52.2297, 21.0122, 50.0647, 19.9450), 252, accuracy: 3, "Warsaw to Kraków")
    }
}

/// ADR-662 in the app: similar products decode apart from the offers and are never counted.
final class DealsSimilarTests: XCTestCase {
    func testSimilarProductsAreKeptApartAndSaidAsSuch() throws {
        let object = try Fixtures.json("deals_search_v1.json")
        let data = try JSONSerialization.data(withJSONObject: try XCTUnwrap(object["response"]))
        let result = try JSONDecoder().decode(DealsResult.self, from: data)
        let butter = result.items[0]
        XCTAssertEqual(butter.similar.map(\.product), ["Masło roślinne 250 g"])
        XCTAssertFalse(butter.offers.contains { $0.product == "Masło roślinne 250 g" })
        XCTAssertFalse(BasketSolver.solve(result).everythingCheapest?.lines.contains { $0.offer.product == "Masło roślinne 250 g" } ?? true)
        let text = DealsResultText.forAgent(result)
        XCTAssertTrue(text.contains("similar, not the same (never call it the item): Dino \"Masło roślinne 250 g\" 3,99\u{00A0}zł"), text)
        let older = try JSONDecoder().decode(DealsItemResult.self, from: Data(#"{"query":"masło","offers":[],"similar":"x"}"#.utf8))
        XCTAssertEqual(older.similar, [], "a wrong shape is dropped, not a failed answer")
        XCTAssertEqual(try JSONDecoder().decode(DealsResult.self, from: JSONEncoder().encode(result)), result)
    }
}
