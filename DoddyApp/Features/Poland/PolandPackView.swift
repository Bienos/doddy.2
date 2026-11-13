import DoddyCore
import Foundation
import SwiftUI

/// My city (owner, 13 Nov 2026: "Polska na co dzień … nie wiem, o co tu chodzi … rzeczy się powtarzają"): what was the
/// Poland Pack, cut to what only it shows and laid out as tiles in Doddy's colours. The weather now (IMGW), weather
/// warnings for the city's county (IMGW), the air (GIOŚ) and NBP's reference rates with a converter, all read from
/// public sources when the screen opens; no accounts, no background polling, nothing added to voice startup. The
/// leaflets row and the InPost section left: leaflets are in Shopping, parcels in Settings › Parcels.
struct PolandPackView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("polandPack.city") private var cityCode = PolandCity.warszawa.rawValue
    @State private var weather: PolandWeather?
    @State private var warnings: PolandWarnings?
    @State private var air: PolandAirIndex?
    @State private var rates: [PolandExchangeRate] = []
    @State private var stationListing: Data?
    @State private var conversionAmount = "100"
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var currentRequestID = UUID()

    private var city: PolandCity { PolandCity(rawValue: cityCode) ?? .warszawa }
    private var polish: Bool { NotificationLanguage.current == .polish }
    private func t(_ pl: String, _ en: String) -> String { polish ? pl : en }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    weatherHero
                    HStack(alignment: .top, spacing: 12) {
                        airTile
                        warningsTile
                    }
                    warningDetails
                    ratesCard
                    DoddyFootnote(text: t("Źródła są odczytywane na żądanie: IMGW-PIB, GIOŚ i NBP. Brak danych nie oznacza zera.",
                                          "Read on demand from IMGW-PIB, GIOŚ and NBP. Missing data never means zero."),
                                  systemImage: "building.columns")
                }
                .padding(16)
                .readableColumn()
            }
            .doddyScreen()
            .navigationTitle(t("Moje miasto", "My city"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(t("Zamknij", "Close")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    .accessibilityLabel(t("Odśwież dane", "Refresh data"))
                }
            }
            .refreshable { await refresh() }
            .task(id: cityCode) { await refresh() }
        }
    }

    // MARK: Weather

    private var weatherHero: some View {
        DoddyHero(title: city.name, subtitle: t("Pogoda teraz, ze stacji IMGW", "The weather now, from an IMGW station"), pose: .leaning) {
            if let weather, let degrees = weather.temperatureCelsius {
                Text(verbatim: String(format: "%.0f°", degrees))
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .accessibilityLabel(Text(verbatim: String(format: t("%.1f stopnia", "%.1f degrees"), degrees)))
                Text(verbatim: weatherLine(weather))
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: "\(weather.station) · \(weather.observedAt) · IMGW-PIB")
                    .font(.caption)
                    .opacity(0.8)
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.inkOnOrange)
                    Text(verbatim: t("Pobieram dane ze źródeł urzędowych…", "Loading official data…")).font(.subheadline)
                }
            } else if hasLoaded {
                Text(verbatim: t("IMGW nie podał teraz pomiaru dla tej stacji.", "IMGW has no reading for this station right now."))
                    .font(.subheadline)
            }
            Menu {
                Picker(t("Miasto", "City"), selection: $cityCode) {
                    ForEach(PolandCity.allCases) { city in
                        Text(verbatim: city.name).tag(city.rawValue)
                    }
                }
            } label: {
                Label(t("Zmień miasto", "Change city"), systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Theme.canvas.opacity(0.55), in: Capsule())
                    .frame(minHeight: 44)
            }
            .foregroundStyle(Theme.inkOnOrange)
            .accessibilityIdentifier("poland.city")
        }
    }

    private func weatherLine(_ w: PolandWeather) -> String {
        var parts: [String] = []
        if let wind = w.wind { parts.append(String(format: t("wiatr %.1f m/s", "wind %.1f m/s"), wind)) }
        if let rain = w.precipitation { parts.append(String(format: t("opady %.1f mm", "rain %.1f mm"), rain)) }
        if let humidity = w.humidity { parts.append(String(format: t("wilgotność %.0f%%", "humidity %.0f%%"), humidity)) }
        return parts.joined(separator: " · ")
    }

    // MARK: Tiles

    private var airTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(t("Powietrze", "Air"), systemImage: "aqi.medium")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            if let air {
                HStack(spacing: 8) {
                    Circle().fill(airColour(air.category)).frame(width: 12, height: 12).accessibilityHidden(true)
                    Text(verbatim: air.category)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(verbatim: air.station).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(2)
                Text(verbatim: t("GIOŚ · jedna stacja, wstępny odczyt", "GIOŚ · one station, preliminary"))
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                unavailable
            }
            Link(t("Mapa GIOŚ", "GIOŚ map"), destination: URL(string: "https://powietrze.gios.gov.pl/pjp/current")!)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .doddyCard(padding: 14)
    }

    /// The Polish index's six words, from good to bad; the dot only repeats what the word says.
    private func airColour(_ category: String) -> Color {
        let c = category.lowercased()
        if c.contains("bardzo zły") || c.contains("very bad") || c.contains("zły") || c.contains("bad") { return Theme.error }
        if c.contains("dostateczny") || c.contains("umiarkowany") || c.contains("moderate") || c.contains("sufficient") { return Theme.orangeCue }
        return Theme.confirmed
    }

    private var warningsTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(t("Ostrzeżenia", "Warnings"), systemImage: "exclamationmark.triangle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            switch warnings {
            case .none:
                unavailable
            case .noWarningsInPoland?:
                Text(verbatim: t("Brak", "None")).font(.system(.title3, design: .rounded, weight: .bold))
                Text(verbatim: t("IMGW nie publikuje teraz ostrzeżeń.", "IMGW reports no warnings now."))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            case .locationNotVerified?:
                Text(verbatim: t("Nie wiem", "Not sure")).font(.system(.title3, design: .rounded, weight: .bold))
                Text(verbatim: t("Nie mogę potwierdzić ostrzeżeń dla tego powiatu.", "I can't confirm warnings for this county."))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            case .matching(let items)?:
                Text(verbatim: items.isEmpty ? t("Brak dla miasta", "None here") : String(format: t("Aktywne: %lld", "Active: %lld"), items.count))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(items.isEmpty ? Theme.ink : Theme.error)
                if let first = items.first {
                    Text(verbatim: first.event).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(2)
                }
            }
            Link(t("Komunikaty IMGW", "IMGW notices"), destination: URL(string: "https://meteo.imgw.pl/")!)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .doddyCard(padding: 14)
    }

    @ViewBuilder private var warningDetails: some View {
        if case .matching(let items)? = warnings, !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(items.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(verbatim: items[i].event).font(.headline)
                            Spacer()
                            if let level = items[i].level { DoddyTag(text: t("Stopień ", "Level ") + level, strong: true) }
                        }
                        if let detail = items[i].text { Text(verbatim: detail).font(.subheadline) }
                        if let validTo = items[i].validTo {
                            Text(verbatim: t("Ważne do: ", "Valid until: ") + validTo)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
            .doddyCard()
        }
    }

    // MARK: Rates

    private var ratesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                DoddySymbolTile(systemImage: "polishzlotysign", size: 36)
                Text(verbatim: t("Kursy NBP i przelicznik", "NBP rates and converter"))
                    .font(.system(.headline, design: .rounded))
            }
            HStack(spacing: 8) {
                TextField(t("Kwota, np. 100", "Amount, e.g. 100"), text: $conversionAmount)
                    .keyboardType(.decimalPad)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("poland.amount")
                Text(verbatim: t("w walucie →  zł", "in currency → PLN"))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            if rates.isEmpty { unavailable }
            ForEach(rates, id: \.code) { rate in
                if let entry = rate.latest {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: rate.code).font(.system(.headline, design: .rounded, weight: .heavy))
                        Text(verbatim: String(format: "%.4f zł", entry.mid))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        if let amount = amountValue, let pln = rate.pln(for: amount) {
                            Text(verbatim: String(format: "%.2f zł", pln))
                                .font(.headline.monospacedDigit())
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
            if let date = rates.compactMap({ $0.latest?.effectiveDate }).first {
                Text(verbatim: t("Kurs średni NBP z \(date), nie kurs banku ani kantoru.", "NBP reference rate of \(date), not a bank's or exchange office's rate."))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .doddyCard()
    }

    private var unavailable: some View {
        Text(verbatim: t("Brak aktualnych danych. Sprawdź źródło lub spróbuj ponownie.", "Current data unavailable. Check the source or retry."))
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
    }

    private var amountValue: Double? {
        let cleaned = conversionAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.range(of: #"^[0-9]{1,7}([,.][0-9]{1,2})?$"#, options: .regularExpression) != nil
        else { return nil }
        return Double(cleaned.replacingOccurrences(of: ",", with: "."))
    }

    private func refresh() async {
        let requestID = UUID()
        currentRequestID = requestID
        isLoading = true
        weather = nil
        warnings = nil
        air = nil
        rates = []
        let chosen = city

        async let weatherResult: PolandWeather? = try? await PolandPackFetcher.weather(chosen)
        async let warningResult: PolandWarnings? = try? await PolandPackFetcher.warnings(chosen)
        async let currencyResult: [PolandExchangeRate] = await PolandPackFetcher.exchangeRates()

        // Stations are the slowest GIOŚ endpoint (2 req/min). Cache the static listing in this sheet
        // across city changes and refresh gestures. The index itself is read each time.
        if stationListing == nil {
            stationListing = try? await PolandStationsCache.shared.current()
        }
        var candidateAir: PolandAirIndex?
        if let data = stationListing, let stations = try? PolandAirStation.all(in: data, city: chosen) {
            // Several stations may lack an overall index. Check a bounded number, never
            // guess a category or quietly fall back to an unrelated city's monitor.
            for station in stations.prefix(5) {
                guard !Task.isCancelled, requestID == currentRequestID else { break }
                if let url = PolandOpenData.airIndexURL(stationID: station.id),
                   let payload = try? await PolandPackFetcher.data(url),
                   let reading = try? PolandAirIndex.parse(payload, station: station.name) {
                    candidateAir = reading
                    break
                }
            }
        }

        let newWeather = await weatherResult
        let newWarnings = await warningResult
        let newRates = await currencyResult
        guard !Task.isCancelled, chosen == city, requestID == currentRequestID else { return }
        weather = newWeather
        warnings = newWarnings
        air = candidateAir
        rates = newRates
        hasLoaded = true
        isLoading = false
    }
}

private enum PolandPackFetcher {
    static func data(_ url: URL) async throws -> Data {
        // The repository's approved, ephemeral, no-redirect transport keeps networking
        // out of the SwiftUI view and enforces its hard response size limit.
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
    static func exchangeRates() async -> [PolandExchangeRate] {
        async let eur = exchangeRate("EUR")
        async let usd = exchangeRate("USD")
        async let gbp = exchangeRate("GBP")
        return [await eur, await usd, await gbp].compactMap { $0 }
    }
    private static func exchangeRate(_ code: String) async -> PolandExchangeRate? {
        guard let url = PolandOpenData.exchangeRateURL(code),
              let payload = try? await data(url),
              let result = try? JSONDecoder().decode(PolandExchangeRate.self, from: payload),
              result.latest != nil else { return nil }
        return result
    }
}

/// In-memory metadata cache across sheet re-openings; GIOŚ throttles station-list requests.
private actor PolandStationsCache {
    static let shared = PolandStationsCache()
    private var cached: (date: Date, data: Data)?

    func current() async throws -> Data {
        if let cached, Date().timeIntervalSince(cached.date) < 15 * 60 { return cached.data }
        let listing = try await PolandPackFetcher.data(PolandOpenData.airStationsURL)
        cached = (Date(), listing)
        return listing
    }
}
