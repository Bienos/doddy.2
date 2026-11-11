import XCTest
@testable import DoddyCore

// Travel, stage 1 (decision 2026-11-11-travel-agent-plan): the bookings the server makes of the shared
// scenario's emails become trips, and each trip its to-do items.
final class TravelTests: XCTestCase {
    private func bookings() throws -> [TravelBooking] {
        try JSONDecoder().decode(TravelBookingsResponse.self, from: Fixtures.data("travel_bookings_v1.json")).bookings
    }

    func testTheServersFixtureDecodes() throws {
        let all = try bookings()
        XCTAssertEqual(all.map(\.reference), ["Z9FAKE", "7001234567", "Q7TEST", "7009999999"])
        XCTAssertEqual(all.map(\.state), [.booked, .booked, .booked, .cancelled])
        XCTAssertEqual(all[1].facts.stay?.city, "Porto")
        XCTAssertEqual(all[2].facts.segments.first?.departDate, "2027-05-13", "the newer confirmation's day")
        XCTAssertEqual(all[2].sources.map(\.senderDomain), ["ryanair.com", "ryanair.com", "ryanairemail.pl"])
    }

    func testBookingsThatTouchBecomeOneTripAndCancelledOnesStayOut() throws {
        let trips = TripAssembly.trips(from: try bookings())
        XCTAssertEqual(trips.count, 2)

        let uk = trips[0]
        XCTAssertEqual(uk.title, "Bristol")
        XCTAssertEqual(uk.places, ["Bristol"], "the flight home to Modlin is not a place the trip goes to")
        XCTAssertEqual(uk.countries, ["GB"])
        XCTAssertEqual(uk.homeCountry, "PL")
        XCTAssertEqual(uk.start.description, "2026-12-08")
        XCTAssertEqual(uk.end.description, "2026-12-12")

        let portugal = trips[1]
        XCTAssertEqual(portugal.bookings.map(\.reference), ["7001234567", "Q7TEST"], "stay from the 12th, flight from the 13th")
        XCTAssertEqual(portugal.title, "Porto · Lizbona")
        XCTAssertEqual(portugal.countries, ["PT"])

        XCTAssertEqual(TripAssembly.notGoingAhead(try bookings()).map(\.reference), ["7009999999"])
    }

    func testWhenATripIs() throws {
        let uk = TripAssembly.trips(from: try bookings())[0]
        XCTAssertEqual(uk.when(today: TripDay(year: 2026, month: 11, day: 11)), .upcoming(days: 27))
        XCTAssertEqual(uk.when(today: TripDay(year: 2026, month: 12, day: 10)), .ongoing)
        XCTAssertEqual(uk.when(today: TripDay(year: 2026, month: 12, day: 13)), .past)
    }

    func testTheUKTripAsksForAPassportAndAnETAAndSaysWhenRyanairCheckInOpens() throws {
        let uk = TripAssembly.trips(from: try bookings())[0]
        let checks = TripChecks.checks(for: uk)

        guard case let .checkIn(flight, rule, opensAt, zone) = checks[0].kind else { return XCTFail("check-in first") }
        XCTAssertEqual(flight, "FR5500 Kraków → Bristol")
        XCTAssertEqual(rule, .ryanair)
        XCTAssertEqual(zone, "Europe/Warsaw")
        // 8 Dec 14:00 in Kraków minus 72 hours: 5 Dec 14:00 Warsaw time, 13:00 UTC.
        XCTAssertEqual(opensAt, ISO8601DateFormatter().date(from: "2026-12-05T13:00:00Z"))
        XCTAssertEqual(checks[0].sourceURL, CheckInRule.ryanair.sourceURL)
        XCTAssertTrue(TripCheckText.detail(checks[0], trip: uk, polish: true).contains("5 gru, 14:00 czasu lokalnego"))

        // The way back leaves Bristol: its check-in time is Bristol's (8:05 on 12 Dec minus 72 h).
        guard case let .checkIn(_, _, backOpens, backZone) = checks[1].kind else { return XCTFail("return check-in") }
        XCTAssertEqual(backZone, "Europe/London")
        XCTAssertEqual(backOpens, ISO8601DateFormatter().date(from: "2026-12-09T08:05:00Z"))

        let documents = checks.filter { if case .documents = $0.kind { true } else { false } }
        XCTAssertEqual(documents.map(\.kind), [.documents(country: "GB", rule: .passportAndUKETA)])
        XCTAssertEqual(documents[0].sourceURL, "https://www.gov.uk/guidance/visiting-the-uk-as-an-eu-eea-or-swiss-citizen")
        XCTAssertTrue(TripCheckText.detail(documents[0], trip: uk, polish: true).contains("dowód osobisty nie wystarczy"))
    }

    func testTheStayBringsItsDeadlineItsExtrasAndWhatTheEmailSaid() throws {
        let portugal = TripAssembly.trips(from: try bookings())[1]
        let kinds = TripChecks.checks(for: portugal).map(\.kind)
        XCTAssertTrue(kinds.contains(.freeCancellation(until: TripDay(year: 2027, month: 5, day: 5), time: "23:59",
                                                       remindOn: TripDay(year: 2027, month: 5, day: 3))))
        XCTAssertTrue(kinds.contains(.deposit(amount: "200.00", currency: "EUR", when: "The host charges this 7 days before arrival.")))
        XCTAssertTrue(kinds.contains(.payOnSite(what: "City tax", amount: "8.00", currency: "EUR")))
        XCTAssertTrue(kinds.contains(.fromTheEmail("Both studios are on the 4th floor without elevator")))
        XCTAssertEqual(kinds.last, .documents(country: "PT", rule: .idCardOrPassport))
    }

    func testAnUnknownAirlineGetsNoInventedTime() {
        XCTAssertNil(CheckInRule.rule(flightNumber: "LO3911", provider: "LOT"))
        XCTAssertNil(CheckInRule.rule(flightNumber: "1350", provider: nil), "a bare number names no airline")
        XCTAssertEqual(CheckInRule.rule(flightNumber: "W6 1350", provider: nil), .wizzAir)
        XCTAssertEqual(CheckInRule.rule(flightNumber: "FR1574", provider: nil), .ryanair)
        XCTAssertNil(CheckInRule.rule(flightNumber: "FRA123", provider: nil), "letters after the code aren't a flight number")

        let check = TripCheck(id: "x.checkin.0", bookingId: "x", kind: .checkIn(flight: "LO3911", rule: nil, opensAt: nil, zone: nil), sourceURL: nil)
        let trip = Trip(id: "x", bookings: [], start: TripDay(year: 2027, month: 1, day: 1), end: TripDay(year: 2027, month: 1, day: 2),
                        places: [], countries: [], homeCountry: "PL")
        XCTAssertTrue(TripCheckText.detail(check, trip: trip, polish: true).hasPrefix("Sprawdź u przewoźnika"))
    }

    func testEntryRules() {
        XCTAssertEqual(EntryRule.forCountry("PT"), .idCardOrPassport)
        XCTAssertEqual(EntryRule.forCountry("NO"), .idCardOrPassport)
        XCTAssertEqual(EntryRule.forCountry("GB"), .passportAndUKETA)
        XCTAssertEqual(EntryRule.forCountry("TR"), .turkey)
        XCTAssertEqual(EntryRule.forCountry("EG"), .checkOfficialPage, "no rule is guessed")
        XCTAssertEqual(TravelCountries.code(named: "Portugal"), "PT")
        XCTAssertEqual(TravelCountries.code(named: "Wielka Brytania"), "GB")
        XCTAssertNil(TravelCountries.code(named: "Atlantis"))
    }

    func testEveryAirportHasARealTimeZone() {
        for airport in TravelAirports.all {
            XCTAssertNotNil(airport.timeZone, airport.code)
            XCTAssertEqual(airport.code.count, 3)
        }
        XCTAssertEqual(TravelAirports.airport("brs")?.country, "GB")
        XCTAssertNil(TravelAirports.airport("XXX"))
    }

    func testDays() {
        let d = TripDay(year: 2026, month: 12, day: 30)
        XCTAssertEqual(d.adding(days: 3).description, "2027-01-02")
        XCTAssertEqual(d.days(to: TripDay(year: 2027, month: 1, day: 2)), 3)
        XCTAssertNil(TripDay("2026-13-01"))
        XCTAssertNil(TripDay(nil))
    }
}

private final class TravelTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    private var replies: [(Int, Data)]
    init(_ replies: [(Int, Data)]) { self.replies = replies }
    var requests: [HTTPRequest] { lock.withLock { recorded } }
    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        lock.withLock {
            recorded.append(request)
            return replies.isEmpty ? (500, Data()) : replies.removeFirst()
        }
    }
}

final class TravelClientTests: XCTestCase {
    private let server = URL(string: "https://api.doddy.example")!

    private func client(_ transport: TravelTransport) throws -> BackendTravelClient {
        let bound = try XCTUnwrap(BoundSessionToken(token: "secret", issuedBy: server))
        return try XCTUnwrap(BackendTravelClient(baseURL: server, boundToken: { bound }, transport: transport))
    }

    func testAskThenSearchSendsTheApprovalAndDecodesTheBookings() async throws {
        let approval = UUID()
        let prepared = """
        {"mode":"mock","tool":"find_trips_in_gmail","preview":{"title":"Find your trips in Gmail?","lines":["x"],"confirmLabel":"Search Gmail"},
         "approvalId":"\(approval.uuidString.lowercased())","expiresAt":"2026-11-11T10:02:00.000Z"}
        """
        let fixture = try JSONSerialization.jsonObject(with: Fixtures.data("travel_bookings_v1.json")) as! [String: Any]
        let scanned = try JSONSerialization.data(withJSONObject: [
            "mode": "live", "emailsFound": 8, "emailsUnreadable": 0, "emailsNotTravel": 1, "bookings": fixture["bookings"]!,
            "receipt": ["operationId": UUID().uuidString],
        ])
        let transport = TravelTransport([(200, Data(prepared.utf8)), (200, scanned)])
        let c = try client(transport)

        let card = try await c.prepareScan()
        XCTAssertEqual(card.approvalId, approval)
        let result = try await c.scan(approvalId: card.approvalId)
        XCTAssertEqual(result.bookings.count, 4)
        XCTAssertEqual(result.emailsNotTravel, 1)

        let paths = transport.requests.map(\.url.path)
        XCTAssertEqual(paths, ["/v1/travel/prepare", "/v1/travel/scan"])
        XCTAssertEqual(transport.requests[0].headers["authorization"], "Bearer secret")
        let firstBody = try JSONSerialization.jsonObject(with: XCTUnwrap(transport.requests[0].body)) as! [String: Any]
        XCTAssertNil(firstBody["approvalId"], "the card is asked for without an approval")
        let secondBody = try JSONSerialization.jsonObject(with: XCTUnwrap(transport.requests[1].body)) as! [String: Any]
        XCTAssertEqual(secondBody["approvalId"] as? String, approval.uuidString.lowercased())
    }

    func testRefusalsBecomeWordsThePersonCanActOn() async throws {
        func problem(_ status: Int, _ code: String, receiptCode: String? = nil) async throws -> TravelScanProblem {
            var error: [String: Any] = ["code": code, "message": "m", "correlationId": "c"]
            if let receiptCode {
                error["receipt"] = ["operationId": UUID().uuidString, "operation": "read", "toolkit": "gmail", "tool": "find_trips_in_gmail",
                                    "timestamp": "2026-11-11T10:00:00Z", "mode": "live", "status": "blocked", "summary": "s", "errorCode": receiptCode]
            }
            let body = try JSONSerialization.data(withJSONObject: ["error": error])
            let c = try client(TravelTransport([(status, body)]))
            do {
                _ = try await c.scan(approvalId: UUID())
                XCTFail("should refuse")
                return .unavailable
            } catch {
                return TravelScanProblem(error)
            }
        }
        let notConnected = try await problem(409, "not_connected")
        XCTAssertEqual(notConnected, .gmailNotConnected)
        let off = try await problem(403, "capability_disabled")
        XCTAssertEqual(off, .readingEmailsOff)
        let unasked = try await problem(403, "capability_disabled", receiptCode: "ask_first_required")
        XCTAssertEqual(unasked, .askAgain)
        let quota = try await problem(429, "quota_exceeded")
        XCTAssertEqual(quota, .dailyLimit)
        XCTAssertTrue(TravelScanProblem.readingEmailsOff.text(polish: true).contains("Przeczytaj maila"))
    }

    func testTripsAreKeptOnThisIPhoneAndForgettingIsChecked() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trips-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TripStore(fileURL: dir.appendingPathComponent("trips-v1.json"))
        XCTAssertNil(try store.load())

        let bookings = try JSONDecoder().decode(TravelBookingsResponse.self, from: Fixtures.data("travel_bookings_v1.json")).bookings
        let saved = SavedTrips(checkedAt: Date(timeIntervalSince1970: 1_794_400_000), bookings: bookings, emailsFound: 8, emailsUnreadable: 0)
        XCTAssertEqual(try store.save(saved), saved)
        XCTAssertEqual(try store.load(), saved)

        try store.forget()
        XCTAssertNil(try store.load())
        try store.forget()

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load(), "an unreadable file is an error, never 'no trips'")
    }

    func testHomeShowsTheNextTripOnlyWhenItIsClose() throws {
        let bookings = try JSONDecoder().decode(TravelBookingsResponse.self, from: Fixtures.data("travel_bookings_v1.json")).bookings
        let trips = TripAssembly.trips(from: bookings)
        let nov11 = TripDay(year: 2026, month: 11, day: 11)
        let next = try XCTUnwrap(TripHomeCard.nextTrip(trips, today: nov11))
        XCTAssertEqual(TripHomeCard.title(next, today: nov11, polish: true), "Bristol za 27 dni")
        XCTAssertEqual(TripHomeCard.title(next, today: TripDay(year: 2026, month: 12, day: 7), polish: false), "Bristol tomorrow")
        XCTAssertEqual(TripHomeCard.title(next, today: TripDay(year: 2026, month: 12, day: 9), polish: true), "Bristol: jesteś w podróży")
        XCTAssertEqual(TripHomeCard.subtitle(next, polish: true), "3 rzeczy do sprawdzenia")
        XCTAssertNil(TripHomeCard.nextTrip(trips, today: TripDay(year: 2026, month: 1, day: 1)), "more than 60 days away")
        XCTAssertEqual(TripHomeCard.nextTrip(trips, today: TripDay(year: 2027, month: 4, day: 1))?.title, "Porto · Lizbona")
    }
}
