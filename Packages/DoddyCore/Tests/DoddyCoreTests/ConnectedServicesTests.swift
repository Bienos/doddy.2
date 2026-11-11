import Foundation
import XCTest
@testable import DoddyCore

final class ConnectedServicesTests: XCTestCase {
    func testBookingUrlsOnlyFromTrustedHttpsProviders() throws {
        let accepted: [(String, BookingService)] = [
            ("https://booksy.com/pl-pl/12345", .booksy),
            ("https://www.booksy.pl/salon/abc", .booksy),
            ("https://my-salon.simplybook.me/v2/", .simplyBook),
        ]
        for (address, provider) in accepted {
            let url = try XCTUnwrap(URL(string: address))
            XCTAssertEqual(BookingService.identify(url), provider)
            XCTAssertEqual(BookingService.sharedBookingURL(in: "Book here: \(address)"), url)
        }
        for bad in [
            "http://booksy.com/pl-pl/123",
            "https://booksy.com.evil.test/pl-pl/123",
            "https://otherbooksy.com/pl-pl/123",
            "https://simplybook.me/en/",
            "https://evil.example/@booksy.com/123",
            "https://user:pass@booksy.com/pl-pl/123",
            "https://booksy.com:444/pl-pl/123",
            "javascript:alert(1)",
        ] {
            let url = try XCTUnwrap(URL(string: bad))
            XCTAssertNil(BookingService.identify(url), "Bad link must not pass: \(bad)")
            XCTAssertNil(BookingService.sharedBookingURL(in: "Here \(bad)"))
        }
        XCTAssertNil(BookingService.sharedBookingURL(in: "https://booksy.com/"))
    }

    func testLocalBookmarkJsonRoundTripDeduplicatesAndRemoves() throws {
        let first = try XCTUnwrap(SavedBookingServices().adding(
            name: "  Mój barber  ", url: "https://booksy.com/pl-pl/12345"
        ))
        XCTAssertEqual(first.items.count, 1)
        XCTAssertEqual(first.items.first?.name, "Mój barber")
        XCTAssertEqual(first.items.first?.provider, .booksy)
        XCTAssertNil(first.adding(name: "Copy", url: "https://booksy.com/pl-pl/12345"))
        let second = try XCTUnwrap(first.adding(
            name: "Hairdresser", url: "https://my-salon.simplybook.me/v2/"
        ))
        XCTAssertEqual(SavedBookingServices(stored: second.stored), second)
        XCTAssertEqual(second.removing(id: first.items[0].id).items.count, 1)
        XCTAssertTrue(second.removing(id: second.items[0].id).items.contains(where: { $0.provider == .simplyBook }))
        XCTAssertTrue(SavedBookingServices(stored: "not json").items.isEmpty)
        XCTAssertNil(SavedBookingServices().adding(name: "Bad", url: "https://booksy.com.evil.test/"))
        XCTAssertNil(SavedBookingServices().adding(name: "Private", url: "https://booksy.com/pl-pl/123?access_token=private"))
        XCTAssertNil(SavedBookingServices().adding(name: "Private fragment", url: "https://booksy.com/pl-pl/123#oauth"))

    }

    func testOnlySharedVintedItemLinksCanOpenListingReview() {
        XCTAssertNotNil(SharedVintedListing(sharedText: "Look https://www.vinted.pl/items/12345-blue-shoes"))
        XCTAssertNotNil(SharedVintedListing(sharedText: "https://vinted.com/items/123-name?x=1"))
        for bad in [
            "https://vinted.pl/",
            "https://vinted.pl/catalog",
            "http://vinted.pl/items/123",
            "https://vinted.pl.evil.test/items/123",
            "https://fakevinted.pl/items/123",
            "https://username:password@vinted.pl/items/123",
        ] {
            XCTAssertNil(SharedVintedListing(sharedText: bad), "Disallow \(bad)")
        }
    }

    func testComparisonPromptNeverCopiesTheVintedUrlOrRunsAutomatically() throws {
        let title = "New Balance 2002R size 43"
        let prompt = try XCTUnwrap(SharedVintedListing.comparisonPrompt(
            product: title, askingPrice: "299,90", polish: true
        ))
        XCTAssertTrue(prompt.contains(title))
        XCTAssertTrue(prompt.contains("299,90 zł"))
        XCTAssertFalse(prompt.contains("https://"))
        XCTAssertNil(SharedVintedListing.comparisonPrompt(product: "", askingPrice: "20", polish: true))
        XCTAssertNil(SharedVintedListing.comparisonPrompt(product: "https://vinted.pl/items/123", askingPrice: "200", polish: true))
        XCTAssertNil(SharedVintedListing.comparisonPrompt(product: "Jacket", askingPrice: "20foo", polish: true))
    }

    func testBookmarkCountHasHardCap() throws {
        let entries: [SavedBookingService] = (0..<60).compactMap { i in
            SavedBookingService(name: "Service \(i)", url: "https://shop\(i).simplybook.me/v2/")
        }
        XCTAssertEqual(SavedBookingServices(items: entries).items.count, SavedBookingServices.maxCount)
        XCTAssertNil(SavedBookingServices(items: entries).adding(name: "Extra", url: "https://extra.simplybook.me/v2/"))
    }
}
