import Foundation
import XCTest
@testable import DoddyCore

final class JourneyPlannerTests: XCTestCase {
    func testCityMustBeExplicitAndConflictsAreRejected() {
        XCTAssertEqual(JourneyCity.named(in: "Mokotów, Warszawa"), .warszawa)
        XCTAssertEqual(JourneyCity.named(in: "w Warszawie"), .warszawa)
        XCTAssertEqual(JourneyCity.named(in: "Rondo Mogilskie, Kraków"), .krakow)
        XCTAssertEqual(JourneyCity.named(in: "Dworzec, Łódź"), .lodz)
        XCTAssertEqual(JourneyCity.named(in: "centrum Wrocławia"), .wroclaw)
        XCTAssertNil(JourneyCity.named(in: "Mokotów"))
        XCTAssertNil(JourneyCity.named(in: "Warszawska 17"))
        XCTAssertNil(JourneyCity.recognised(from: "Warszawa Centralna", destination: "Dworzec, Kraków"))
        XCTAssertNil(MapTrip(place: "Mokotów", mode: .transit).jakdojadeHandoff())
        XCTAssertNotNil(MapTrip(place: "Mokotów", mode: .transit).jakdojadeHandoff(city: .warszawa))
    }

    func testOneTapLinkWithKnownOriginIsARealSearchNotAFabricatedRoute() throws {
        let handoff = try XCTUnwrap(JakdojadeLinkBuilder.handoff(JourneyIntent(
            destination: "Mokotów, Warszawa",
            origin: "Wola, Warszawa",
            city: .warszawa,
            priority: .convenient,
            avoidTransfers: true,
            avoidBuses: true
        )))
        XCTAssertFalse(handoff.requiresOriginSelection)
        let url = handoff.url
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "jakdojade.pl")
        XCTAssertTrue(url.path.contains("/warszawa/"))
        XCTAssertTrue(url.path.contains("Mokotów"))
        let parameters = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(parameters.first(where: { $0.name == "t" })?.value, "1")
        XCTAssertEqual(parameters.first(where: { $0.name == "aac" })?.value, "true")
        XCTAssertEqual(parameters.first(where: { $0.name == "aab" })?.value, "true")
        XCTAssertNil(parameters.first(where: { $0.name == "fc" }))
        XCTAssertNil(parameters.first(where: { $0.name == "tc" }))
    }

    func testWithoutOriginOnlyPrefillsDestinationNotAComputedTrip() throws {
        let trip = MapTrip(place: "Dworzec Główny, Kraków", mode: .transit)
        let handoff = try XCTUnwrap(trip.jakdojadeHandoff())
        XCTAssertTrue(handoff.requiresOriginSelection)
        XCTAssertEqual(handoff.url.path, "/krakow")
        let parameters = try XCTUnwrap(URLComponents(url: handoff.url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(parameters.first(where: { $0.name == "tn" })?.value, "Dworzec Główny, Kraków")
    }

    func testDateTimeIsInPolandAndArrivalIsNotDeparture() throws {
        let formatter = ISO8601DateFormatter()
        let when = try XCTUnwrap(formatter.date(from: "2026-11-20T07:30:00Z")) // 08:30 Warsaw
        let handoff = try XCTUnwrap(JakdojadeLinkBuilder.handoff(JourneyIntent(
            destination: "Rondo ONZ, Warszawa", city: .warszawa,
            when: .arrive(when), priority: .fastest
        )))
        let params = try XCTUnwrap(URLComponents(url: handoff.url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(params.first(where: { $0.name == "d" })?.value, "20.11.26")
        XCTAssertEqual(params.first(where: { $0.name == "h" })?.value, "08:30")
        XCTAssertEqual(params.first(where: { $0.name == "ia" })?.value, "true")
        XCTAssertEqual(params.first(where: { $0.name == "t" })?.value, "2")
    }

    func testMaliciousNamesCannotInjectParamsOrChangeHost() throws {
        let raw = "A/B?fc=0:0&redirect_url=https://evil.test, Warszawa"
        let h = try XCTUnwrap(JakdojadeLinkBuilder.handoff(JourneyIntent(
            destination: raw, origin: "Wola &B, Warszawa", city: .warszawa
        )))
        XCTAssertEqual(h.url.host, "jakdojade.pl")
        XCTAssertNil(URLComponents(url: h.url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "fc" }))
        XCTAssertFalse(h.url.path.contains("?"))
        XCTAssertTrue(h.url.absoluteString.contains("%2F"))
        XCTAssertNil(JakdojadeLinkBuilder.handoff(JourneyIntent(destination: "Wola\nEvil, Warszawa", city: .warszawa)))
        XCTAssertNil(JakdojadeLinkBuilder.handoff(JourneyIntent(destination: String(repeating: "X", count: 161), city: .warszawa)))
    }

    func testDoNotOfferPartnerTransitForOtherModesOrIntercity() {
        XCTAssertNil(MapTrip(place: "Warszawa", mode: .driving).jakdojadeHandoff())
        XCTAssertNil(MapTrip(place: "Warszawa", mode: .walking).jakdojadeHandoff())
        XCTAssertNil(MapTrip(place: "Warszawa").jakdojadeHandoff())
        XCTAssertNil(MapTrip(place: "Dworzec, Kraków", from: "Warszawa Centralna", mode: .transit).jakdojadeHandoff())
        XCTAssertNil(JakdojadeLinkBuilder.handoff(JourneyIntent(destination: "Dworzec, Kraków", city: .warszawa)))
        XCTAssertNotNil(MapTrip(place: "Wola", mode: .transit).jakdojadeHandoff(city: .warszawa))
    }
}
