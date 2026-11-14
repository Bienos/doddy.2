@testable import DoddyCore
import XCTest

/// Shopping by kind of shop (owner, 13 Nov 2026): every leaflet chain has exactly one kind, a kind's page lists only
/// shops the code can reach, and a scoped "Find me this" adds one line the yes card shows (and changes nothing else).
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
}
