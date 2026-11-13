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
        let stops = Self.stops(l.stops, polish: polish)
        let route = "\(l.fromCity ?? l.from) → \(l.toCity ?? l.to)"
        return "\(route) · \(day), \(time(l.departs)) → \(time(l.arrives)) · \(stops)" + (l.airlines.isEmpty ? "" : " · \(l.airlines.joined(separator: ", "))")
    }

    /// "bez przesiadek", "1 przesiadka", "przesiadki: 2" (the boarding-pass cards show it under the plane).
    public static func stops(_ n: Int, polish: Bool) -> String {
        switch n {
        case 0: polish ? "bez przesiadek" : "direct"
        case 1: polish ? "1 przesiadka" : "1 stop"
        default: polish ? "przesiadki: \(n)" : "\(n) stops"
        }
    }

    /// "3055 zł", or "412 EUR": the big number on a flight card.
    public static func money(_ o: PlanOption, polish: Bool) -> String {
        o.currency == "PLN" && polish ? "\(o.price) zł" : "\(o.price) \(o.currency)"
    }

    /// "za 2 osoby, bez walizki": what the big number covers.
    public static func priceDetail(_ o: PlanOption, adults: Int, polish: Bool) -> String {
        String(price(o, adults: adults, polish: polish).dropFirst(money(o, polish: polish).count + 1))
    }

    /// "3055 zł za 2 osoby, 2 walizki wliczone"
    public static func price(_ o: PlanOption, adults: Int, polish: Bool) -> String {
        let money = Self.money(o, polish: polish)
        let people = polish ? (adults == 1 ? "za 1 osobę" : "za \(adults) osoby") : (adults == 1 ? "for 1 person" : "for \(adults) people")
        let bags = o.checkedBagsIncluded > 0
            ? (polish ? ", walizki wliczone: \(o.checkedBagsIncluded)" : ", checked bags included: \(o.checkedBagsIncluded)")
            : (polish ? ", bez walizki" : ", no checked bag")
        return "\(money) \(people)\(bags)"
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

/// Stays on their own (owner, 13 Nov 2026: Trips is "planowanie wyjazdu, wyszukiwanie lotów, hoteli"): the
/// person types a place, a check-in day, the nights and who is going; the iPhone builds the same Booking.com
/// and Airbnb searches as the server's `stayLinks` (backend/src/travel/plan.ts), with everything filled in.
/// Nothing is read from those pages and nothing is booked; the words for Doddy's background research name
/// the same stay. No server is asked, so it works with no connection to Doddy's server.
public struct StaySearch: Equatable, Sendable {
    public static let maxNights = 30
    public static let maxAdults = 9
    public static let maxChildren = 6

    public let place: String
    public let checkIn: TripDay
    public let nights: Int
    public let adults: Int
    public let children: Int

    /// Nil for an empty place (after trimming), a place over 80 characters, no nights or too many, nobody
    /// grown up, or too many people. The checks are the screen's steppers' limits, so a nil is a bug there.
    public init?(place: String, checkIn: TripDay, nights: Int, adults: Int, children: Int) {
        let trimmed = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80, (1...Self.maxNights).contains(nights),
              (1...Self.maxAdults).contains(adults), (0...Self.maxChildren).contains(children) else { return nil }
        self.place = trimmed
        self.checkIn = checkIn
        self.nights = nights
        self.adults = adults
        self.children = children
    }

    public var checkOut: TripDay { checkIn.adding(days: nights) }

    /// Booking.com's search: `ss`, `checkin`, `checkout`, `group_adults`, `group_children`, `no_rooms`.
    public var bookingURL: URL? {
        var c = URLComponents(string: "https://www.booking.com/searchresults.html")
        c?.queryItems = [
            URLQueryItem(name: "ss", value: place), URLQueryItem(name: "checkin", value: checkIn.description),
            URLQueryItem(name: "checkout", value: checkOut.description), URLQueryItem(name: "group_adults", value: String(adults)),
            URLQueryItem(name: "group_children", value: String(children)), URLQueryItem(name: "no_rooms", value: "1"),
        ]
        return c?.url
    }

    /// Airbnb's search for the place: `checkin`, `checkout`, `adults` and, with children, `children`.
    public var airbnbURL: URL? {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        guard let path = place.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        var c = URLComponents(string: "https://www.airbnb.com/s/\(path)/homes")
        var items = [
            URLQueryItem(name: "checkin", value: checkIn.description), URLQueryItem(name: "checkout", value: checkOut.description),
            URLQueryItem(name: "adults", value: String(adults)),
        ]
        if children > 0 { items.append(URLQueryItem(name: "children", value: String(children))) }
        c?.queryItems = items
        return c?.url
    }

    /// "Lizbona · 12 lutego – 16 lutego · 4 noce · 2 osoby"
    public func summary(polish: Bool) -> String {
        let days = "\(TripCheckText.day(checkIn, polish: polish)) – \(TripCheckText.day(checkOut, polish: polish))"
        let nightsText: String
        if polish {
            nightsText = nights == 1 ? "1 noc" : (Self.polishFew(nights) ? "\(nights) noce" : "\(nights) nocy")
        } else {
            nightsText = nights == 1 ? "1 night" : "\(nights) nights"
        }
        let people = adults + children
        let peopleText: String
        if polish {
            peopleText = people == 1 ? "1 osoba" : (Self.polishFew(people) ? "\(people) osoby" : "\(people) osób")
        } else {
            peopleText = people == 1 ? "1 person" : "\(people) people"
        }
        return [place, days, nightsText, peopleText].joined(separator: " · ")
    }

    /// The words handed to Doddy's background research, in the same shape as `TripPlanText.stayResearchWords`.
    public var researchWords: String {
        let who = children > 0 ? "\(adults) dorosłych i \(children) dzieci" : (adults == 1 ? "1 osoby" : "\(adults) osób")
        return "Sprawdź noclegi. Miejsce: \(place). Od \(TripCheckText.day(checkIn, polish: true)) do \(TripCheckText.day(checkOut, polish: true)), dla \(who). Które okolice wybrać i dlaczego, przykładowe ceny za noc i za cały pobyt ze źródłem i datą sprawdzenia, oraz na co uważać."
    }

    /// Polish "2, 3, 4, 22, 23, 24…" take "noce"/"osoby"; the rest take the genitive plural.
    static func polishFew(_ n: Int) -> Bool {
        let last = n % 10, lastTwo = n % 100
        return (2...4).contains(last) && !(12...14).contains(lastTwo)
    }
}

/// How long a flight leg takes, for the boarding-pass cards: "2 h 55 min" / "2h 55m".
public enum TripDuration {
    public static func text(minutes: Int, polish: Bool) -> String {
        let h = max(0, minutes) / 60, m = max(0, minutes) % 60
        if polish { return h == 0 ? "\(m) min" : (m == 0 ? "\(h) h" : "\(h) h \(m) min") }
        return h == 0 ? "\(m)m" : (m == 0 ? "\(h)h" : "\(h)h \(m)m")
    }
}
