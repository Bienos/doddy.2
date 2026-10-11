import XCTest
@testable import DoddyCore

/// A shared list's place reminder for everyone (ADR-307).
final class SharedListPlaceTests: XCTestCase {
    private func place(_ lat: Double, arrive: Bool = true) throws -> ReminderPlace {
        try ReminderPlace(name: "Lidl", latitude: lat, longitude: 21.0, radiusMeters: 200, onArrival: arrive)
    }

    func testOnlyACompletePlaceIsTakenFromICloud() {
        XCTAssertNotNil(SharedListPlace.validated(name: "Lidl", latitude: 52.2, longitude: 21.0, radiusMeters: 200, onArrival: true, sharedBy: "_a"))
        XCTAssertNil(SharedListPlace.validated(name: "Lidl", latitude: 95, longitude: 21.0, radiusMeters: 200, onArrival: true, sharedBy: "_a"))
        XCTAssertNil(SharedListPlace.validated(name: "", latitude: 52.2, longitude: 21.0, radiusMeters: 200, onArrival: true, sharedBy: "_a"))
        XCTAssertNil(SharedListPlace.validated(name: "Lidl", latitude: 52.2, longitude: 21.0, radiusMeters: nil, onArrival: true, sharedBy: "_a"))
    }

    func testWhatTheListScreenOffers() throws {
        let lidl = try place(52.2)
        let shared = SharedListPlace(place: lidl, sharedBy: "_marta")
        let names = ["_marta": "Marta"]
        XCTAssertEqual(SharedPlaceOffer.make(isShared: false, shared: shared, mine: nil, me: "_me", names: names), .nothing)
        XCTAssertEqual(SharedPlaceOffer.make(isShared: true, shared: nil, mine: nil, me: "_me", names: names), .nothing)
        XCTAssertEqual(SharedPlaceOffer.make(isShared: true, shared: nil, mine: lidl, me: "_me", names: names), .canShare(lidl))
        XCTAssertEqual(SharedPlaceOffer.make(isShared: true, shared: shared, mine: nil, me: "_me", names: names), .remindMeToo(shared, by: "Marta"))
        XCTAssertEqual(SharedPlaceOffer.make(isShared: true, shared: shared, mine: try place(52.2003), me: "_me", names: names), .shared(shared, byMe: false),
                       "about 33 m away counts as the same place")
        XCTAssertEqual(SharedPlaceOffer.make(isShared: true, shared: shared, mine: try place(52.21), me: "_me", names: names), .remindMeToo(shared, by: "Marta"),
                       "a different place: still offered")
        XCTAssertEqual(SharedPlaceOffer.make(isShared: true, shared: shared, mine: try place(52.2, arrive: false), me: "_me", names: names), .remindMeToo(shared, by: "Marta"),
                       "leaving isn't arriving")
        XCTAssertEqual(SharedPlaceOffer.make(isShared: true, shared: shared, mine: nil, me: "_marta", names: names), .shared(shared, byMe: true))
    }
}
