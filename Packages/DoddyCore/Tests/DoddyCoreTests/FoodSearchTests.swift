import Foundation
import XCTest
@testable import DoddyCore

/// Home › Food's search (decision `2026-11-13-food-search-nearby`): Apple Maps results judged by code. Food places
/// only, nearest first, within 10 km, each once; a phone number rings only when it is a plain number.
final class FoodSearchTests: XCTestCase {
    private let here = (latitude: 52.2297, longitude: 21.0122)

    /// A result `km` kilometres north of `here` (one degree of latitude is about 111.2 km).
    private func result(_ name: String, north km: Double, kind: FoodPlaceKind? = .restaurant,
                        phone: String? = nil) -> FoodSearchResult {
        FoodSearchResult(name: name, address: "Warszawa", kind: kind,
                         latitude: 52.2297 + km / 111.195, longitude: 21.0122, phone: phone)
    }

    func testFoodPlacesOnlyNearestFirstWithinTenKilometres() {
        let places = FoodSearch.nearby([
            result("Far Burger", north: 12),
            result("Mid Burger", north: 3),
            result("A shop with no food category", north: 1, kind: nil),
            result("Near Burger", north: 0.5),
            result("Corner Bakery", north: 2, kind: .bakery),
        ], here: here)
        XCTAssertEqual(places.map(\.name), ["Near Burger", "Corner Bakery", "Mid Burger"])
        XCTAssertEqual(places[0].kilometres, 0.5, accuracy: 0.01)
        XCTAssertEqual(places[1].kind, .bakery)
    }

    func testEachPlaceOnceAndAtMostTheLimit() {
        let many = (0..<30).map { result("Pizza \($0)", north: Double($0) * 0.1) }
        XCTAssertEqual(FoodSearch.nearby(many, here: here).count, FoodSearch.maxResults)
        XCTAssertEqual(FoodSearch.nearby(many, here: here, limit: 3).map(\.name), ["Pizza 0", "Pizza 1", "Pizza 2"])
        let twice = FoodSearch.nearby([result("Sushi Kushi", north: 1), result("Sushi Kushi", north: 1)], here: here)
        XCTAssertEqual(twice.count, 1)
    }

    func testNamelessPlacesAndImpossiblePositionsAreDropped() {
        let bad = [
            FoodSearchResult(name: "  ", address: "", kind: .cafe, latitude: 52.23, longitude: 21.01),
            FoodSearchResult(name: "Nowhere", address: "", kind: .cafe, latitude: .nan, longitude: 21.01),
            FoodSearchResult(name: "Null Island", address: "", kind: .cafe, latitude: 0, longitude: 0),
            FoodSearchResult(name: "Off the map", address: "", kind: .cafe, latitude: 95, longitude: 21.01),
        ]
        XCTAssertTrue(FoodSearch.nearby(bad, here: here).isEmpty)
    }

    func testOnlyAPlainNumberRings() {
        XCTAssertEqual(FoodSearch.callURL("+48 22 123 45 67")?.absoluteString, "tel:+48221234567")
        XCTAssertEqual(FoodSearch.callURL("(22) 123-45-67")?.absoluteString, "tel:221234567")
        XCTAssertEqual(FoodSearch.callURL("+48\u{00A0}600.100.200")?.absoluteString, "tel:+48600100200")
        XCTAssertNil(FoodSearch.callURL(nil))
        XCTAssertNil(FoodSearch.callURL("   "))
        XCTAssertNil(FoodSearch.callURL("22 123 45 67,123"), "no pause and extension")
        XCTAssertNil(FoodSearch.callURL("*100#"), "no service codes")
        XCTAssertNil(FoodSearch.callURL("48+22123456"), "a + only at the start")
        XCTAssertNil(FoodSearch.callURL("call 221234567"))
        XCTAssertNil(FoodSearch.callURL("1234"), "too short")
        XCTAssertNil(FoodSearch.callURL("+48 1234 5678 9012 3456"), "too long")
        XCTAssertNil(FoodSearch.callURL("\u{0662}\u{0662}\u{0661}\u{0662}\u{0663}\u{0664}\u{0665}"), "ASCII digits only")
    }

    func testAPlaceCarriesItsCallAndMapsLinks() throws {
        let place = try XCTUnwrap(FoodSearch.nearby([result("Pho Hanoi", north: 1, phone: "+48 22 111 22 33")], here: here).first)
        XCTAssertEqual(place.callURL?.absoluteString, "tel:+48221112233")
        let maps = try XCTUnwrap(place.mapsURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        XCTAssertEqual(maps.scheme, "https")
        XCTAssertEqual(maps.host, "maps.apple.com")
        XCTAssertEqual(maps.queryItems?.first { $0.name == "q" }?.value, "Pho Hanoi")
        XCTAssertNotNil(maps.queryItems?.first { $0.name == "ll" }?.value)
        XCTAssertNil(FoodSearch.nearby([result("Quiet Place", north: 1)], here: here).first?.callURL, "no number listed, no call")
    }

    func testTheDishAndTheAddressAreOneShortLineRefusedNotCut() {
        XCTAssertEqual(FoodSearch.dish("  burger \n"), "burger")
        XCTAssertNil(FoodSearch.dish("   "))
        XCTAssertNil(FoodSearch.dish("burger\npizza"))
        XCTAssertNil(FoodSearch.dish(String(repeating: "a", count: FoodSearch.dishMaxLength + 1)))
        XCTAssertEqual(FoodSearch.dish(String(repeating: "a", count: FoodSearch.dishMaxLength))?.count, FoodSearch.dishMaxLength)
        XCTAssertEqual(FoodSearch.address(" ul. Długa 5, Warszawa "), "ul. Długa 5, Warszawa")
        XCTAssertNil(FoodSearch.address(String(repeating: "a", count: FoodSearch.addressMaxLength + 1)))
    }

    func testThePrivacyPageSaysWhereTheSearchGoes() throws {
        let state = DataFlowState(
            rememberConversations: false, shareProfileWithVoice: false, tokenServerSet: false,
            connectionsOn: [], pauseAll: false, doddyServerSet: false, askDoddyOn: false, askDoddyUsesNotes: true)
        let row = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "placeSearch" })
        XCTAssertTrue(row.what.contains("For Food: the dish and the delivery address you type."))
        XCTAssertTrue(row.when.contains("search for food in Food"))
        XCTAssertTrue(DataFlow.staysOnPhone(state).contains { $0.hasPrefix("The delivery address you type in Food") })
    }

    func testTheDeliveryAppsStillOpenTheirFrontPagesWithNoSearchInTheLink() {
        // The screen copies a place's name for the person to paste: no provider publishes a search address
        // (decision 2026-11-11-food-button), so nothing is added to the link.
        for app in FoodApps.all {
            XCTAssertNil(app.url.query, app.name)
            XCTAssertEqual(FoodHandoff(app: app, search: "Sushi Kushi").openURL, app.url, app.name)
        }
    }
}
