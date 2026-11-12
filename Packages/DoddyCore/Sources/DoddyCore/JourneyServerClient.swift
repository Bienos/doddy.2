import Foundation

/// Real, licensed Jakdojade responses via DODDY's signed-in messaging server.
/// These are read-only source data; absent partner credentials give 503, never demo routes.
public struct JourneyCoordinate: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite &&
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

public struct JourneyProviderStatus: Decodable, Equatable, Sendable {
    public let provider: String
    public let available: Bool
    public let capabilities: [String]
    public let tickets: Bool
    public let realtime: Bool
}

public struct JourneyPartnerPlace: Decodable, Equatable, Sendable {
    public let name: String
    public let type: String
    public let coordinate: JourneyCoordinate
    public let stopCode: String?
}

public struct JourneyPartnerStop: Decodable, Equatable, Sendable {
    public let name: String
    public let departure: String?
    public let arrival: String?
}

public struct JourneyPartnerSegment: Decodable, Equatable, Sendable {
    public let line: String
    public let vehicleType: String
    public let direction: String?
    public let stops: [JourneyPartnerStop]
}

public struct JourneyPartnerRoute: Decodable, Equatable, Sendable {
    public let source: String
    public let startLocal: String
    public let finishLocal: String
    public let segments: [JourneyPartnerSegment]

    /// Never invent dates. The partner publishes Warsaw-local date/time without an offset.
    public func normalized(timeZone: TimeZone = TimeZone(identifier: "Europe/Warsaw")!) -> JourneyRoute? {
        guard source == "Jakdojade", !segments.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.isLenient = false
        formatter.dateFormat = "dd.MM.yy HH:mm"
        guard let first = formatter.date(from: startLocal),
              let last = formatter.date(from: finishLocal),
              last >= first, last.timeIntervalSince(first) <= 24 * 60 * 60 else { return nil }
        let steps = segments.compactMap { segment -> JourneySegment? in
            guard let from = segment.stops.first?.name, !from.isEmpty,
                  let to = segment.stops.last?.name, !to.isEmpty else { return nil }
            return JourneySegment(line: segment.line, from: from, to: to)
        }
        guard steps.count == segments.count else { return nil }
        return JourneyRoute(source: source, departs: first, arrives: last, segments: steps)
    }
}

public struct JourneyPartnerRoutes: Decodable, Equatable, Sendable {
    public let source: String
    public let fetchedAt: String
    public let routes: [JourneyPartnerRoute]
    public let realtime: Bool
    public let tickets: Bool
}

public struct JourneyPartnerPlaces: Decodable, Equatable, Sendable {
    public let source: String
    public let fetchedAt: String
    public let locations: [JourneyPartnerPlace]
}

public enum JourneyBackendError: Error, Equatable, Sendable {
    case invalid
    case unavailable
    case server(ServerError)
}

/// Only coordinates consented to by the user are sent to DODDY's own server.
/// There is no Wykop/Jakdojade credential, GPS reader, trip cache or background tracking here.
public struct JourneyRouteQuery: Encodable, Equatable, Sendable {
    public let from: JourneyCoordinate
    public let to: JourneyCoordinate
    public let day: String?
    public let hour: String?
    public let arriving: Bool?
    public let mode: String?
    public let avoidBuses: Bool?
    public let avoidTransfers: Bool?

    public init(from: JourneyCoordinate, to: JourneyCoordinate, day: String? = nil, hour: String? = nil,
                arriving: Bool? = nil, mode: String? = nil,
                avoidBuses: Bool? = nil, avoidTransfers: Bool? = nil) {
        self.from = from
        self.to = to
        self.day = day
        self.hour = hour
        self.arriving = arriving
        self.mode = mode
        self.avoidBuses = avoidBuses
        self.avoidTransfers = avoidTransfers
    }

    public var isValid: Bool {
        from.isValid && to.isValid
            && (day == nil || day!.range(of: #"^\d{2}\.\d{2}\.\d{2}$"#, options: .regularExpression) != nil)
            && (hour == nil || hour!.range(of: #"^(?:[01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil)
            && (mode == nil || ["optimal", "convenient", "hurry"].contains(mode!))
    }
}

private struct JourneyPlaceQuery: Encodable {
    let city: String
    let query: String
}

extension VoiceToolReply {
    /// Only after a licensed provider returned source routes; never convert an empty/malformed
    /// reply into invented times, destinations or ticket prices.
    public static func licensedJourneys(_ response: JourneyPartnerRoutes, calendar: Calendar = .current) -> String {
        let routes = response.routes.prefix(3).compactMap { $0.normalized() }
        guard response.source == "Jakdojade", !routes.isEmpty else {
            return "not found: Jakdojade did not return any complete route. Suggest opening Jakdojade to search manually."
        }
        let lines = routes.enumerated().map { index, route -> String in
            let from = route.departs.formatted(date: .abbreviated, time: .shortened)
            let to = route.arrives.formatted(date: .abbreviated, time: .shortened)
            let steps = route.segments.map { "\($0.line): \($0.from) → \($0.to)" }
                .joined(separator: "; ")
            return "Option \(index + 1): \(from) to \(to); \(steps)"
        }
        return "found: Licensed Jakdojade scheduled transit connections, checked at \(response.fetchedAt). "
            + "Not live vehicle positions or confirmed punctuality. No ticket purchase was made. "
            + "These times came from the source, not Doddy; do not invent other lines.\\n"
            + ToolData.block(lines)
    }
}

extension DoddyServerClient {
    public func journeyProviderStatus() async throws -> JourneyProviderStatus {
        let response = try await authorized(.get, "/v1/journeys/provider", body: nil)
        guard response.status == 200,
              let result = try? JSONDecoder().decode(JourneyProviderStatus.self, from: response.body)
        else { throw Self.error(from: response) }
        return result
    }

    public func journeyPlaces(city: JourneyCity, text: String) async throws -> JourneyPartnerPlaces {
        let search = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...100).contains(search.count), !search.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw JourneyBackendError.invalid
        }
        let body = JourneyPlaceQuery(city: city.rawValue.uppercased(), query: search)
        let response = try await authorized(.post, "/v1/journeys/places", body: try Self.json(body))
        guard response.status == 200,
              let result = try? JSONDecoder().decode(JourneyPartnerPlaces.self, from: response.body),
              result.source == "Jakdojade" else { throw JourneyBackendError.server(Self.error(from: response)) }
        return result
    }

    public func journeyRoutes(_ query: JourneyRouteQuery) async throws -> JourneyPartnerRoutes {
        guard query.isValid else { throw JourneyBackendError.invalid }
        let response = try await authorized(.post, "/v1/journeys/routes", body: try Self.json(query))
        guard response.status == 200,
              let result = try? JSONDecoder().decode(JourneyPartnerRoutes.self, from: response.body),
              result.source == "Jakdojade", result.routes.count <= 3,
              result.routes.allSatisfy({ $0.source == "Jakdojade" }) else {
            throw JourneyBackendError.server(Self.error(from: response))
        }
        return result
    }
}
