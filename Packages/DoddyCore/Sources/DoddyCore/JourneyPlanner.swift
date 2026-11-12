import Foundation

/// A provider-neutral journey request. No GPS is read and no private data is sent by constructing a link.
/// DODDY may add a licensed route provider later; until then, a handoff is NOT a retrieved itinerary.
public enum JourneyCity: String, CaseIterable, Equatable, Hashable, Sendable {
    case warszawa, krakow, wroclaw, poznan, gdansk, lodz
    case katowice, szczecin, lublin, bydgoszcz, torun, rzeszow

    public var label: String {
        switch self {
        case .warszawa: "Warszawa"
        case .krakow: "Kraków"
        case .wroclaw: "Wrocław"
        case .poznan: "Poznań"
        case .gdansk: "Gdańsk"
        case .lodz: "Łódź"
        case .katowice: "Katowice"
        case .szczecin: "Szczecin"
        case .lublin: "Lublin"
        case .bydgoszcz: "Bydgoszcz"
        case .torun: "Toruń"
        case .rzeszow: "Rzeszów"
        }
    }

    /// Recognise only an explicitly named city, not a guessed district, postal code or device location.
    /// If a start and destination name two different cities, use a different intercity planner.
    public static func named(in text: String) -> JourneyCity? {
        let tokens = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
            .lowercased().replacingOccurrences(of: "ł", with: "l")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let aliases: [(JourneyCity, Set<String>)] = [
            (.warszawa, ["warszawa", "warszawie"]),
            (.krakow, ["krakow", "krakowie"]),
            (.wroclaw, ["wroclaw", "wroclawiu"]),
            (.poznan, ["poznan", "poznaniu"]),
            (.gdansk, ["gdansk", "gdansku"]),
            (.lodz, ["lodz", "lodzi"]),
            (.katowice, ["katowice", "katowicach"]),
            (.szczecin, ["szczecin", "szczecinie"]),
            (.lublin, ["lublin", "lublinie"]),
            (.bydgoszcz, ["bydgoszcz", "bydgoszczy"]),
            (.torun, ["torun", "toruniu"]),
            (.rzeszow, ["rzeszow", "rzeszowie"])
        ]
        return aliases.first(where: { !$0.1.isDisjoint(with: Set(tokens)) })?.0
    }

    public static func recognised(from origin: String?, destination: String) -> JourneyCity? {
        let a = origin.flatMap(named(in:))
        let b = named(in: destination)
        if let a, let b, a != b { return nil }
        return a ?? b
    }
}

public enum JourneyTime: Equatable, Sendable {
    case depart(Date)
    case arrive(Date)
}

public enum JourneyPriority: String, Equatable, Sendable {
    case optimal, convenient, fastest

    var jakdojadeValue: String {
        switch self {
        case .optimal: "0"
        case .convenient: "1"
        case .fastest: "2"
        }
    }
}

public struct JourneyIntent: Equatable, Sendable {
    public let destination: String
    public let origin: String?
    public let city: JourneyCity
    public let when: JourneyTime?
    public let priority: JourneyPriority
    public let avoidTransfers: Bool
    public let avoidBuses: Bool

    public init(destination: String, origin: String? = nil, city: JourneyCity,
                when: JourneyTime? = nil, priority: JourneyPriority = .optimal,
                avoidTransfers: Bool = false, avoidBuses: Bool = false) {
        self.destination = destination
        self.origin = origin
        self.city = city
        self.when = when
        self.priority = priority
        self.avoidTransfers = avoidTransfers
        self.avoidBuses = avoidBuses
    }
}

public struct JourneyHandoff: Equatable, Sendable {
    public let url: URL
    /// With no explicit start name the official URL prefills the destination; it does not find a route.
    public let requiresOriginSelection: Bool
    public let city: JourneyCity
}

/// Public link parameters: https://docs.jakdojade.pl/parameters/basic/
/// and https://docs.jakdojade.pl/parameters/advanced/
/// Never use the authenticated partner endpoints until a licensed server-side provider exists.
public enum JakdojadeLinkBuilder {
    private static func clean(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value.count <= 160,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return value
    }

    public static func handoff(_ intent: JourneyIntent) -> JourneyHandoff? {
        guard let destination = clean(intent.destination) else { return nil }
        let origin = clean(intent.origin)
        // An explicitly supplied start must not silently disappear if it is malformed.
        if intent.origin != nil && origin == nil { return nil }
        // Reject a conflicting explicitly named city; no misleading intra-city search.
        if let origin, let named = JourneyCity.named(in: origin), named != intent.city { return nil }
        if let named = JourneyCity.named(in: destination), named != intent.city { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "jakdojade.pl"
        if let origin {
            // Official name-to-name link: /city/From/To. Encode each segment, including '/' and '?'.
            let encode: (String) -> String = {
                $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            }
            components.percentEncodedPath = "/\(intent.city.rawValue)/\(encode(origin))/\(encode(destination))"
        } else {
            // Official form-prefill link, NOT a computed itinerary (no starting location supplied).
            components.path = "/\(intent.city.rawValue)"
        }

        var params: [URLQueryItem] = []
        if origin == nil { params.append(URLQueryItem(name: "tn", value: destination)) }
        params.append(URLQueryItem(name: "t", value: intent.priority.jakdojadeValue))
        if intent.avoidTransfers { params.append(URLQueryItem(name: "aac", value: "true")) }
        if intent.avoidBuses { params.append(URLQueryItem(name: "aab", value: "true")) }
        if let when = intent.when {
            let date: Date
            let arrival: Bool
            switch when {
            case .depart(let value): date = value; arrival = false
            case .arrive(let value): date = value; arrival = true
            }
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(identifier: "Europe/Warsaw")!
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "dd.MM.yy"
            params.append(URLQueryItem(name: "d", value: formatter.string(from: date)))
            formatter.dateFormat = "HH:mm"
            params.append(URLQueryItem(name: "h", value: formatter.string(from: date)))
            params.append(URLQueryItem(name: "ia", value: arrival ? "true" : "false"))
        }
        components.queryItems = params
        guard let url = components.url, url.scheme == "https", url.host == "jakdojade.pl" else { return nil }
        return JourneyHandoff(url: url, requiresOriginSelection: origin == nil, city: intent.city)
    }
}

/// Both partners will eventually conform to this contract. The public-link variant cannot
/// return a route or timetable: those require licensed source data.
public protocol JourneyRouteProvider: Sendable {
    func routes(for request: JourneyIntent) async throws -> [JourneyRoute]
}
public struct JourneyRoute: Equatable, Sendable {
    public let source: String
    public let departs: Date
    public let arrives: Date
    public let segments: [JourneySegment]

    public init(source: String, departs: Date, arrives: Date, segments: [JourneySegment]) {
        self.source = source
        self.departs = departs
        self.arrives = arrives
        self.segments = segments
    }
}
public struct JourneySegment: Equatable, Sendable {
    public let line: String
    public let from: String
    public let to: String
    public init(line: String, from: String, to: String) {
        self.line = line
        self.from = from
        self.to = to
    }
}

extension MapTrip {
    /// Available only for explicit public-transport requests. City is user-specified or
    /// explicitly named in the request, not guessed from Warsaw or the user's GPS.
    public func jakdojadeHandoff(city userSelectedCity: JourneyCity? = nil) -> JourneyHandoff? {
        guard mode == .transit else { return nil }
        let city = userSelectedCity ?? JourneyCity.recognised(from: from, destination: place)
        guard let city else { return nil }
        return JakdojadeLinkBuilder.handoff(JourneyIntent(destination: place, origin: from, city: city))
    }
}
