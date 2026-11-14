@testable import DoddyCore
import XCTest

/// Leaflet results and deal watches (decision 2026-11-13-leaflet-results-and-deal-watches): the answer's new fields
/// (`match`, `leafletRead`, a catalogued chain's `readAt` and `complete`) decode from the contract fixture and are
/// optional, so an older server's answer decodes as before; the deal-watch request keeps the server's limits and sends
/// exactly its fields; the watch, list and matches decode from `deal_watch_v1.json`; the push opens Shopping.
final class DealWatchesTests: XCTestCase {
    private func deals() throws -> DealsResult {
        let object = try XCTUnwrap(try Fixtures.json("deals_search_v1.json")["response"])
        return try JSONDecoder().decode(DealsResult.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func watchFixture(_ key: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: try XCTUnwrap(try Fixtures.json("deal_watch_v1.json")[key]))
    }

    // MARK: The answer's new fields

    func testHowEachOfferMatchedAndWhenItsSourceWasRead() throws {
        let result = try deals()
        let butter = try XCTUnwrap(result.items.first { $0.query == "masło" })
        XCTAssertEqual(butter.offers.map(\.match), [.exact, .exact])
        XCTAssertEqual(butter.similar.map(\.match), [.similar])
        XCTAssertTrue(butter.similar.allSatisfy(\.isSimilarOnly))
        XCTAssertFalse(butter.offers.contains(where: \.isSimilarOnly))
        let read = try XCTUnwrap(butter.offers.first?.leafletRead)
        XCTAssertEqual(read.readAt, "2026-10-24T05:45:00.000Z")
        XCTAssertEqual(read.readDate, ServerDates.parse("2026-10-24T05:45:00.000Z"))
        XCTAssertEqual(read.validFrom, DealDay(rawValue: "2026-10-23"))
        XCTAssertEqual(read.validTo, DealDay(rawValue: "2026-10-29"))
        XCTAssertFalse(read.complete, "Biedronka's leaflet was read in part")
        let coffee = try XCTUnwrap(result.items.first { $0.query == "kawa mielona" })
        XCTAssertNotNil(coffee.promotions.first?.leafletRead)
    }

    func testACataloguedChainSaysWhenItWasReadAndWhetherAllOfIt() throws {
        let result = try deals()
        let biedronka = try XCTUnwrap(result.report(for: .biedronka))
        XCTAssertEqual(biedronka.readAt, "2026-10-24T05:45:00.000Z")
        XCTAssertEqual(biedronka.complete, false)
        XCTAssertTrue(biedronka.readInPart)
        let lidl = try XCTUnwrap(result.report(for: .lidl))
        XCTAssertEqual(lidl.complete, true)
        XCTAssertFalse(lidl.readInPart)
        let rossmann = try XCTUnwrap(result.report(for: .rossmann))
        XCTAssertNil(rossmann.readAt, "read live for this answer: no catalog time")
        XCTAssertNil(rossmann.complete)
    }

    func testTheNewFieldsSurviveARoundTrip() throws {
        let result = try deals()
        XCTAssertEqual(try JSONDecoder().decode(DealsResult.self, from: JSONEncoder().encode(result)), result)
    }

    func testAnOlderServersAnswerDecodesWithoutThemAndAValueThatDoesntReadIsDropped() throws {
        let old = #"""
        {"checkedAt":"2026-10-24T06:10:00.000Z","chains":[{"chain":"lidl","status":"checked","leaflet":{"url":"https://www.lidl.pl/x"},"readAt":"yesterday","complete":"yes"}],
         "items":[{"query":"masło","offers":[{"chain":"lidl","product":"Masło","price":{"minor":499,"currency":"PLN"},"conditions":[],
           "source":{"url":"https://www.lidl.pl/x"},"readBy":"page_image","check":false,"match":"telepathy","leafletRead":{"readAt":"soon","complete":true}},
           {"chain":"lidl","product":"Masło 2","price":{"minor":549,"currency":"PLN"},"conditions":[],"source":{"url":"https://www.lidl.pl/x"},"check":false}]}]}
        """#
        let result = try JSONDecoder().decode(DealsResult.self, from: Data(old.utf8))
        let report = try XCTUnwrap(result.report(for: .lidl))
        XCTAssertNil(report.readAt)
        XCTAssertNil(report.complete)
        let offers = result.items[0].offers
        XCTAssertEqual(offers[0].match, .unknown, "a value this app doesn't know is never read as exact")
        XCTAssertNil(offers[0].leafletRead, "a time that doesn't read is dropped")
        XCTAssertNil(offers[1].match)
        XCTAssertNil(offers[1].leafletRead)
    }

    // MARK: The request

    func testTheRequestKeepsTheServersLimitsAndSendsExactlyItsFields() throws {
        let fixture = try JSONSerialization.jsonObject(with: try watchFixture("request")) as? [String: Any]
        let request = DealWatchRequest(item: "  masło ", maxPriceMinor: 500, chains: [.biedronka, .lidl, .biedronka], language: "PL")
        XCTAssertEqual(request.item, "masło")
        XCTAssertEqual(request.chains, [.biedronka, .lidl])
        XCTAssertTrue(request.isValid)
        let sent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        XCTAssertEqual(sent as NSDictionary?, fixture as NSDictionary?)
        let bare = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DealWatchRequest(item: "kawa"))) as? [String: Any]
        XCTAssertEqual(Set(try XCTUnwrap(bare).keys), ["item", "language"], "the optional fields only when set: the body is strict")

        XCTAssertEqual(DealWatchRequest(item: " ").validationIssues(), [.emptyItem])
        XCTAssertEqual(DealWatchRequest(item: String(repeating: "x", count: 61)).validationIssues(), [.itemTooLong])
        XCTAssertEqual(DealWatchRequest(item: "masło", maxPriceMinor: 0).validationIssues(), [.priceOutOfRange])
        XCTAssertEqual(DealWatchRequest(item: "masło", chains: [.rossmann]).validationIssues(), [.chainNotCatalogued],
                       "Rossmann is read by the item, never catalogued")
        XCTAssertEqual(DealWatchRequest(item: "masło", language: "de").validationIssues(), [.languageNotSupported])
        XCTAssertEqual(DealWatchRequestIssue.chainNotCatalogued.field, "chains")
        XCTAssertEqual(Set(DealWatchRequest.catalogued).count, 11)
    }

    // MARK: The answers

    func testTheWatchListAndMatchesDecodeFromTheContractFixture() throws {
        let created = try JSONDecoder().decode(DealWatchCreated.self, from: watchFixture("created"))
        XCTAssertEqual(created.watch.item, "masło")
        XCTAssertEqual(created.watch.maxPrice, Money(minor: 500))
        XCTAssertEqual(created.watch.chains, [.biedronka, .lidl])
        XCTAssertEqual(created.watch.found, 0)
        XCTAssertNotNil(created.watch.endsDate)
        XCTAssertEqual(created.offers.map(\.product), ["Masło Extra 82% 200 g"])
        XCTAssertEqual(created.offers.first?.match, .exact)

        let list = try JSONDecoder().decode(DealWatchList.self, from: watchFixture("list"))
        XCTAssertEqual(list.watches.map(\.item), ["masło", "słuchawki Apple"])
        XCTAssertNil(list.watches[1].maxPriceMinor)
        XCTAssertNil(list.watches[1].chains)
        XCTAssertNil(list.watches[1].lastCheckedAt)
        XCTAssertEqual(list.watches[0].found, 1)

        let matches = try JSONDecoder().decode(DealWatchMatches.self, from: watchFixture("offers"))
        XCTAssertEqual(matches.offers.map(\.price.minor), [479])
        XCTAssertEqual(matches.chains.map(\.chain), [.biedronka, .lidl])
        XCTAssertFalse(matches.readInPart)
        XCTAssertTrue(created.chains.contains { !$0.complete }, "the fixture's Lidl was read in part when the watch was made")
    }

    func testASimilarOfferNeverCountsAsAWatchsMatch() throws {
        let body = #"""
        {"id":"w","checkedAt":"2026-11-14T08:00:00.000Z","chains":[],"offers":[
          {"chain":"lidl","product":"Margaryna","price":{"minor":299,"currency":"PLN"},"conditions":[],"source":{"url":"https://www.lidl.pl/x"},"check":false,"match":"similar"},
          {"chain":"lidl","product":"Masło","price":{"minor":479,"currency":"PLN"},"conditions":[],"source":{"url":"https://www.lidl.pl/x"},"check":false,"match":"brand"}]}
        """#
        let matches = try JSONDecoder().decode(DealWatchMatches.self, from: Data(body.utf8))
        XCTAssertEqual(matches.offers.map(\.product), ["Masło"])
    }

    func testTheRefusalCodesAreTheFixtures() throws {
        let errors = try XCTUnwrap(try Fixtures.json("deal_watch_v1.json")["errors"] as? [String: [String: Any]])
        let codes = Set(errors.values.compactMap { ($0["body"] as? [String: Any])?["error"] as? String })
        XCTAssertEqual(codes, Set(DealWatchRefusal.allCases.map(\.rawValue)))
    }

    // MARK: The push

    func testADealWatchPushOpensShoppingByItsKindOnly() {
        XCTAssertEqual(ServerPushKind.parse(["aps": ["alert": "x"], "doddy": ["kind": "deal-watch"]]), .dealWatch)
        XCTAssertTrue(ServerPushKind.dealWatch.opensShopping)
        XCTAssertFalse(ServerPushKind.dealWatch.opensMessages)
        XCTAssertFalse(ServerPushKind.dealWatch.opensRadar)
        for other in [ServerPushKind.callResult, .errandResult, .fileReady, .radar] {
            XCTAssertFalse(other.opensShopping, other.rawValue)
        }
        XCTAssertNil(ServerPushKind.parse(["doddy": ["kind": "deal-watch:1234"]]), "never an id in the hint")
    }
}
