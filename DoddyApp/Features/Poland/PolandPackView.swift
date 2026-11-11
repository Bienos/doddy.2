import DoddyCore
import Foundation
import SwiftUI

/// Poland Pack: real public-data reads, no accounts or background polling.
/// The screen is loaded only when requested; it adds no weight to voice startup.
struct PolandPackView: View {
    let dealsEnabled: Bool

    @Environment(\.dismiss) private var dismiss
    @AppStorage("polandPack.city") private var cityCode = PolandCity.warszawa.rawValue
    @State private var weather: PolandWeather?
    @State private var warnings: PolandWarnings?
    @State private var air: PolandAirIndex?
    @State private var rates: [PolandExchangeRate] = []
    @State private var stationListing: Data?
    @State private var shipmentNumber = ""
    @State private var conversionAmount = "100"
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var showDeals = false

    private var city: PolandCity { PolandCity(rawValue: cityCode) ?? .warszawa }
    private var polish: Bool { NotificationLanguage.current == .polish }
    private func t(_ pl: String, _ en: String) -> String { polish ? pl : en }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(t("Miasto", "City"), selection: $cityCode) {
                        ForEach(PolandCity.allCases) { city in
                            Text(city.name).tag(city.rawValue)
                        }
                    }
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(t("Pobieram dane ze źródeł urzędowych…", "Loading official data…"))
                                .font(.footnote)
                        }
                    } else if hasLoaded {
                        Text(t("Źródła są odczytywane na żądanie. Brak danych nie oznacza zera.", "Sources are read on demand. Missing data never means zero."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(t("Wybierz lokalizację", "Choose a location"))
                }

                Section {
                    if let weather {
                        if let degrees = weather.temperatureCelsius {
                            LabeledContent(t("Temperatura", "Temperature"), value: String(format: "%.1f °C", degrees))
                        }
                        if let wind = weather.wind {
                            LabeledContent(t("Wiatr", "Wind"), value: String(format: "%.1f m/s", wind))
                        }
                        if let rain = weather.precipitation {
                            LabeledContent(t("Opady", "Rainfall"), value: String(format: "%.1f mm", rain))
                        }
                        if let humidity = weather.humidity {
                            LabeledContent(t("Wilgotność", "Humidity"), value: String(format: "%.0f%%", humidity))
                        }
                        Text("\(weather.station) · \(weather.observedAt) · IMGW-PIB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        unavailable
                    }
                } header: {
                    Label(t("Pogoda teraz", "Current weather"), systemImage: "thermometer.medium")
                } footer: {
                    Text(t("Pomiar ze stacji IMGW — nie prognoza pogody.", "An IMGW station observation, not a forecast."))
                }

                Section {
                    if let warnings {
                        switch warnings {
                        case .noWarningsInPoland:
                            Text(t("IMGW nie publikuje obecnie ostrzeżeń meteorologicznych.", "IMGW currently reports no meteorological warnings."))
                        case .locationNotVerified:
                            Text(t("Nie mogę potwierdzić ostrzeżeń dla tego powiatu. Sprawdź komunikaty IMGW.", "County-specific warning status could not be verified. Check IMGW notices."))
                        case .matching(let items):
                            ForEach(items.indices, id: \.self) { i in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(items[i].event).font(.headline)
                                    if let level = items[i].level { Text(t("Stopień: ", "Level: ") + level) }
                                    if let detail = items[i].text { Text(detail).font(.subheadline) }
                                    if let validTo = items[i].validTo {
                                        Text(t("Ważne do: ", "Valid until: ") + validTo)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } else {
                        unavailable
                    }
                    Link(t("Komunikaty IMGW", "Official IMGW notices"),
                         destination: URL(string: "https://meteo.imgw.pl/")!)
                } header: {
                    Label(t("Ostrzeżenia pogodowe", "Weather warnings"), systemImage: "exclamationmark.triangle")
                }

                Section {
                    if let air {
                        LabeledContent(t("Polski indeks", "Polish air index"), value: air.category)
                        Text(air.station).font(.footnote)
                        Text(t("GIOŚ · Wskazanie jednej stacji, nie średnia z całego miasta.", "GIOŚ · One station's reading, not a citywide average."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        unavailable
                    }
                    Link(t("Sprawdź mapę GIOŚ", "Open GIOŚ map"),
                         destination: URL(string: "https://powietrze.gios.gov.pl/pjp/current")!)
                } header: {
                    Label(t("Jakość powietrza", "Air quality"), systemImage: "aqi.medium")
                } footer: {
                    Text(t("GIOŚ publikuje wstępne odczyty; mogą zostać później skorygowane.", "GIOŚ readings are preliminary and may be revised."))
                }

                Section {
                    TextField(t("Kwota, np. 100", "Amount, e.g. 100"), text: $conversionAmount)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("poland.amount")
                    if rates.isEmpty { unavailable }
                    ForEach(rates, id: \.code) { rate in
                        if let entry = rate.latest {
                            VStack(alignment: .leading, spacing: 3) {
                                LabeledContent("1 \(rate.code)", value: String(format: "%.4f PLN", entry.mid))
                                if let amount = amountValue, let pln = rate.pln(for: amount) {
                                    Text(String(format: "%.2f %@ = %.2f PLN", amount, rate.code, pln))
                                        .font(.footnote)
                                }
                                Text("NBP · \(entry.effectiveDate)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Label(t("Kursy NBP i przelicznik", "NBP rates and converter"), systemImage: "polishzlotysign.circle")
                } footer: {
                    Text(t("Kurs średni NBP, nie kurs transakcyjny banku ani kantoru.", "NBP reference rate, not a bank or exchange office transaction rate."))
                }

                Section {
                    TextField(t("24-cyfrowy numer paczki", "24-digit tracking number"), text: $shipmentNumber)
                        .keyboardType(.numberPad)
                        .textContentType(.none)
                        .accessibilityIdentifier("poland.parcel.number")
                    if let link = PolandParcel.trackingURL(number: shipmentNumber) {
                        Link(t("Śledź na stronie InPost", "Track on InPost"), destination: link)
                    } else {
                        Text(t("Wpisz poprawny 24-cyfrowy numer, aby otworzyć śledzenie.", "Enter a valid 24-digit number to open tracking."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Link(t("Znajdź Paczkomat lub PaczkoPunkt", "Find a parcel locker or pickup point"),
                         destination: PolandParcel.lockerFinder)
                } header: {
                    Label(t("Paczki InPost", "InPost parcels"), systemImage: "shippingbox")
                } footer: {
                    Text(t("DODDY nie odczytuje statusu paczki ani konta InPost. Link otwiera oficjalny serwis.", "DODDY does not read your parcel status or InPost account. Links open the official service."))
                }

                if dealsEnabled {
                    Section {
                        Button {
                            showDeals = true
                        } label: {
                            Label(t("Sprawdź Biedronkę, Lidla i inne gazetki", "Compare Biedronka, Lidl and other leaflets"),
                                  systemImage: "cart")
                        }
                    } header: {
                        Text(t("Zakupy w Polsce", "Shopping in Poland"))
                    } footer: {
                        Text(t("Otwiera istniejące porównanie promocji i koszyka w DODDY.", "Opens DODDY's existing grocery-deals and basket comparison."))
                    }
                }
            }
            .navigationTitle(t("Polska na co dzień", "Poland Pack"))
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
            .sheet(isPresented: $showDeals) { DealsView() }
        }
    }

    private var unavailable: some View {
        Text(t("Brak aktualnych danych. Sprawdź źródło lub spróbuj ponownie.", "Current data unavailable. Check the source or retry."))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var amountValue: Double? {
        let cleaned = conversionAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.range(of: #"^[0-9]{1,7}([,.][0-9]{1,2})?$"#, options: .regularExpression) != nil
        else { return nil }
        return Double(cleaned.replacingOccurrences(of: ",", with: "."))
    }

    private func refresh() async {
        guard !isLoading else { return }
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
            stationListing = try? await PolandPackFetcher.data(PolandOpenData.airStationsURL)
        }
        var candidateAir: PolandAirIndex?
        if let data = stationListing,
           let station = try? PolandAirStation.find(in: data, city: chosen),
           let url = PolandOpenData.airIndexURL(stationID: station.id),
           let payload = try? await PolandPackFetcher.data(url) {
            candidateAir = try? PolandAirIndex.parse(payload, station: station.name)
        }

        let newWeather = await weatherResult
        let newWarnings = await warningResult
        let newRates = await currencyResult
        guard !Task.isCancelled, chosen == city else {
            isLoading = false
            return
        }
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
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json, application/ld+json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PolandDataError.unavailable
        }
        guard bytes.count <= 2_000_000 else { throw PolandDataError.tooLarge }
        return bytes
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
