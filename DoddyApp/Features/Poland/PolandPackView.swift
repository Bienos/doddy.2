import DoddyCore
import Foundation
import SwiftUI

/// My city ("Moje miasto"; it was "Polska na co dzień" / Poland Pack until 13 Nov 2026, owner: "nie wiem, o co
/// tu chodzi … żeby było w kolorach Dodiego"): the weather now, IMGW's warnings and the air quality for one
/// Polish city, from official public sources, and NBP's exchange rates with a converter. Read only when the
/// page opens or is pulled down: no account, no location, nothing kept but the city picked. InPost parcels and
/// "Shopping in Poland" left this page; they live in Parcels and Shopping.
struct PolandPackView: View {
    /// Kept so Home's call stays the same; this page no longer links to the leaflets or the parcels.
    let dealsEnabled: Bool
    let parcelTrackingEnabled: Bool

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
    /// Until a read for this city has finished, every card shows that it's asking.
    private var waiting: Bool { isLoading || !hasLoaded }

    var body: some View {
        NavigationStack {
            DoddyPage {
                DoddyPageHeader(
                    eyebrow: "Poland",
                    title: "My city",
                    subtitle: "Weather, air and warnings for your city, from official sources, plus today's exchange rates.",
                    pose: .tiptoe)
                cityPicker
                CityWeatherCard(weather: weather, waiting: waiting)
                CityWarningsCard(warnings: warnings, waiting: waiting)
                CityAirCard(air: air, waiting: waiting)
                CityCurrencyCard(rates: rates, waiting: waiting, amount: $conversionAmount)
                DoddyFinePrint(text: Text("When this page opens or you pull it down, Doddy asks IMGW-PIB (weather and warnings), GIOŚ (air) and NBP (exchange rates) directly. Only the city you picked goes with a request, never where you are. The city stays on this iPhone."))
            }
            .refreshable { await refresh() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    .accessibilityLabel("Refresh")
                    .accessibilityIdentifier("poland.refresh")
                }
            }
            .task(id: cityCode) { await refresh() }
        }
    }

    // MARK: City

    private var cityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your city")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PolandCity.allCases) { place in
                        DoddyChip(
                            title: LocalizedStringKey(place.name),
                            systemImage: place == city ? "mappin" : nil,
                            isSelected: place == city
                        ) {
                            cityCode = place.rawValue
                        }
                        .accessibilityIdentifier("poland.city.\(place.rawValue)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Reading

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

// MARK: - Cards

/// A card's heading: Doddy's orange badge, the title, and the source it's read from.
private struct CityCardHeader: View {
    let systemImage: String
    let title: LocalizedStringKey
    let source: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            DoddyIconBadge(systemName: systemImage, size: 36)
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Text(verbatim: source)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

/// While a source is being asked.
private struct CityCardLoading: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A source that gave nothing usable: said in words, never shown as zero.
private struct CityCardMissing: View {
    let title: LocalizedStringKey

    var body: some View {
        Label {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "questionmark.circle")
        }
        .font(.subheadline)
        .foregroundStyle(Theme.secondaryText)
    }
}

/// A link out to the source's own page.
private struct CitySourceLink: View {
    let title: LocalizedStringKey
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "arrow.up.right").accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accentText)
            .frame(minHeight: 44, alignment: .leading)
        }
    }
}

private enum CityNumber {
    static func text(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func text(_ value: Double, digits: ClosedRange<Int>) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }
}

// MARK: Weather

private struct CityWeatherCard: View {
    let weather: PolandWeather?
    let waiting: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var bigSize: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var tileWidth: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CityCardHeader(systemImage: "thermometer.medium", title: "Weather now", source: "IMGW-PIB")
            content
        }
        .doddyCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("poland.weather")
    }

    @ViewBuilder
    private var content: some View {
        if waiting {
            CityCardLoading(title: "Asking IMGW-PIB…")
        } else if let weather {
            reading(weather)
        } else {
            CityCardMissing(title: "No weather reading right now: IMGW-PIB didn't answer, or this station has nothing new. Pull down to try again.")
        }
    }

    private func reading(_ weather: PolandWeather) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            temperature(weather.temperatureCelsius)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth), spacing: 10)], alignment: .leading, spacing: 10) {
                CityTile(systemImage: "wind", title: "Wind", value: weather.wind.map { CityNumber.text($0, digits: 1) + " m/s" })
                CityTile(systemImage: "cloud.rain", title: "Rain", value: weather.precipitation.map { CityNumber.text($0, digits: 1) + " mm" })
                CityTile(systemImage: "humidity", title: "Humidity", value: weather.humidity.map { ($0 / 100).formatted(.percent.precision(.fractionLength(0))) })
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(weather.station) · \(weather.observedAt)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Measured at an IMGW-PIB weather station: an observation, not a forecast.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func temperature(_ degrees: Double?) -> some View {
        if let degrees {
            let value = CityNumber.text(degrees, digits: 1) + "°C"
            Text(verbatim: value)
                .font(.system(size: bigSize, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityLabel(String(format: NSLocalizedString("Temperature %@", comment: "My city: the temperature now"), value))
        } else {
            Text("This reading has no temperature.")
                .font(.headline)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

/// One measurement under the big temperature.
private struct CityTile: View {
    let systemImage: String
    let title: LocalizedStringKey
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .accessibilityHidden(true)
            if let value {
                Text(verbatim: value)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.ink)
            } else {
                Text("Not reported")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Warnings

private struct CityWarningsCard: View {
    let warnings: PolandWarnings?
    let waiting: Bool

    private var hasWarning: Bool {
        if case .matching(let items) = warnings { !items.isEmpty } else { false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CityCardHeader(
                systemImage: hasWarning ? "exclamationmark.triangle.fill" : "exclamationmark.triangle",
                title: "Weather warnings",
                source: "IMGW-PIB")
            content
            CitySourceLink(title: "IMGW-PIB's own notices", url: URL(string: "https://meteo.imgw.pl/")!)
        }
        .doddyCard(accent: hasWarning)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("poland.warnings")
    }

    @ViewBuilder
    private var content: some View {
        if waiting {
            CityCardLoading(title: "Asking IMGW-PIB…")
        } else if let warnings {
            switch warnings {
            case .noWarningsInPoland:
                Label {
                    Text("No weather warnings: IMGW-PIB lists none in Poland right now.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
            case .locationNotVerified:
                Text("IMGW-PIB has warnings in Poland, but none lists this city's county. Check IMGW-PIB's notices to be sure.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            case .matching(let items):
                ForEach(items.indices, id: \.self) { index in
                    CityWarningRow(warning: items[index])
                }
            }
        } else {
            CityCardMissing(title: "Couldn't read IMGW-PIB's warnings just now. Pull down to try again.")
        }
    }
}

private struct CityWarningRow: View {
    let warning: PolandWeatherWarning

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: warning.event)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            if let level = warning.level {
                Text(verbatim: String(format: NSLocalizedString("Level %@", comment: "My city: an IMGW warning's level"), level))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
            if let detail = warning.text {
                Text(verbatim: detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let validTo = warning.validTo {
                Text(verbatim: String(format: NSLocalizedString("Valid until %@", comment: "My city: when an IMGW warning ends"), validTo))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Air

private struct CityAirCard: View {
    let air: PolandAirIndex?
    let waiting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CityCardHeader(systemImage: "aqi.medium", title: "Air quality", source: "GIOŚ")
            content
            CitySourceLink(title: "GIOŚ map", url: URL(string: "https://powietrze.gios.gov.pl/pjp/current")!)
        }
        .doddyCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("poland.air")
    }

    @ViewBuilder
    private var content: some View {
        if waiting {
            CityCardLoading(title: "Asking GIOŚ…")
        } else if let air {
            reading(air)
        } else {
            CityCardMissing(title: "No air quality index for this city right now: GIOŚ didn't answer, or none of its stations here has one. Pull down to try again.")
        }
    }

    private func reading(_ air: PolandAirIndex) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Self.category(air.step)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("on the Polish air quality index")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            CityAirScale(step: air.step)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: air.station)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("One station's reading, not a city-wide average. GIOŚ readings are preliminary and may be corrected later.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The index's six steps in the app's language (GIOŚ's own words are Polish).
    static func category(_ step: Int) -> Text {
        switch step {
        case 0: Text("Very good")
        case 1: Text("Good")
        case 2: Text("Moderate")
        case 3: Text("Sufficient")
        case 4: Text("Bad")
        default: Text("Very bad")
        }
    }
}

/// The index's six steps as a bar, this reading's step marked by size and outline as well as colour, and
/// written out, so colour is never the only sign.
private struct CityAirScale: View {
    let step: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<PolandAirIndex.steps, id: \.self) { index in
                    segment(current: index == step)
                }
            }
            .frame(height: 16)
            HStack(alignment: .firstTextBaseline) {
                Text("Very good")
                Spacer(minLength: 8)
                Text(verbatim: String(format: NSLocalizedString("Grade %lld of %lld", comment: "My city: the air index step"), step + 1, PolandAirIndex.steps))
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Text("Very bad")
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: NSLocalizedString("Grade %lld of %lld, from very good to very bad", comment: "My city: the air index scale"), step + 1, PolandAirIndex.steps))
    }

    private func segment(current: Bool) -> some View {
        Capsule()
            .fill(current ? Theme.orangeCue : Theme.separator)
            .frame(height: current ? 16 : 8)
            .overlay {
                if current { Capsule().strokeBorder(Theme.ink, lineWidth: 1.5) }
            }
            .frame(maxWidth: .infinity)
    }
}

// MARK: Currency

private struct CityCurrencyCard: View {
    let rates: [PolandExchangeRate]
    let waiting: Bool
    @Binding var amount: String

    private var amountValue: Double? { PolandAmount.parse(amount) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CityCardHeader(systemImage: "banknote", title: "Exchange rates", source: "NBP")
            amountField
            content
            Text("NBP's mid rate, not a bank's or an exchange office's rate. NBP publishes it on working days.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .doddyCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("poland.rates")
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How much in złoty?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            TextField("Amount, like 100", text: $amount)
                .keyboardType(.decimalPad)
                .font(.title3.monospacedDigit())
                .foregroundStyle(Theme.ink)
                .doddyField()
                .accessibilityIdentifier("poland.amount")
            if amountValue == nil {
                Text("Type an amount like 100 or 12,50 to convert it.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if waiting {
            CityCardLoading(title: "Asking NBP…")
        } else if rates.isEmpty {
            CityCardMissing(title: "Couldn't read NBP's rates just now. Pull down to try again.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rates, id: \.code) { rate in
                    if let entry = rate.latest {
                        CityRateRow(rate: rate, entry: entry, amount: amountValue)
                    }
                }
            }
        }
    }
}

/// One currency: the typed amount in złoty when there is one, and NBP's rate with its date.
private struct CityRateRow: View {
    let rate: PolandExchangeRate
    let entry: PolandExchangeRate.Entry
    let amount: Double?

    private var convertedLine: String? {
        guard let amount, let pln = rate.pln(for: amount) else { return nil }
        return "\(CityNumber.text(amount, digits: 0...2)) \(rate.code) = \(CityNumber.text(pln, digits: 2)) PLN"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: rate.code)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 2) {
                if let convertedLine {
                    Text(verbatim: convertedLine)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Theme.ink)
                }
                Text(verbatim: "1 \(rate.code) = \(CityNumber.text(entry.mid, digits: 4)) PLN · \(entry.effectiveDate)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Fetching

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
