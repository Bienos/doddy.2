@testable import DoddyCore
import XCTest

/// ADR-666: "search further" under a leaflet answer decodes as the contract fixture writes it (and an older
/// server's answer has none), only https links are opened, the ask card is in Polish when the app is, and the
/// agent hears that the list is on the screen.
final class DealsFurtherTests: XCTestCase {
    private func fixture() throws -> DealsResult {
        let object: [String: Any] = try Fixtures.json("deals_search_v1.json")
        let data = try JSONSerialization.data(withJSONObject: try XCTUnwrap(object["response"]))
        return try JSONDecoder().decode(DealsResult.self, from: data)
    }

    func testFurtherDecodesAsTheFixtureWritesIt() throws {
        let further = try XCTUnwrap(try fixture().further)
        XCTAssertEqual(further.leaflets.map(\.chain), [.carrefour, .auchan, .netto], "Kaufland was asked for, so it's in the answer's own rows")
        XCTAssertEqual(further.leaflets.first?.url, "https://www.carrefour.pl/gazetki")
        XCTAssertEqual(further.searches.map(\.item), ["masło", "pieluchy rozmiar 4", "kawa mielona"])
        let butter = further.searches[0].links
        XCTAssertEqual(butter.map(\.shop), ["Allegro", "Ceneo"])
        XCTAssertEqual(butter[0].url, "https://allegro.pl/listing?string=mas%C5%82o")
        XCTAssertTrue(butter[0].isPartner)
        XCTAssertEqual(butter[0].openURL, butter[0].buyUrl, "a tap opens the partner link, said under it first")
        XCTAssertFalse(butter[1].isPartner)
        XCTAssertEqual(butter[1].openURL, "https://www.ceneo.pl/;szukaj-mas%C5%82o")
        XCTAssertEqual(further.shopNames, ["Allegro", "Ceneo"])
        XCTAssertTrue(further.hasPartnerLink)
        XCTAssertEqual(try fixture().readChainCount, 4, "Biedronka, Lidl and Dino read with offers, Rossmann read with none")
    }

    func testAnOlderServersAnswerHasNoFurtherAndStillDecodes() throws {
        let json = #"{"checkedAt":"2026-10-24T06:10:00.000Z","chains":[{"chain":"lidl","status":"no_match"}],"items":[{"query":"masło","offers":[]}]}"#
        let result = try JSONDecoder().decode(DealsResult.self, from: Data(json.utf8))
        XCTAssertNil(result.further)
        XCTAssertEqual(result.readChainCount, 1)
    }

    func testOnlyHttpsLinksWithAHostAreKept() {
        let further = DealsFurther(
            leaflets: [DealsLeafletLink(chain: .kaufland, url: "http://www.kaufland.pl/gazetka"), DealsLeafletLink(chain: .netto, url: "https://netto.pl/gazetka-netto/")],
            searches: [
                DealsItemSearch(item: "masło", links: [
                    DealsSearchLink(shop: "Allegro", url: "https://allegro.pl/listing?string=mas%C5%82o", buyUrl: "javascript:alert(1)"),
                    DealsSearchLink(shop: "Ceneo", url: "https://www.ceneo.pl/;szukaj-mas%C5%82o"),
                ]),
                DealsItemSearch(item: "kawa", links: [DealsSearchLink(shop: "X", url: "https:///no-host")]),
            ])
        let kept = try? XCTUnwrap(further.openable)
        XCTAssertEqual(kept?.leaflets.map(\.chain), [.netto])
        XCTAssertEqual(kept?.searches.map(\.item), ["masło"], "an item with no link left is dropped")
        XCTAssertEqual(kept?.searches.first?.links.map(\.shop), ["Ceneo"], "a partner link that isn't https isn't opened, and isn't swapped for the plain one")
        XCTAssertNil(DealsFurther(leaflets: [], searches: [DealsItemSearch(item: "a", links: [DealsSearchLink(shop: "X", url: "ftp://x")])]).openable)
    }

    func testTheAskCardIsInPolishWhenTheAppIs() {
        let deals = DealsRequest(items: ["masło", "kawa mielona"], chains: [.lidl, .kaufland])
        XCTAssertEqual(AskFirst.need(for: .findDeals(deals), polish: true), .yesFirst(AskCard(
            title: "Sprawdzić tegotygodniowe gazetki?",
            lines: [
                "Produkty: masło, kawa mielona",
                "Sklepy: Lidl, Kaufland (tylko link do gazetki)",
                "Doddy czyta gazetki na swoim serwerze. Do sklepów nie trafia nic, co cię identyfikuje; Rossmann dostaje nazwy produktów jako wyszukiwanie.",
            ],
            confirmLabel: "Tak, sprawdź")))
        XCTAssertEqual(AskFirst.need(for: .findDeals(deals)), .yesFirst(DealsAsk.card(deals)), "other languages: the English card, as before")
        XCTAssertEqual(DealsAsk.card(deals).title, "Check this week's leaflets?")
        XCTAssertEqual(DealsAsk.card(DealsRequest(items: ["masło"]), polish: true).lines[1], "Sklepy: Biedronka, Lidl, Dino, Rossmann, Aldi, Żabka")
    }

    func testTheAgentHearsTheListIsOnTheScreenAndWhereToSearchFurther() throws {
        let text = DealsResultText.forAgent(try fixture())
        XCTAssertTrue(text.contains("This list is in the app now: a card on Home opens it. You may tell them so once, in a few words."))
        XCTAssertTrue(text.contains("It also has links to search for the items at Allegro, Ceneo."))
        XCTAssertTrue(text.hasSuffix("Links to the leaflets are on the user's screen; don't read them out."))
        XCTAssertFalse(text.contains("network.example"), "no link reaches the agent")
        let older = DealsResult(checkedAt: "2026-10-24T06:10:00Z", chains: [], items: [DealsItemResult(query: "masło", offers: [])])
        XCTAssertFalse(DealsResultText.forAgent(older).contains("search for the items"), "no shops named when the answer has none")
    }
}
