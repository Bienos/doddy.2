@testable import DoddyCore
import XCTest

/// ADR-667: Delikatesy Centrum, E.Leclerc, Maxi Zoo, Komfort and CCC. The app asks the grocery chains by default,
/// E.Leclerc only when picked, and leaves the specialty shops to the server, which asks them only for their kind.
final class DealsNewShopsTests: XCTestCase {
    func testTheNewShopsHaveTheirNamesAndPlaces() {
        XCTAssertEqual([DealsChain.delikatesy, .leclerc, .maxizoo, .komfort, .ccc].map(\.name),
                       ["Delikatesy Centrum", "E.Leclerc", "Maxi Zoo", "Komfort", "CCC"])
        XCTAssertTrue(DealsChain.read.contains(.leclerc) && DealsChain.read.contains(.ccc))
        XCTAssertTrue([DealsChain.delikatesy, .leclerc, .maxizoo, .komfort, .ccc].allSatisfy { $0.isKnown && $0.isRead })
        XCTAssertFalse(DealsChain.defaultRead.contains(.leclerc), "E.Leclerc only when picked")
        XCTAssertTrue(DealsChain.defaultRead.contains(.delikatesy))
        XCTAssertEqual(DealsChain.named("maxizoo"), .maxizoo)
    }

    func testTheCardNamesTheGroceryChainsAndTheSpecialtyShopsAsAGroup() {
        let card = DealsAsk.card(DealsRequest(items: ["sneakersy"]))
        XCTAssertFalse(card.lines[1].contains("CCC"), "not named one by one when nobody picked")
        XCTAssertTrue(card.lines[1].hasSuffix("pet, shoe and home shops when an item fits"))
        XCTAssertEqual(DealsAsk.card(DealsRequest(items: ["sneakersy"], chains: [.ccc, .leclerc])).lines[1], "Shops: CCC, E.Leclerc",
                       "picked shops are named as picked, with no group line")
        XCTAssertEqual(DealsRequest(items: ["masło"]).chainsAsked, DealsChain.defaultRead)
    }

    func testAnAnswerWithTheNewShopsDecodes() throws {
        let json = #"{"checkedAt":"2026-10-30T08:00:00.000Z","chains":[{"chain":"delikatesy","status":"no_match"},{"chain":"ccc","status":"checked","leaflet":{"title":"Promocje CCC","url":"https://ccc.eu/pl/pl/c/damskie/wyprzedaz/sneakersy"}}],"items":[{"query":"sneakersy","offers":[{"chain":"ccc","product":"adidas BREAKNET SLEEK, sneakersy damskie","price":{"minor":19999,"currency":"PLN"},"lowest30d":{"minor":25999,"currency":"PLN"},"conditions":["−30% w koszyku"],"source":{"url":"https://ccc.eu/pl/pl/p/x"},"readBy":"leaflet_data","check":false,"cut":{"percent":23}}]}]}"#
        let result = try JSONDecoder().decode(DealsResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.chains.map(\.chain), [.delikatesy, .ccc])
        XCTAssertEqual(result.items.first?.offers.first?.chain, .ccc)
        XCTAssertEqual(result.readChainCount, 2)
    }
}
