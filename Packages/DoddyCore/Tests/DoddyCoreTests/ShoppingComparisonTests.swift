import XCTest
@testable import DoddyCore

/// "Compare the picks" (ShoppingComparison): the lowest price and the gaps are sums over the registered prices,
/// marked only when the prices can be compared, never by a model.
final class ShoppingComparisonTests: XCTestCase {
    func testTheLowestPriceIsMarkedAndTheOthersSayByHowMuch() {
        let shopping = ShoppingResult(
            offers: [Self.offer("o1", price: 189_900), Self.offer("o2", price: 159_900, evidence: .listing), Self.offer("o3", price: 249_900)],
            picks: [ShoppingPick(role: .best, offerId: "o1", why: "quiet"),
                    ShoppingPick(role: .cheapest, offerId: "o2", why: "cheap"),
                    ShoppingPick(role: .premium, offerId: "o3", why: "best")])
        let comparison = ShoppingComparison(shopping)
        XCTAssertTrue(comparison.pricesComparable)
        XCTAssertEqual(comparison.columns.map(\.offer.id), ["o1", "o2", "o3"], "the result card's order")
        XCTAssertEqual(comparison.columns.map(\.isLowestPrice), [false, true, false])
        XCTAssertEqual(comparison.columns.map(\.aboveLowest), [Money(minor: 30_000), nil, Money(minor: 90_000)])
        XCTAssertEqual(comparison.columns.map(\.priceCheckedOnPage), [true, false, true])
    }

    func testTheColumnsFollowTheResultCardsOrderNotTheServersList() {
        let shopping = ShoppingResult(
            offers: [Self.offer("o1", price: 30_000), Self.offer("o2", price: 10_000), Self.offer("o3", price: 20_000)],
            picks: [ShoppingPick(role: .alternative, offerId: "o3", why: "c"),
                    ShoppingPick(role: .cheapest, offerId: "o2", why: "b"),
                    ShoppingPick(role: .best, offerId: "o1", why: "a")])
        XCTAssertEqual(ShoppingComparison(shopping).columns.map(\.pick.role), [.best, .cheapest, .alternative])
    }

    func testNothingIsLowestWhenThePricesCantBeCompared() {
        let mixed = ShoppingResult(
            offers: [Self.offer("o1", price: 10_000), Self.offer("o2", price: 9_000, currency: "EUR")],
            picks: [ShoppingPick(role: .best, offerId: "o1", why: "a"), ShoppingPick(role: .alternative, offerId: "o2", why: "b")])
        let comparison = ShoppingComparison(mixed)
        XCTAssertFalse(comparison.pricesComparable)
        XCTAssertEqual(comparison.columns.map(\.isLowestPrice), [false, false], "9 000 EUR minor units is not less than 10 000 PLN")
        XCTAssertEqual(comparison.columns.map(\.aboveLowest), [nil, nil])
    }

    func testATieHasNoLowestAndASingleOfferHasNothingToCompare() {
        let same = ShoppingResult(
            offers: [Self.offer("o1", price: 10_000), Self.offer("o2", price: 10_000)],
            picks: [ShoppingPick(role: .best, offerId: "o1", why: "a"), ShoppingPick(role: .cheapest, offerId: "o2", why: "b")])
        XCTAssertEqual(ShoppingComparison(same).columns.map(\.isLowestPrice), [false, false], "a tie has no lowest")
        XCTAssertEqual(ShoppingComparison(same).columns.map(\.aboveLowest), [nil, nil])

        let one = ShoppingResult(offers: [Self.offer("o1", price: 10_000)], picks: [ShoppingPick(role: .best, offerId: "o1", why: "a")])
        XCTAssertFalse(ShoppingComparison(one).pricesComparable)
        XCTAssertEqual(ShoppingComparison(one).columns.map(\.isLowestPrice), [false])
        XCTAssertFalse(ShoppingComparison.isOffered(for: one))
    }

    func testTwoPicksAtTheLowestPriceAreBothMarkedWhenAnotherCostsMore() {
        let shopping = ShoppingResult(
            offers: [Self.offer("o1", price: 10_000), Self.offer("o2", price: 10_000), Self.offer("o3", price: 12_550)],
            picks: [ShoppingPick(role: .best, offerId: "o1", why: "a"),
                    ShoppingPick(role: .cheapest, offerId: "o2", why: "b"),
                    ShoppingPick(role: .premium, offerId: "o3", why: "c")])
        let comparison = ShoppingComparison(shopping)
        XCTAssertEqual(comparison.columns.map(\.isLowestPrice), [true, true, false])
        XCTAssertEqual(comparison.columns.map(\.aboveLowest), [nil, nil, Money(minor: 2_550)], "exact, in minor units")
    }

    func testAPickWithoutItsOfferIsNotCompared() {
        let shopping = ShoppingResult(
            offers: [Self.offer("o1", price: 10_000), Self.offer("o2", price: 20_000)],
            picks: [ShoppingPick(role: .best, offerId: "o1", why: "a"), ShoppingPick(role: .cheapest, offerId: "gone", why: "b"),
                    ShoppingPick(role: .premium, offerId: "o2", why: "c")])
        let comparison = ShoppingComparison(shopping)
        XCTAssertEqual(comparison.columns.map(\.offer.id), ["o1", "o2"])
        XCTAssertEqual(comparison.columns.map(\.isLowestPrice), [true, false])
        XCTAssertTrue(ShoppingComparison.isOffered(for: shopping))
    }

    func testCompareIsOfferedOnlyForTwoPicksOrMoreThatHaveTheirOffers() {
        let oneShown = ShoppingResult(
            offers: [Self.offer("o1", price: 10_000)],
            picks: [ShoppingPick(role: .best, offerId: "o1", why: "a"), ShoppingPick(role: .cheapest, offerId: "gone", why: "b")])
        XCTAssertFalse(ShoppingComparison.isOffered(for: oneShown), "a pick without its offer isn't shown, so it isn't a second pick")
        XCTAssertFalse(ShoppingComparison.isOffered(for: ShoppingResult(offers: [], picks: [])))
    }

    // MARK: Helpers

    private static func offer(_ id: String, price: Int, currency: String = "PLN", evidence: ShoppingOffer.Evidence = .shopPage) -> ShoppingOffer {
        ShoppingOffer(id: id, title: "Product \(id)", shop: "Shop \(id)", price: Money(minor: price, currency: currency),
                      url: "https://shop.example/\(id)", evidence: evidence, seenAt: Date(timeIntervalSince1970: 1_800_000_000))
    }
}
