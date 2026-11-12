import Foundation
import XCTest
@testable import DoddyCore

/// The ElevenLabs model only proposes a live Shopify search or one numbered offer.
/// Every real merchant cart write requires an exact on-screen tap.
final class ShopifyVoiceToolTests: XCTestCase {
    private func parse(_ name: String, _ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: name, parametersJSON: Data(json.utf8))
    }

    func testRealSearchIsReadOnlyAndRunsNow() {
        let request = parse(VoiceToolName.shopifySearch, #"{"query":"czarna bluza"}"#)
        XCTAssertEqual(request, .shopifySearch(query: "czarna bluza"))
        XCTAssertEqual(AskFirst.need(for: request), .runsNow)
        XCTAssertTrue(AskFirst.publicLookups.contains(VoiceToolName.shopifySearch))
        XCTAssertTrue(ConnectionPause.applies(to: request))
        XCTAssertEqual(CarProfile.decision(for: request), .run)
    }

    func testShopifyCheckoutSelectsOnlyIndexAndQuantityAndRequiresATap() {
        let request = parse(VoiceToolName.shopifyPrepareCheckout, #"{"index":2,"quantity":3}"#)
        XCTAssertEqual(request, .shopifyPrepareCheckout(index: 2, quantity: 3))
        let need = AskFirst.need(for: request)
        guard case .tapFirst(let card) = need else { return XCTFail("Real merchant cart must require a tap") }
        XCTAssertTrue(AskFirst.needsTap(need))
        XCTAssertTrue(card.lines.contains(where: { $0.contains("3") }))
        XCTAssertTrue(ConnectionPause.applies(to: request))
        if case .refuse = CarProfile.decision(for: request) {
            // A remote merchant checkout is never created while driving.
        } else { XCTFail("Car mode must refuse checkout") }
    }

    func testNoGuessedMerchantOrRemoteCheckoutCanBeSubmittedByModel() {
        let invalid = [
            #"{"index":0}"#,
            #"{"index":6}"#,
            #"{"index":1.5}"#,
            #"{"index":"1"}"#,
            #"{"index":1,"quantity":0}"#,
            #"{"index":1,"quantity":11}"#,
            #"{"index":1,"quantity":1.5}"#,
            #"{"index":1,"quantity":"1"}"#,
        ]
        for json in invalid {
            if case .invalid = parse(VoiceToolName.shopifyPrepareCheckout, json) {
                // Rejected before any backend call or on-screen proposal.
            } else {
                XCTFail("Invalid live Shopify selection accepted: \(json)")
            }
        }
        XCTAssertEqual(
            parse(VoiceToolName.shopifyPrepareCheckout, #"{"index":1}"#),
            .shopifyPrepareCheckout(index: 1, quantity: 1))
        XCTAssertEqual(
            parse(VoiceToolName.shopifyPrepareCheckout, #"{"index":1,"quantity":10}"#),
            .shopifyPrepareCheckout(index: 1, quantity: 10))
    }

    func testUnboundedCatalogQueriesFailClosed() {
        for query in ["", "x", String(repeating: "x", count: 161)] {
            let input = #"{"query":"\#(query)"}"#
            if case .invalid = parse(VoiceToolName.shopifySearch, input) {
                // Invalid voice input never contacts the provider.
            } else { XCTFail("Accepted invalid query length \(query.count)") }
        }
    }

    func testShopifyIsInTheVoiceCatalogAndOwnedByShoppingFeature() {
        let byName = Dictionary(uniqueKeysWithValues: ToolCatalog.all.map { ($0.name, $0) })
        XCTAssertEqual(byName[VoiceToolName.shopifySearch]?.effect, .lookup)
        XCTAssertEqual(byName[VoiceToolName.shopifySearch]?.approval, .askFirst)
        XCTAssertEqual(byName[VoiceToolName.shopifyPrepareCheckout]?.effect, .handoff)
        XCTAssertEqual(byName[VoiceToolName.shopifyPrepareCheckout]?.approval, .card)
        XCTAssertEqual(Feature.shopifyShopping.tools, [VoiceToolName.shopifySearch, VoiceToolName.shopifyPrepareCheckout])
        let hidden = ReleaseScope(hidden: [.shopifyShopping])
        XCTAssertEqual(hidden.hiddenFeature(forTool: VoiceToolName.shopifySearch), .shopifyShopping)
        XCTAssertEqual(hidden.hiddenFeature(forTool: VoiceToolName.shopifyPrepareCheckout), .shopifyShopping)
    }
}
