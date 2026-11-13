import Foundation

// The trip planner (decision 2026-11-11-travel-agent-plan, stage 2; docs/implementation/TRAVEL_PLANNER.md).
// The person says or types what they want; Doddy's server turns the words into a brief and says what is
// still missing; the app asks for one missing thing at a time, in the words below; then the server searches
// Kiwi.com and answers with up to three options chosen by code. Doddy never books or pays: each option
// links to Kiwi.com, and the stays to Booking.com and Airbnb with the dates filled in.

public struct TripBrief: Codable, Equatable, Sendable {
    public var from: String?
    public var to: String?
    public var departFrom: String?
    public var departTo: String?
    public var nightsMin: Int?
    public var nightsMax: Int?
    public var adults: Int?
    public var children: Int?
    public var checkedBagPerAdult: Bool?
    public var directOnly: Bool?
    public var package: Bool?
    public var budget: Int?

    public init() {}

    // Every key is sent, null included: the server's brief has no optional keys.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(from, forKey: .from); try c.encode(to, forKey: .to)
        try c.encode(departFrom, forKey: .departFrom); try c.encode(departTo, forKey: .departTo)
        try c.encode(nightsMin, forKey: .nightsMin); try c.encode(nightsMax, forKey: .nightsMax)
        try c.encode(adults, forKey: .adults); try c.encode(children, forKey: .children)
        try c.encode(checkedBagPerAdult, forKey: .checkedBagPerAdult); try c.encode(directOnly, forKey: .directOnly)
        try c.encode(package, forKey: .package); try c.encode(budget, forKey: .budget)
    }
    enum CodingKeys: String, CodingKey {
        case from, to, departFrom, departTo, nightsMin, nightsMax, adults, children, checkedBagPerAdult, directOnly, package, budget
    }
}

public enum PlanNeed: String, Codable, Sendable { case to, from, when, nights, who }
public enum PlanAssumption: String, Codable, Sendable { case noCheckedBag = "no_checked_bag", stopsAllowed = "stops_allowed", noChildren = "no_children", exactDay = "exact_day" }

public struct PlanUnderstood: Codable, Equatable, Sendable {
    public let brief: TripBrief
    public let missing: [PlanNeed]
    public let assumptions: [PlanAssumption]
}

public struct PlanLeg: Codable, Equatable, Sendable {
    public let from: String
    public let to: String
    public let fromCity: String?
    public let toCity: String?
    public let toCountry: String?
    /// Local times at the airports, "2027-02-12T14:15:00".
    public let departs: String
    public let arrives: String
    public let minutes: Int
    public let stops: Int
    public let flights: [String]
    public let airlines: [String]
}

public struct PlanLinks: Codable, Equatable, Sendable {
    public let booking: String
    public let airbnb: String
    public let packages: String?
}

public struct PlanOption: Codable, Equatable, Sendable, Identifiable {
    public enum Pick: String, Codable, Sendable { case cheapest, fastest, easiest }
    public enum Trap: String, Codable, Sendable {
        case airportChange = "airport_change", differentAirlines = "different_airlines"
        case overnightConnection = "overnight_connection", earlyDeparture = "early_departure", lateArrival = "late_arrival"
    }

    public let pick: Pick
    public let price: Int
    public let currency: String
    public let overBudget: Bool
    public let checkedBagsIncluded: Int
    public let outbound: PlanLeg
    public let inbound: PlanLeg?
    public let traps: [Trap]
    public let bookingUrl: String
    public let links: PlanLinks

    public var id: String { pick.rawValue }
}

public struct PlanResult: Codable, Equatable, Sendable {
    public let brief: TripBrief
    public let options: [PlanOption]
    public let source: String
    public let checkedAt: String
}

// MARK: - Client

public protocol TripPlannerClient: Sendable {
    func understand(words: String, brief: TripBrief?, today: TripDay) async throws(OnlineAccountsError) -> PlanUnderstood
    func search(_ brief: TripBrief, today: TripDay) async throws(OnlineAccountsError) -> PlanResult
}

public struct BackendTripPlannerClient: TripPlannerClient {
    private let baseURL: URL
    private let sessionToken: @Sendable () -> String?
    private let transport: any HTTPTransport

    public init?(baseURL: URL, boundToken: @escaping @Sendable () -> BoundSessionToken?, transport: any HTTPTransport) {
        guard BackendConnectedAppsClient.isAllowed(baseURL) else { return nil }
        self.baseURL = baseURL
        self.sessionToken = { boundToken()?.token(for: baseURL) }
        self.transport = transport
    }

    struct UnderstandBody: Encodable { let words: String; let brief: TripBrief?; let today: String
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(words, forKey: .words); try c.encodeIfPresent(brief, forKey: .brief); try c.encode(today, forKey: .today)
        }
        enum CodingKeys: String, CodingKey { case words, brief, today }
    }
    struct SearchBody: Encodable { let brief: TripBrief; let today: String }

    public func understand(words: String, brief: TripBrief?, today: TripDay) async throws(OnlineAccountsError) -> PlanUnderstood {
        try await call("v1/travel/plan/understand", UnderstandBody(words: words, brief: brief, today: today.description))
    }

    public func search(_ brief: TripBrief, today: TripDay) async throws(OnlineAccountsError) -> PlanResult {
        try await call("v1/travel/plan/search", SearchBody(brief: brief, today: today.description))
    }

    private func call<Body: Encodable, Response: Decodable>(_ path: String, _ body: Body) async throws(OnlineAccountsError) -> Response {
        guard let token = sessionToken(), !token.isEmpty else { throw .notConfigured }
        let data: Data
        do { data = try JSONEncoder().encode(body) } catch { throw .transport("encoding") }
        let request = HTTPRequest(
            method: "POST", url: baseURL.appendingPathComponent(path),
            headers: ["authorization": "Bearer \(token)", "accept": "application/json", "content-type": "application/json"], body: data)
        let status: Int, payload: Data
        do { (status, payload) = try await transport.send(request) } catch { throw .transport(String(describing: type(of: error))) }
        return try BackendOnlineAccountsClient.decode(status: status, data: payload)
    }
}

// MARK: - Words (Polish and English)

public enum TripPlanText {
    /// The one question for the first missing thing.
    public static func question(_ need: PlanNeed, polish: Bool) -> String {
        switch need {
        case .to: polish ? "Dokąd chcesz polecieć?" : "Where would you like to go?"
        case .from: polish ? "Z którego miasta albo lotniska wylatujesz?" : "Which city or airport do you fly from?"
        case .when: polish ? "Kiedy chcesz wylecieć? Może być dzień albo okres, np. „w lutym”." : "When would you like to leave? A day or a window, e.g. “in February”."
        case .nights: polish ? "Na ile nocy?" : "For how many nights?"
        case .who: polish ? "Ile osób leci, licząc dzieci?" : "How many people are flying, children included?"
        }
    }

    public static func assumption(_ a: PlanAssumption, polish: Bool) -> String {
        switch a {
        case .noCheckedBag: polish ? "Bez bagażu rejestrowanego (dopisz, jeśli chcesz walizkę)." : "No checked bag (say if you want a suitcase)."
        case .stopsAllowed: polish ? "Przesiadki są w porządku (dopisz „bez przesiadek”, jeśli nie)." : "Stops are fine (say “direct only” if not)."
        case .noChildren: polish ? "Bez dzieci." : "No children."
        case .exactDay: polish ? "Dokładnie ten dzień wylotu (dopisz „± kilka dni”, jeśli może być elastycznie)." : "Exactly that day (say “± a few days” to be flexible)."
        }
    }

    public static func pick(_ p: PlanOption.Pick, polish: Bool) -> String {
        switch p {
        case .cheapest: polish ? "Najtaniej" : "Cheapest"
        case .fastest: polish ? "Najszybciej" : "Fastest"
        case .easiest: polish ? "Najwygodniej" : "Easiest"
        }
    }

    public static func trap(_ t: PlanOption.Trap, polish: Bool) -> String {
        switch t {
        case .airportChange: polish ? "Przesiadka ze zmianą lotniska: trzeba samemu dojechać na drugie lotnisko." : "The connection changes airports: you get to the other airport yourself."
        case .differentAirlines: polish ? "Przesiadka między różnymi liniami: zwykle osobne bilety. Sprawdź na Kiwi.com, co się dzieje przy spóźnieniu." : "The connection is between different airlines, usually separate tickets. Check on Kiwi.com what happens if one is late."
        case .overnightConnection: polish ? "Długa albo nocna przesiadka." : "A long or overnight connection."
        case .earlyDeparture: polish ? "Wylot przed 6:00." : "Leaves before 6:00."
        case .lateArrival: polish ? "Przylot po 23:00 albo następnego dnia." : "Lands after 23:00 or the next day."
        }
    }

    /// "14:15" from "2027-02-12T14:15:00".
    public static func time(_ local: String) -> String { String(local.dropFirst(11).prefix(5)) }

    /// "12 lutego, 14:15 → 23:05 · 1 przesiadka · Ryanair, easyJet"
    public static func leg(_ l: PlanLeg, polish: Bool) -> String {
        let day = TripDay(String(l.departs.prefix(10))).map { TripCheckText.day($0, polish: polish) } ?? ""
        let route = "\(l.fromCity ?? l.from) → \(l.toCity ?? l.to)"
        return "\(route) · \(day), \(time(l.departs)) → \(time(l.arrives)) · \(stops(l.stops, polish: polish))"
            + (l.airlines.isEmpty ? "" : " · \(l.airlines.joined(separator: ", "))")
    }

    /// "3055 zł za 2 osoby, 2 walizki wliczone"
    public static func price(_ o: PlanOption, adults: Int, polish: Bool) -> String {
        "\(money(o, polish: polish)) \(party(o, people: adults, polish: polish))"
    }

    /// The words handed to Doddy's background task when the person asks it to look at stays. No links in them.
    public static func stayResearchWords(_ o: PlanOption, adults: Int, children: Int) -> String {
        let city = o.outbound.toCity ?? o.outbound.to
        let checkIn = TripDay(String(o.outbound.arrives.prefix(10))).map { TripCheckText.day($0, polish: true) } ?? ""
        let checkOut = TripDay(String((o.inbound?.departs ?? o.outbound.arrives).prefix(10))).map { TripCheckText.day($0, polish: true) } ?? ""
        let who = children > 0 ? "\(adults) dorosłych i \(children) dzieci" : (adults == 1 ? "1 osoby" : "\(adults) osób")
        return "Sprawdź noclegi. Miejsce: \(city). Od \(checkIn) do \(checkOut), dla \(who). Które okolice wybrać i dlaczego, przykładowe ceny za noc i za cały pobyt ze źródłem i datą sprawdzenia, oraz na co uważać."
    }
}
