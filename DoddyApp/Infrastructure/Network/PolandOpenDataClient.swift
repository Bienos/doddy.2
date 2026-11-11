import DoddyCore
import Foundation

/// Official Polish open-data readers shared by the Poland Pack UI and the voice agent.
/// All HTTP goes through DODDY's approved, ephemeral, no-redirect AppHTTPTransport.
/// Nothing loads before a user opens Poland Pack or makes an approved voice request.
enum PolandPackFetcher {
    static func data(_ url: URL) async throws -> Data {
        let response = try await AppHTTPTransport().send(GatewayHTTPRequest(
            url: url,
            method: "GET",
            headers: ["Accept": "application/json, application/ld+json"],
            body: nil,
            timeout: 12
        ))
        guard response.status == 200 else { throw PolandDataError.unavailable }
        return response.body
    }

    static func weather(_ city: PolandCity) async throws -> PolandWeather {
        try JSONDecoder().decode(PolandWeather.self, from: await data(PolandOpenData.weatherURL(city: city)))
    }

    static func warnings(_ city: PolandCity) async throws -> PolandWarnings {
        try PolandWarnings.parse(await data(PolandOpenData.warningsURL), city: city)
    }

    static func exchangeRate(_ currency: String) async -> PolandExchangeRate? {
        guard let url = PolandOpenData.exchangeRateURL(currency),
              let payload = try? await data(url),
              let result = try? JSONDecoder().decode(PolandExchangeRate.self, from: payload),
              result.latest != nil else { return nil }
        return result
    }

    static func exchangeRates() async -> [PolandExchangeRate] {
        async let eur = exchangeRate("EUR")
        async let usd = exchangeRate("USD")
        async let gbp = exchangeRate("GBP")
        return [await eur, await usd, await gbp].compactMap { $0 }
    }

    /// GIOŚ indexes are per station; fail closed if no station in this city has a valid index.
    static func air(_ city: PolandCity) async -> PolandAirIndex? {
        guard let payload = try? await PolandStationsCache.shared.current(),
              let stations = try? PolandAirStation.all(in: payload, city: city) else { return nil }
        for station in stations.prefix(5) {
            guard !Task.isCancelled else { return nil }
            if let url = PolandOpenData.airIndexURL(stationID: station.id),
               let payload = try? await data(url),
               let index = try? PolandAirIndex.parse(payload, station: station.name) {
                return index
            }
        }
        return nil
    }
}

/// Metadata cached in memory only (no persistent index or tracking). Keep API use low.
private actor PolandStationsCache {
    static let shared = PolandStationsCache()
    private var cached: (date: Date, data: Data)?

    func current() async throws -> Data {
        if let cached, Date().timeIntervalSince(cached.date) < 15 * 60 { return cached.data }
        let payload = try await PolandPackFetcher.data(PolandOpenData.airStationsURL)
        cached = (Date(), payload)
        return payload
    }
}

/// Text results deliberately include the source and reference time when supplied by the publisher.
/// No model-generated facts, coordinates, personalized data or checkout actions.
enum PolandVoiceReader {
    static func answer(_ query: PolandVoiceRequest, polish: Bool) async -> String {
        let unavailable = polish
            ? "Nie udało się potwierdzić aktualnych danych w oficjalnym źródle. Nie zgaduj wyniku."
            : "The official source did not return verifiable data. Do not guess a result."
        switch query.topic {
        case .weather:
            guard let city = query.city, let measurement = try? await PolandPackFetcher.weather(city) else {
                return unavailable
            }
            let temp = measurement.temperatureCelsius.map { String(format: "%.1f °C", $0) }
                ?? (polish ? "brak pomiaru" : "not measured")
            let wind = measurement.wind.map { String(format: "%.1f m/s", $0) }
            let rain = measurement.precipitation.map { String(format: "%.1f mm", $0) }
            let parts = [wind.map { (polish ? "wiatr " : "wind ") + $0 },
                         rain.map { (polish ? "opady " : "precipitation ") + $0 }].compactMap { $0 }
            return (polish ? "IMGW-PIB, obserwacja ze stacji " : "IMGW-PIB station observation: ")
                + measurement.station + " (" + measurement.observedAt + "): "
                + temp + (parts.isEmpty ? "" : "; " + parts.joined(separator: "; "))
                + (polish ? ". To pomiar, nie prognoza." : ". This is an observation, not a forecast.")
        case .warnings:
            guard let city = query.city, let status = try? await PolandPackFetcher.warnings(city) else {
                return unavailable
            }
            switch status {
            case .noWarningsInPoland:
                return polish ? "Źródło IMGW nie zgłasza teraz ostrzeżeń meteorologicznych w Polsce."
                    : "IMGW currently reports no weather warnings in Poland."
            case .locationNotVerified:
                return polish
                    ? "IMGW zwraca ostrzeżenia, lecz nie potwierdziłem ich zakresu dla \(city.name). Sprawdź meteo.imgw.pl."
                    : "IMGW returned warnings, but their applicability to \(city.name) was not verified. Check meteo.imgw.pl."
            case .matching(let items):
                let summary = items.prefix(3).map { alert in
                    alert.event + (alert.level.map { " (\($0))" } ?? "")
                        + (alert.validTo.map { " do/until \($0)" } ?? "")
                }.joined(separator: "; ")
                return "IMGW · \(city.name): \(summary). "
                    + (polish ? "Sprawdź szczegóły na meteo.imgw.pl." : "Check details at meteo.imgw.pl.")
            }
        case .air:
            guard let city = query.city, let index = await PolandPackFetcher.air(city) else {
                return unavailable
            }
            return (polish ? "GIOŚ, stacja " : "GIOŚ station ")
                + index.station + " (\(city.name)): "
                + index.category + ". "
                + (polish ? "To indeks z jednej stacji, nie średnia dla całego miasta."
                   : "This is one station's index, not a city-wide average.")
        case .rates:
            let rates = await PolandPackFetcher.exchangeRates()
            guard !rates.isEmpty else { return unavailable }
            let values = rates.compactMap { rate -> String? in
                guard let latest = rate.latest else { return nil }
                return "1 \(rate.code) = \(String(format: "%.4f", latest.mid)) PLN (NBP \(latest.effectiveDate))"
            }
            return (polish ? "Średnie kursy referencyjne NBP: " : "NBP reference exchange rates: ")
                + values.joined(separator: "; ") + ". "
                + (polish ? "To nie jest kurs kupna lub sprzedaży banku."
                   : "These are not bank buying or selling rates.")
        }
    }
}
