import XCTest
@testable import DoddyCore

/// "Wyznacz mi trasę" (owner, 10 Nov 2026): open_map with a start or a way to travel opens directions.
final class MapTripTests: XCTestCase {
    private func parse(_ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: "open_map", parametersJSON: Data(json.utf8))
    }

    func testAPlaceAloneStaysASearch() {
        XCTAssertEqual(parse(#"{"place":"Park Żerański"}"#), .openMap(place: "Park Żerański"))
        let trip = MapTrip(place: "Park Żerański")
        XCTAssertFalse(trip.isRoute)
        XCTAssertEqual(trip.url, OpenLinks.map(place: "Park Żerański"))
    }

    func testStartAndModeMakeARoute() {
        XCTAssertEqual(parse(#"{"place":"Park Żerański, Warszawa","from":"Okocimska 4, Warszawa","mode":"transit"}"#),
                       .openMap(place: "Park Żerański, Warszawa", from: "Okocimska 4, Warszawa", mode: .transit))
        let trip = MapTrip(place: "Park Żerański", from: "Okocimska 4", mode: .transit)
        XCTAssertTrue(trip.isRoute)
        XCTAssertEqual(trip.url?.absoluteString,
                       "https://maps.apple.com/?daddr=Park%20%C5%BBera%C5%84ski&saddr=Okocimska%204&dirflg=r")
    }

    func testModeAloneStartsWhereTheIPhoneIs() {
        let url = MapTrip(place: "Hala Koszyki", mode: .walking).url?.absoluteString
        XCTAssertEqual(url, "https://maps.apple.com/?daddr=Hala%20Koszyki&dirflg=w")
    }

    func testSeparatorsInPlacesCantAddParameters() {
        let url = OpenLinks.directions(to: "A&saddr=B", from: "C+D")?.absoluteString
        XCTAssertEqual(url, "https://maps.apple.com/?daddr=A%26saddr%3DB&saddr=C%2BD")
    }

    func testUnknownModeIsNoMode() {
        XCTAssertNil(MapTravelMode.parse("teleport"))
        XCTAssertNil(MapTravelMode.parse(" "))
        XCTAssertEqual(MapTravelMode.parse("Walk"), .walking)
        XCTAssertEqual(MapTravelMode.parse("car"), .driving)
        XCTAssertEqual(parse(#"{"place":"Wola","mode":"teleport"}"#), .openMap(place: "Wola"))
    }

    func testRouteReplyNeverClaimsTravelTimes() {
        let reply = VoiceToolReply.routeOpened(MapTrip(place: "Park Żerański", mode: .transit))
        XCTAssertTrue(reply.hasPrefix("opened:"))
        XCTAssertTrue(reply.contains("From: where the iPhone is"))
        XCTAssertTrue(reply.contains("don't state travel times"))
    }

    func testActivityNamesTheRoute() {
        let request = ActivityRequest.describe(.openMap(place: "Park Żerański", from: "Okocimska 4", mode: .transit), calendar: .current)
        XCTAssertEqual(request?.title, "Directions in Maps")
        XCTAssertEqual(request?.detail, "“Okocimska 4” → “Park Żerański”")
    }
}

/// A card the user can't answer never blocks the next one: the newer ask replaces it (owner, 10 Nov 2026).
final class ReplacedCardReplyTests: XCTestCase {
    func testAReplacedCardCountsAsDeclinedAndClaimsNothing() {
        let reply = VoiceToolReply.replacedByNewerAsk
        XCTAssertTrue(reply.hasPrefix("declined:"))
        XCTAssertTrue(reply.contains("Nothing was done"))
        let entry = ActivityEntry(
            request: ActivityRequest.describe(.openMap(place: "Wola"), calendar: .current)!, reply: reply, at: Date())
        XCTAssertEqual(entry.outcome, .declined)
    }
}
