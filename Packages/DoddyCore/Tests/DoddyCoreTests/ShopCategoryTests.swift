@testable import DoddyCore
import XCTest

/// Shopping by kind of shop (owner, 13 Nov 2026): every leaflet chain has exactly one kind, a kind's page lists only
/// shops the code can reach, a scoped "Find me this" adds one line the yes card shows (and changes nothing else), and
/// "Compare" marks the lowest price only from the registered prices.
final class ShopCategoryTests: XCTestCase {

    // MARK: Kinds of chain

    func testEveryChainHasTheKindItSells() {
        XCTAssertEqual(DealsChain.biedronka.category, .groceries)
        XCTAssertEqual(DealsChain.zabka.category, .groceries)
        XCTAssertEqual(DealsChain.rossmann.category, .groceries, "a drugstore is household")
        XCTAssertEqual(DealsChain.natura.category, .groceries)
        XCTAssertEqual(DealsChain.kaufland.category, .groceries, "a link-only chain still has its kind")
        XCTAssertEqual(DealsChain.ccc.category, .fashion)
        XCTAssertEqual(DealsChain.deichmann.category, .fashion)
        XCTAssertEqual(DealsChain.komfort.category, .home)
        XCTAssertEqual(DealsChain.action.category, .home)
        XCTAssertEqual(DealsChain.maxizoo.category, .other)
        XCTAssertEqual(DealsChain.zooplus.category, .other)
        XCTAssertEqual(DealsChain(rawValue: "newchain").category, .other, "a chain this app doesn't know is never put with the groceries")
    }

    func testEachChainIsInExactlyOneKind() {
        for chain in DealsChain.all {
            let kinds = ShopCategory.allCases.filter { ShopDirectory.chains(in: $0).contains(chain) }
            XCTAssertEqual(kinds, [chain.category], chain.rawValue)
        }
        let listed = ShopCategory.allCases.flatMap { ShopDirectory.chains(in: $0) }
        XCTAssertEqual(Set(listed), Set(DealsChain.all))
        XCTAssertEqual(listed.count, DealsChain.all.count)
    }

    func testElectronicsHasNoLeafletChain() {
        XCTAssertEqual(ShopDirectory.chains(in: .electronics), [])
        XCTAssertEqual(ShopDirectory.shops(in: .electronics, shopify: false), [])
        XCTAssertEqual(ShopDirectory.shops(in: .electronics, shopify: true), [.shopify])
    }

    // MARK: A kind's shops

    func testCapabilitiesComeFromWhatTheServerDoes() {
        XCTAssertEqual(ShopDirectory.capabilities(of: .lidl), [.leaflet])
        XCTAssertEqual(ShopDirectory.capabilities(of: .ccc), [.leaflet, .onlyItsKind])
        XCTAssertEqual(ShopDirectory.capabilities(of: .zooplus), [.leaflet, .onlyItsKind])
        XCTAssertEqual(ShopDirectory.capabilities(of: .carrefour), [.leafletLink])
        XCTAssertEqual(ShopDirectory.capabilities(of: .netto), [.leafletLink])
    }

    func testGroceriesListTheReadChainsFirstAndNoShopify() {
        let shops = ShopDirectory.shops(in: .groceries, shopify: true)
        XCTAssertFalse(shops.contains(.shopify), "groceries are the leaflet chains")
        XCTAssertEqual(shops.first?.chain, .biedronka)
        let firstLinkOnly = shops.firstIndex { $0.capabilities == [.leafletLink] }
        let lastRead = shops.lastIndex { $0.capabilities.contains(.leaflet) }
        XCTAssertNotNil(firstLinkOnly)
        XCTAssertNotNil(lastRead)
        if let firstLinkOnly, let lastRead { XCTAssertGreaterThan(firstLinkOnly, lastRead) }
        XCTAssertEqual(Set(shops.compactMap(\.chain)), Set(ShopDirectory.chains(in: .groceries)))
    }

    func testShopifyIsListedOnlyWhenOnAndAfterTheChains() {
        XCTAssertEqual(ShopDirectory.shops(in: .fashion, shopify: false).map(\.name), ["CCC", "Deichmann"])
        XCTAssertEqual(ShopDirectory.shops(in: .fashion, shopify: true).map(\.name), ["CCC", "Deichmann", "Shopify"])
        XCTAssertEqual(ShopDirectory.shops(in: .home, shopify: true).last, .shopify)
        XCTAssertEqual(ShopDirectory.shops(in: .other, shopify: true).map(\.name), ["Maxi Zoo", "zooplus", "Shopify"])
        XCTAssertEqual(ShopListing.shopify.capabilities, [.searchAndCart])
    }

    // MARK: The kind in a task's words

    func testTheKindIsOneLineUnderTheWords() {
        XCTAssertEqual(ShopCategoryRequest.words("  cichy laptop do 3000 zł \n", category: .electronics, language: "pl"),
                       "cichy laptop do 3000 zł\n\nKategoria: Elektronika")
        XCTAssertEqual(ShopCategoryRequest.words("trainers size 44", category: .fashion, language: "en"),
                       "trainers size 44\n\nCategory: Fashion and shoes")
        XCTAssertEqual(ShopCategoryRequest.words("Hängematte", category: .home, language: "de"),
                       "Hängematte\n\nCategory: Home and garden", "any language but Polish gets the English line")
        XCTAssertEqual(ShopCategoryRequest.words(" a kettle ", category: nil, language: "en"), "a kettle")
    }

    func testEmptyWordsNeverSendAKindAlone() {
        XCTAssertEqual(ShopCategoryRequest.words("   \n", category: .groceries, language: "pl"), "")
        let draft = ErrandDraft.typedShopping(ShopCategoryRequest.words("", category: .other, language: "pl"),
                                              priorities: [], language: "pl")
        XCTAssertEqual(draft.validationIssues().first, .missingWords)
    }

    func testTheTitleStaysThePersonsWords() {
        let words = ShopCategoryRequest.words("Słuchawki z ANC do 500 zł", category: .electronics, language: "pl")
        let draft = ErrandDraft.typedShopping(words, priorities: ["Cena"], language: "pl")
        XCTAssertEqual(draft.title, "Słuchawki z ANC do 500 zł")
        XCTAssertEqual(draft.words, words, "the yes card shows, and the digest covers, the kind's line too")
        XCTAssertEqual(draft.kind, .shopping)
        XCTAssertEqual(draft.validationIssues(), [])
    }

    func testTheKindIsReadBackOnlyFromItsOwnLine() {
        for category in ShopCategory.allCases {
            for language in ["pl", "en"] {
                let words = ShopCategoryRequest.words("something", category: category, language: language)
                XCTAssertEqual(ShopCategoryRequest.category(in: words), category, "\(category) \(language)")
            }
        }
        XCTAssertNil(ShopCategoryRequest.category(in: "a quiet dishwasher"))
        XCTAssertNil(ShopCategoryRequest.category(in: "Category: Electronics\nbut for my mum"), "only the last line counts")
        XCTAssertNil(ShopCategoryRequest.category(in: "x\n\nCategory: Toys"), "not one of the five")
        XCTAssertNil(ShopCategoryRequest.category(in: ""))
    }

    // MARK: Watched prices by kind

    func testAWatchedPageTakesTheKindOfTheTaskItCameFrom() {
        let offer = Self.offer("o1", price: 129_900, url: "https://shop.example/laptop")
        let words = ShopCategoryRequest.words("laptop", category: .electronics, language: "en")
        let errands = [Self.errand(words: words, offers: [offer])]
        XCTAssertEqual(ShopDirectory.category(ofWatchedPage: "https://shop.example/laptop", shop: "Shop", in: errands), .electronics)
        XCTAssertNil(ShopDirectory.category(ofWatchedPage: "https://shop.example/other", shop: "Shop", in: errands))
        let unscoped = [Self.errand(words: "laptop", offers: [offer])]
        XCTAssertNil(ShopDirectory.category(ofWatchedPage: "https://shop.example/laptop", shop: "Shop", in: unscoped))
    }

    func testAWatchedPageAtALeafletChainTakesTheChainsKind() {
        XCTAssertEqual(ShopDirectory.category(ofWatchedPage: "https://ccc.eu/p/1", shop: "CCC", in: []), .fashion)
        XCTAssertEqual(ShopDirectory.category(ofWatchedPage: "https://example.pl/1", shop: " żabka ", in: []), .groceries)
        XCTAssertNil(ShopDirectory.category(ofWatchedPage: "https://example.pl/1", shop: "x-kom", in: []))
    }

    // MARK: Compare

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

    func testNothingIsLowestWhenThePricesCantBeCompared() {
        let mixed = ShoppingResult(
            offers: [Self.offer("o1", price: 10_000), Self.offer("o2", price: 9_000, currency: "EUR")],
            picks: [ShoppingPick(role: .best, offerId: "o1", why: "a"), ShoppingPick(role: .alternative, offerId: "o2", why: "b")])
        let comparison = ShoppingComparison(mixed)
        XCTAssertFalse(comparison.pricesComparable)
        XCTAssertEqual(comparison.columns.map(\.isLowestPrice), [false, false])
        XCTAssertEqual(comparison.columns.map(\.aboveLowest), [nil, nil])

        let same = ShoppingResult(
            offers: [Self.offer("o1", price: 10_000), Self.offer("o2", price: 10_000)],
            picks: [ShoppingPick(role: .best, offerId: "o1", why: "a"), ShoppingPick(role: .cheapest, offerId: "o2", why: "b")])
        XCTAssertEqual(ShoppingComparison(same).columns.map(\.isLowestPrice), [false, false], "a tie has no lowest")

        let one = ShoppingResult(offers: [Self.offer("o1", price: 10_000)], picks: [ShoppingPick(role: .best, offerId: "o1", why: "a")])
        XCTAssertFalse(ShoppingComparison(one).pricesComparable)
        XCTAssertEqual(ShoppingComparison(one).columns.map(\.isLowestPrice), [false])
    }

    func testAPickWithoutItsOfferIsNotCompared() {
        let shopping = ShoppingResult(
            offers: [Self.offer("o1", price: 10_000), Self.offer("o2", price: 20_000)],
            picks: [ShoppingPick(role: .best, offerId: "o1", why: "a"), ShoppingPick(role: .cheapest, offerId: "gone", why: "b"),
                    ShoppingPick(role: .premium, offerId: "o2", why: "c")])
        let comparison = ShoppingComparison(shopping)
        XCTAssertEqual(comparison.columns.map(\.offer.id), ["o1", "o2"])
        XCTAssertEqual(comparison.columns.map(\.isLowestPrice), [true, false])
    }

    // MARK: Helpers

    private static func offer(_ id: String, price: Int, currency: String = "PLN", evidence: ShoppingOffer.Evidence = .shopPage,
                              url: String? = nil) -> ShoppingOffer {
        ShoppingOffer(id: id, title: "Product \(id)", shop: "Shop \(id)", price: Money(minor: price, currency: currency),
                      url: url ?? "https://shop.example/\(id)", evidence: evidence, seenAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    private static func errand(words: String, offers: [ShoppingOffer]) -> StoredErrand {
        let draft = ErrandDraft.typedShopping(words, priorities: [], language: "en")
        let shopping = ShoppingResult(offers: offers, picks: offers.map { ShoppingPick(role: .best, offerId: $0.id, why: "w") })
        let result = ErrandResult(answer: "a", checkedAt: "2026-11-13T10:00:00.000Z", shopping: shopping)
        return StoredErrand(id: UUID(), createdAt: Date(timeIntervalSince1970: 1_800_000_000), state: .done, draft: draft, result: result)
    }
}
