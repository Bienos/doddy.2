import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Poland Pack ("My city" on screen since 13 Nov 2026): official read-only data only. No app login,
/// personal data, or payments.
public enum PolandCity: String, CaseIterable, Identifiable, Sendable {
    case warszawa, krakow, gdansk, wroclaw, poznan

    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .warszawa: "Warszawa"
        case .krakow: "Kraków"
        case .gdansk: "Gdańsk"
        case .wroclaw: "Wrocław"
        case .poznan: "Poznań"
        }
    }
    public var synopStation: String { rawValue }
    /// County-level TERYT prefix. A province-wide alert is not assumed to apply locally.
    public var countyTERYT: String {
        switch self {
        case .warszawa: "1465"
        case .krakow: "1261"
        case .gdansk: "2261"
        case .wroclaw: "0264"
        case .poznan: "3064"
        }
    }
}

public struct PolandWeather: Decodable, Sendable, Equatable {
    public let station: String
    public let date: String
    public let hour: String
    public let temperature: String?
    public let windMetersPerSecond: String?
    public let humidityPercent: String?
    public let precipitationMillimeters: String?

    enum CodingKeys: String, CodingKey {
        case station = "stacja", date = "data_pomiaru", hour = "godzina_pomiaru"
        case temperature = "temperatura"
        case windMetersPerSecond = "predkosc_wiatru"
        case humidityPercent = "wilgotnosc_wzgledna"
        case precipitationMillimeters = "suma_opadu"
    }

    public var observedAt: String { "\(date) \(hour):00" }
    /// A measurement, not a forecast; missing values never become zero.
    public var temperatureCelsius: Double? { Self.value(temperature) }
    public var wind: Double? { Self.value(windMetersPerSecond) }
    public var humidity: Double? { Self.value(humidityPercent) }
    public var precipitation: Double? { Self.value(precipitationMillimeters) }

    private static func value(_ raw: String?) -> Double? {
        guard let raw, let number = Double(raw.replacingOccurrences(of: ",", with: ".")), number.isFinite else { return nil }
        return number
    }
}

public struct PolandWeatherWarning: Decodable, Equatable, Sendable {
    public let event: String
    public let level: String?
    public let text: String?
    public let validFrom: String?
    public let validTo: String?
    public let counties: [String]

    enum CodingKeys: String, CodingKey {
        case event = "nazwa_zdarzenia", level = "stopien", text = "tresc"
        case validFrom = "obowiazuje_od", validTo = "obowiazuje_do", counties = "teryt"
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        event = (try? box.decode(String.self, forKey: .event)) ?? "Ostrzeżenie IMGW"
        level = try? box.decode(String.self, forKey: .level)
        text = try? box.decode(String.self, forKey: .text)
        validFrom = try? box.decode(String.self, forKey: .validFrom)
        validTo = try? box.decode(String.self, forKey: .validTo)
        counties = (try? box.decode([String].self, forKey: .counties)) ?? []
    }
}

public enum PolandWarnings: Sendable, Equatable {
    case noWarningsInPoland
    case matching([PolandWeatherWarning])
    /// Never infer 'no local warning' if the publisher supplied no location identifiers.
    case locationNotVerified

    public static func parse(_ data: Data, city: PolandCity) throws -> PolandWarnings {
        if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["message"] as? String,
           message.lowercased().contains("brak ostrzeżeń") { return .noWarningsInPoland }
        let warnings = try JSONDecoder().decode([PolandWeatherWarning].self, from: data)
        guard !warnings.isEmpty else { return .noWarningsInPoland }
        let found = warnings.filter { item in
            item.counties.contains { $0 == city.countyTERYT || $0.hasPrefix(city.countyTERYT) }
        }
        return found.isEmpty ? .locationNotVerified : .matching(found)
    }
}

public struct PolandAirStation: Sendable, Equatable {
    public let id: Int
    public let city: String
    public let name: String

    public static func find(in data: Data, city: PolandCity) throws -> PolandAirStation? {
        try all(in: data, city: city).first
    }

    /// More than one GIOŚ station may be present in a city. Some have no current AQI.
    public static func all(in data: Data, city: PolandCity) throws -> [PolandAirStation] {
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stations = response["Lista stacji pomiarowych"] as? [[String: Any]] else {
            throw PolandDataError.invalidResponse
        }
        // Exact city name; never silently show an unrelated station as local air quality.
        return stations.compactMap { record -> PolandAirStation? in
            guard let id = record["Identyfikator stacji"] as? Int,
                  let stationCity = record["Nazwa miasta"] as? String,
                  let title = record["Nazwa stacji"] as? String,
                  stationCity.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pl_PL"))
                    == city.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pl_PL"))
            else { return nil }
            return PolandAirStation(id: id, city: stationCity, name: title)
        }
    }
}

public struct PolandAirIndex: Sendable, Equatable {
    public let category: String
    public let value: Int
    public let station: String

    /// The Polish air quality index has six steps, 0 (very good) to 5 (very bad). My city draws all six
    /// and marks this one, with the step's name beside it, so colour is never the only sign.
    public static let steps = 6
    /// This reading's place on the scale, 0 ... `steps - 1`.
    public var step: Int { min(max(value, 0), Self.steps - 1) }

    public static func parse(_ data: Data, station: String) throws -> PolandAirIndex? {
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let index = response["AqIndex"] as? [String: Any] else {
            throw PolandDataError.invalidResponse
        }
        guard let category = index["Nazwa kategorii indeksu"] as? String,
              let number = index["Wartość indeksu"] as? Int,
              (0...5).contains(number),
              !category.lowercased().contains("brak indeksu") else { return nil }
        return PolandAirIndex(category: category, value: number, station: station)
    }
}

public struct PolandExchangeRate: Decodable, Equatable, Sendable {
    public struct Entry: Decodable, Equatable, Sendable {
        public let effectiveDate: String
        public let mid: Double
    }
    public let code: String
    public let rates: [Entry]

    public var latest: Entry? {
        guard let value = rates.first, value.mid.isFinite, value.mid > 0 else { return nil }
        return value
    }
    public func pln(for amount: Double) -> Double? {
        guard amount.isFinite, amount > 0, amount <= 1_000_000, let entry = latest else { return nil }
        return (amount * entry.mid * 100).rounded() / 100
    }
}

/// The amount typed in My city's currency card: up to seven digits, then up to two decimals after a comma
/// or a dot ("100", "12,50", "0.5"). Anything else is no amount, and the card says so; it never becomes 0.
public enum PolandAmount {
    public static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.range(of: #"^[0-9]{1,7}([,.][0-9]{1,2})?$"#, options: .regularExpression) != nil,
              let value = Double(cleaned.replacingOccurrences(of: ",", with: ".")), value.isFinite, value > 0
        else { return nil }
        return value
    }
}

public enum PolandDataError: Error, Equatable {
    case invalidResponse
    case unavailable
    case tooLarge
}

/// A tracking handoff is not parcel-account access and does not claim shipment status.
public enum PolandParcel {
    public static func trackingURL(number: String) -> URL? {
        let clean = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count == 24, clean.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        var link = URLComponents(string: "https://inpost.pl/sledzenie-przesylek")!
        link.queryItems = [URLQueryItem(name: "number", value: clean)]
        return link.url
    }
    public static let lockerFinder = URL(string: "https://inpost.pl/znajdz-paczkomat")!
}

/// Fixed allowlisted endpoints. The device sends only a manually selected city, never GPS coordinates.
public enum PolandOpenData {
    public static func weatherURL(city: PolandCity) -> URL {
        URL(string: "https://danepubliczne.imgw.pl/api/data/synop/station/\(city.synopStation)")!
    }
    public static let warningsURL = URL(string: "https://danepubliczne.imgw.pl/api/data/warningsmeteo")!
    public static let airStationsURL = URL(string: "https://api.gios.gov.pl/pjp-api/v1/rest/station/findAll?page=0&size=500")!
    public static func airIndexURL(stationID: Int) -> URL? {
        guard (1...1000000).contains(stationID) else { return nil }
        return URL(string: "https://api.gios.gov.pl/pjp-api/v1/rest/aqindex/getIndex/\(stationID)")
    }
    public static func exchangeRateURL(_ currency: String) -> URL? {
        let normalized = currency.uppercased()
        guard ["EUR", "USD", "GBP"].contains(normalized) else { return nil }
        return URL(string: "https://api.nbp.pl/api/exchangerates/rates/a/\(normalized.lowercased())/?format=json")
    }
}
