@testable import DoddyCore
import XCTest

/// "Sprawdź to": the address and the words a price watch needs, read from what the person shared.
final class SharedShopPageTests: XCTestCase {
    private let page = "https://www.mediaexpert.pl/agd/zmywarki/zmywarka-bosch-sms4hvw33e?utm_source=app"

    func testALoneAddressIsTheWholePage() throws {
        let shared = try XCTUnwrap(SharedShopPage.parse(page))
        XCTAssertEqual(shared.url, page, "tracking parameters stay: the page is read as the person saw it")
        XCTAssertEqual(shared.shop, "mediaexpert.pl")
        XCTAssertEqual(shared.title, "mediaexpert.pl", "no words shared: the shop stands in")
    }

    func testTheWordsNextToTheAddressAreTheTitle() throws {
        let shared = try XCTUnwrap(SharedShopPage.parse("Zmywarka Bosch 60 cm – \(page)"))
        XCTAssertEqual(shared.title, "Zmywarka Bosch 60 cm")
        XCTAssertEqual(shared.url, page)
        let after = try XCTUnwrap(SharedShopPage.parse("\(page)\n  Zmywarka   Bosch | "))
        XCTAssertEqual(after.title, "Zmywarka Bosch")
    }

    func testPunctuationAroundTheAddressIsNotPartOfIt() throws {
        let shared = try XCTUnwrap(SharedShopPage.parse("Zobacz (\(page)), fajna"))
        XCTAssertEqual(shared.url, page)
        XCTAssertEqual(shared.title, "Zobacz fajna", "the brackets and the comma belong to the address's word")
    }

    func testTheFirstAddressIsTheOneShared() throws {
        let shared = try XCTUnwrap(SharedShopPage.parse("https://x-kom.pl/p/1 albo https://morele.net/2"))
        XCTAssertEqual(shared.url, "https://x-kom.pl/p/1")
        XCTAssertEqual(shared.shop, "x-kom.pl")
    }

    func testOnlyAWebAddressWithAHostCounts() {
        for text in ["", "zmywarka bosch", "http://sklep.pl/p/1", "ftp://sklep.pl/p/1", "file:///Users/a/b.html",
                     "https://user:secret@sklep.pl/p/1", "https://sklep/p/1", "https:///p/1", "https://sklep.pl./p/1",
                     "mediaexpert.pl/p/1"] {
            XCTAssertNil(SharedShopPage.parse(text), text)
        }
    }

    func testAnAddressLongerThanAWatchTakesIsRefused() {
        let long = "https://sklep.pl/p/" + String(repeating: "a", count: PriceWatchDraft.maxURL)
        XCTAssertNil(SharedShopPage.parse(long))
        let fits = "https://sklep.pl/p/" + String(repeating: "a", count: PriceWatchDraft.maxURL - 19)
        XCTAssertEqual(SharedShopPage.parse(fits)?.url, fits)
    }

    func testALongTitleIsCutToWhatAWatchTakes() throws {
        let words = String(repeating: "bardzo długa nazwa ", count: 20)
        let shared = try XCTUnwrap(SharedShopPage.parse("\(words) \(page)"))
        XCTAssertLessThanOrEqual(shared.title.utf16.count, PriceWatchDraft.maxTitle)
        XCTAssertTrue(shared.title.hasSuffix("\u{2026}"))
    }

    func testTheDraftIsAnOrdinaryPriceWatch() throws {
        let shared = try XCTUnwrap(SharedShopPage.parse("Zmywarka Bosch \(page)"))
        let draft = shared.watchDraft(thresholdMinor: 189_900)
        XCTAssertEqual(draft.validationIssues(), [])
        XCTAssertEqual(draft.url, page)
        XCTAssertEqual(draft.shop, "mediaexpert.pl")
        XCTAssertEqual(draft.currency, "PLN")
        // The yes is bound to the page, the words and the price, like a watch from a pick.
        XCTAssertNotEqual(draft.digest, shared.watchDraft(thresholdMinor: 179_900).digest)
        XCTAssertEqual(draft.digest, PriceWatchDraft(title: "Zmywarka Bosch", shop: "mediaexpert.pl", url: page,
                                                      thresholdMinor: 189_900).digest)
    }
}
