import XCTest
@testable import DoddyCore

final class FoodDeliveryProviderTests: XCTestCase {
    func testEveryDestinationIsOfficialHttpsWithoutEmbeddedCredentials() {
        let expectedHosts: [FoodDeliveryProvider: String] = [
            .uberEats: "www.ubereats.com",
            .glovo: "glovoapp.com",
            .wolt: "wolt.com",
            .pyszne: "www.pyszne.pl",
            .boltFood: "food.bolt.eu",
        ]

        XCTAssertEqual(FoodDeliveryProvider.allCases.count, expectedHosts.count)
        XCTAssertEqual(Set(FoodDeliveryProvider.allCases.map(\.id)).count, expectedHosts.count)
        for provider in FoodDeliveryProvider.allCases {
            let url = provider.orderURL
            XCTAssertEqual(url.scheme, "https", provider.name)
            XCTAssertEqual(url.host, expectedHosts[provider], provider.name)
            XCTAssertNil(url.user, provider.name)
            XCTAssertNil(url.password, provider.name)
            XCTAssertNil(url.query, provider.name)
            XCTAssertNil(url.fragment, provider.name)
            XCTAssertFalse(provider.canOrderInsideDoddy, "External handoff is never an in-Doddy order")
        }
    }

    func testWarsawListingsAreExplicitAndNeverRepresentCheckout() {
        XCTAssertTrue(FoodDeliveryProvider.glovo.showsWarsawListing)
        XCTAssertTrue(FoodDeliveryProvider.wolt.showsWarsawListing)
        XCTAssertFalse(FoodDeliveryProvider.uberEats.showsWarsawListing)
        XCTAssertFalse(FoodDeliveryProvider.pyszne.showsWarsawListing)
        XCTAssertFalse(FoodDeliveryProvider.boltFood.showsWarsawListing)
    }

    func testLinksStayOnVerifiedEntryPagesNotInventedCartEndpoints() {
        XCTAssertEqual(FoodDeliveryProvider.uberEats.orderURL.path, "/pl/near-me")
        XCTAssertEqual(FoodDeliveryProvider.glovo.orderURL.path, "/pl/pl/warszawa/categories/jedzenie_1")
        XCTAssertEqual(FoodDeliveryProvider.wolt.orderURL.path, "/pl/pol/warsaw")
        XCTAssertEqual(FoodDeliveryProvider.pyszne.orderURL.path, "/")
        XCTAssertEqual(FoodDeliveryProvider.boltFood.orderURL.path, "/")
    }
}
