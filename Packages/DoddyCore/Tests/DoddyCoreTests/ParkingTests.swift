import XCTest
@testable import DoddyCore

final class ParkingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    private let now = ISO8601DateFormatter().date(from: "2026-10-11T12:00:00Z")!

    func testToolCalls() {
        func parse(_ json: String) -> VoiceToolRequest { VoiceToolRequest.parse(name: "parking_spot", parametersJSON: Data(json.utf8)) }
        XCTAssertEqual(parse(#"{"action": "save", "note": "level 2, row C"}"#), .parkingSpot(.save(note: "level 2, row C")))
        XCTAssertEqual(parse(#"{"action": "FIND"}"#), .parkingSpot(.find))
        XCTAssertEqual(parse(#"{"action": "clear"}"#), .parkingSpot(.clear))
        if case .invalid = parse(#"{"action": "share"}"#) {} else { XCTFail("unknown actions are refused") }
        XCTAssertFalse(ConnectionPause.applies(to: .parkingSpot(.find)), "stays on this iPhone")
    }

    func testDistanceIsRoughAndRounded() {
        // About 1.11 km per 0.01° of latitude.
        let meters = Parking.distance(from: (52.2297, 21.0122), to: (52.2397, 21.0122))
        XCTAssertEqual(meters, 1112, accuracy: 5)
        XCTAssertEqual(Parking.distanceText(12), "very close (within about 30 m)")
        XCTAssertEqual(Parking.distanceText(337), "about 350 m")
        XCTAssertEqual(Parking.distanceText(1112), "about 1.1 km")
        XCTAssertEqual(Parking.distanceText(15_400), "about 15 km")
    }

    func testTheAgentNeverHearsCoordinates() {
        let spot = ParkingSpot(latitude: 52.229712, longitude: 21.012233, accuracyMeters: 12, savedAt: now.addingTimeInterval(-3600), note: " level 2\nrow C ")
        XCTAssertEqual(spot.note, "level 2 row C")
        let found = VoiceToolReply.parkingFound(spot, now: now, calendar: calendar, distanceMeters: 337)
        XCTAssertTrue(found.hasPrefix("found: the user saved their parking spot today at 13:00"), found)
        XCTAssertTrue(found.contains("about 350 m"))
        XCTAssertFalse(found.contains("52.2"))
        XCTAssertFalse(found.contains("21.0"))
        let saved = VoiceToolReply.parkingSaved(spot, now: now, calendar: calendar)
        XCTAssertTrue(saved.hasPrefix("saved:"))
        XCTAssertFalse(saved.contains("52.2"))
    }

    func testSavedTimeReadsNaturally() {
        let yesterday = now.addingTimeInterval(-24 * 3600)
        XCTAssertEqual(Parking.savedText(yesterday, now: now, calendar: calendar), "yesterday at 14:00")
        XCTAssertEqual(Parking.savedText(now.addingTimeInterval(-5 * 86_400), now: now, calendar: calendar), "on 6 Oct at 14:00")
    }

    func testMapsLinkAndStorage() throws {
        let spot = ParkingSpot(latitude: 52.2297, longitude: 21.0122, accuracyMeters: 20, savedAt: now, note: nil)
        XCTAssertEqual(Parking.mapsURL(spot)?.absoluteString, "https://maps.apple.com/?ll=52.229700,21.012200&q=Parked%20car")
        XCTAssertEqual(Parking.decode(Parking.encode(spot)), spot)
        XCTAssertNil(Parking.decode(Data("nonsense".utf8)))
    }

    func testLocationProblemsSayWhatToDo() {
        XCTAssertTrue(VoiceToolReply.parkingNoLocation(.denied).contains("While Using"))
        XCTAssertTrue(VoiceToolReply.parkingNoLocation(.approximateOnly).contains("Precise Location"))
        XCTAssertTrue(VoiceToolReply.parkingNoLocation(nil).contains("Nothing was saved"))
    }
}
