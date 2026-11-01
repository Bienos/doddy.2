@testable import DoddyCore
import XCTest

/// ADR-668: an offer may carry a partner link to the shop's own page; an older server sends none; only https is used.
final class DealsPartnerOfferTests: XCTestCase {
    private func offer(_ extra: String) throws -> DealOffer {
        let json = #"{"chain":"ccc","product":"JENNY, sneakersy damskie","price":{"minor":4799,"currency":"PLN"},"conditions":[],"source":{"url":"https://ccc.eu/pl/pl/p/jenny-2"},"readBy":"leaflet_data","check":false\#(extra)}"#
        return try JSONDecoder().decode(DealOffer.self, from: Data(json.utf8))
    }

    func testAPartnerLinkDecodesAndRoundTrips() throws {
        let partner = try offer(#","buyUrl":"https://network.example/click?id=7&to=https%3A%2F%2Fccc.eu%2Fpl%2Fpl%2Fp%2Fjenny-2""#)
        XCTAssertTrue(partner.isPartner)
        XCTAssertEqual(try JSONDecoder().decode(DealOffer.self, from: JSONEncoder().encode(partner)), partner)
        XCTAssertFalse(try offer("").isPartner, "an older server sends none")
        XCTAssertFalse(try offer(#","buyUrl":"javascript:alert(1)""#).isPartner, "only https is ever opened")
        XCTAssertFalse(try offer(#","buyUrl":5"#).isPartner, "a wrong type is dropped, the offer still decodes")
    }
}
