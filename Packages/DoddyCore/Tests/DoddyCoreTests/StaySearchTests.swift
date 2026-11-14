import XCTest
@testable import DoddyCore

// Stays on their own in Trips (owner, 13 Nov 2026): the links the iPhone builds and the words it shows.
final class StaySearchTests: XCTestCase {
    private let feb12 = TripDay(year: 2027, month: 2, day: 12)

    func testLinksCarryThePlaceTheDaysAndThePeople() throws {
        let stay = try XCTUnwrap(StaySearch(place: "  Lizbona ", checkIn: feb12, nights: 4, adults: 2, children: 1))
        XCTAssertEqual(stay.place, "Lizbona")
        XCTAssertEqual(stay.checkOut.description, "2027-02-16")

        let booking = try XCTUnwrap(stay.bookingURL)
        let items = try XCTUnwrap(URLComponents(url: booking, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(booking.host, "www.booking.com")
        XCTAssertEqual(items.first { $0.name == "ss" }?.value, "Lizbona")
        XCTAssertEqual(items.first { $0.name == "checkin" }?.value, "2027-02-12")
        XCTAssertEqual(items.first { $0.name == "checkout" }?.value, "2027-02-16")
        XCTAssertEqual(items.first { $0.name == "group_adults" }?.value, "2")
        XCTAssertEqual(items.first { $0.name == "group_children" }?.value, "1")

        let airbnb = try XCTUnwrap(stay.airbnbURL)
        XCTAssertEqual(airbnb.host, "www.airbnb.com")
        XCTAssertEqual(airbnb.path, "/s/Lizbona/homes")
        let airbnbItems = try XCTUnwrap(URLComponents(url: airbnb, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(airbnbItems.first { $0.name == "children" }?.value, "1")
    }

    func testAPlaceWithSpacesAndSlashesStaysOnePathPart() throws {
        let stay = try XCTUnwrap(StaySearch(place: "São Paulo/centro", checkIn: feb12, nights: 1, adults: 1, children: 0))
        let airbnb = try XCTUnwrap(stay.airbnbURL)
        XCTAssertTrue(airbnb.absoluteString.hasPrefix("https://www.airbnb.com/s/S%C3%A3o%20Paulo%2Fcentro/homes?"))
        XCTAssertNil(URLComponents(url: airbnb, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "children" })
    }

    func testWhatTheStepperLimitsRefuse() {
        XCTAssertNil(StaySearch(place: "   ", checkIn: feb12, nights: 2, adults: 1, children: 0))
        XCTAssertNil(StaySearch(place: "Rzym", checkIn: feb12, nights: 0, adults: 1, children: 0))
        XCTAssertNil(StaySearch(place: "Rzym", checkIn: feb12, nights: 31, adults: 1, children: 0))
        XCTAssertNil(StaySearch(place: "Rzym", checkIn: feb12, nights: 2, adults: 0, children: 2))
        XCTAssertNil(StaySearch(place: String(repeating: "a", count: 81), checkIn: feb12, nights: 2, adults: 1, children: 0))
    }

    func testSummaryInPolishAndEnglish() throws {
        let two = try XCTUnwrap(StaySearch(place: "Rzym", checkIn: feb12, nights: 4, adults: 2, children: 0))
        XCTAssertEqual(two.summary(polish: true), "Rzym · 12 lutego – 16 lutego · 4 noce · 2 osoby")
        XCTAssertEqual(two.summary(polish: false), "Rzym · 12 February – 16 February · 4 nights · 2 people")
        let five = try XCTUnwrap(StaySearch(place: "Rzym", checkIn: feb12, nights: 12, adults: 3, children: 2))
        XCTAssertEqual(five.summary(polish: true), "Rzym · 12 lutego – 24 lutego · 12 nocy · 5 osób")
        let one = try XCTUnwrap(StaySearch(place: "Rzym", checkIn: feb12, nights: 1, adults: 1, children: 0))
        XCTAssertEqual(one.summary(polish: true), "Rzym · 12 lutego – 13 lutego · 1 noc · 1 osoba")
    }

    func testResearchWordsNameTheSameStayAndNoLinks() throws {
        let stay = try XCTUnwrap(StaySearch(place: "Porto", checkIn: feb12, nights: 3, adults: 2, children: 0))
        XCTAssertTrue(stay.researchWords.hasPrefix("Sprawdź noclegi. Miejsce: Porto. Od 12 lutego do 15 lutego, dla 2 osób."))
        XCTAssertFalse(stay.researchWords.contains("http"))
    }

    func testPolishFewAndDurations() {
        XCTAssertEqual([1, 2, 4, 5, 12, 14, 22, 25].map(StaySearch.polishFew), [false, true, true, false, false, false, true, false])
        XCTAssertEqual(TripDuration.text(minutes: 175, polish: true), "2 h 55 min")
        XCTAssertEqual(TripDuration.text(minutes: 120, polish: false), "2h")
        XCTAssertEqual(TripDuration.text(minutes: 45, polish: true), "45 min")
    }
}
