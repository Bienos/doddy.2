import Foundation

// Bookings become trips (docs/implementation/TRAVEL_EMAILS.md, "Trips"): bookings whose days touch or
// overlap, give or take one day, are one trip. Only bookings to plan around (booked, changed) and ones
// waiting for the seller go into a trip; cancelled and failed bookings stay out and are listed apart.

public struct Trip: Equatable, Sendable, Identifiable {
    public let id: String
    public let bookings: [TravelBooking]
    public let start: TripDay
    public let end: TripDay
    /// Where the trip goes, in order, as the emails name it ("Lizbona", "Porto").
    public let places: [String]
    /// ISO countries the trip goes to (not the home country), from the airports and stays it can place.
    public let countries: [String]
    /// The country the first flight leaves from, when Doddy knows the airport; else Poland.
    public let homeCountry: String

    public enum When: Equatable, Sendable { case upcoming(days: Int), ongoing, past }

    public func when(today: TripDay) -> When {
        if today < start { return .upcoming(days: today.days(to: start)) }
        if today > end { return .past }
        return .ongoing
    }

    /// "Lizbona · Porto"; the first two places.
    public var title: String { places.prefix(2).joined(separator: " · ") }
}

public enum TripAssembly {
    public static func trips(from bookings: [TravelBooking]) -> [Trip] {
        let usable = bookings
            .filter { $0.isActive || $0.state == .waiting }
            .compactMap { b in b.span.map { (booking: b, span: $0) } }
            .sorted { ($0.span.start, $0.booking.id) < ($1.span.start, $1.booking.id) }

        var groups: [[(booking: TravelBooking, span: (start: TripDay, end: TripDay))]] = []
        for item in usable {
            if var last = groups.last, let lastEnd = last.map(\.span.end).max(), item.span.start <= lastEnd.adding(days: 1) {
                last.append(item)
                groups[groups.count - 1] = last
            } else {
                groups.append([item])
            }
        }
        return groups.map(makeTrip)
    }

    /// Bookings that ended or never happened, for a "not going ahead" list.
    public static func notGoingAhead(_ bookings: [TravelBooking]) -> [TravelBooking] {
        bookings.filter { $0.state == .cancelled || $0.state == .failed }
    }

    private static func makeTrip(_ group: [(booking: TravelBooking, span: (start: TripDay, end: TripDay))]) -> Trip {
        let bookings = group.map(\.booking)
        let firstFlight = bookings.flatMap(\.facts.segments).first
        let home = TravelAirports.airport(firstFlight?.from.code)?.country ?? "PL"

        var places: [String] = [], countries: [String] = []
        func addPlace(_ p: String?) { if let p, !p.isEmpty, !places.contains(p) { places.append(p) } }
        func addCountry(_ c: String?) { if let c, c != home, !countries.contains(c) { countries.append(c) } }

        for b in bookings {
            for s in b.facts.segments {
                let to = TravelAirports.airport(s.to.code)
                if to?.country != home { addPlace(s.to.name ?? s.to.code); addCountry(to?.country) }
            }
            if let stay = b.facts.stay {
                addPlace(stay.city)
                addCountry(TravelCountries.code(named: b.facts.destination?.country))
            }
            if b.facts.segments.isEmpty && b.facts.stay == nil { addPlace(b.facts.destination?.city) }
        }
        if places.isEmpty { addPlace(bookings.first?.facts.destination?.city) }

        return Trip(
            id: bookings[0].id,
            bookings: bookings,
            start: group.map(\.span.start).min()!,
            end: group.map(\.span.end).max()!,
            places: places,
            countries: countries,
            homeCountry: home)
    }
}

/// Country names as booking emails write them, to ISO codes; and back to names in Polish and English.
public enum TravelCountries {
    private static let names: [String: (pl: String, en: String)] = [
        "PL": ("Polska", "Poland"), "GB": ("Wielka Brytania", "United Kingdom"), "IE": ("Irlandia", "Ireland"),
        "ES": ("Hiszpania", "Spain"), "PT": ("Portugalia", "Portugal"), "IT": ("Włochy", "Italy"), "FR": ("Francja", "France"),
        "GR": ("Grecja", "Greece"), "CY": ("Cypr", "Cyprus"), "MT": ("Malta", "Malta"), "HR": ("Chorwacja", "Croatia"),
        "DE": ("Niemcy", "Germany"), "NL": ("Holandia", "Netherlands"), "BE": ("Belgia", "Belgium"), "LU": ("Luksemburg", "Luxembourg"),
        "AT": ("Austria", "Austria"), "CH": ("Szwajcaria", "Switzerland"), "CZ": ("Czechy", "Czechia"), "SK": ("Słowacja", "Slovakia"),
        "HU": ("Węgry", "Hungary"), "SI": ("Słowenia", "Slovenia"), "DK": ("Dania", "Denmark"), "SE": ("Szwecja", "Sweden"),
        "NO": ("Norwegia", "Norway"), "FI": ("Finlandia", "Finland"), "IS": ("Islandia", "Iceland"), "EE": ("Estonia", "Estonia"),
        "LV": ("Łotwa", "Latvia"), "LT": ("Litwa", "Lithuania"), "RO": ("Rumunia", "Romania"), "BG": ("Bułgaria", "Bulgaria"),
        "TR": ("Turcja", "Türkiye"), "EG": ("Egipt", "Egypt"), "TN": ("Tunezja", "Tunisia"), "MA": ("Maroko", "Morocco"),
        "AL": ("Albania", "Albania"), "ME": ("Czarnogóra", "Montenegro"), "MK": ("Macedonia Północna", "North Macedonia"),
        "BA": ("Bośnia i Hercegowina", "Bosnia and Herzegovina"), "RS": ("Serbia", "Serbia"), "GE": ("Gruzja", "Georgia"),
        "AM": ("Armenia", "Armenia"), "JO": ("Jordania", "Jordan"), "IL": ("Izrael", "Israel"), "AE": ("Zjednoczone Emiraty Arabskie", "United Arab Emirates"),
        "UA": ("Ukraina", "Ukraine"),
    ]
    private static let aliases: [String: String] = ["uk": "GB", "england": "GB", "anglia": "GB", "turkey": "TR", "czech republic": "CZ", "uae": "AE"]

    public static func code(named name: String?) -> String? {
        guard let name else { return nil }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let alias = aliases[n] { return alias }
        return names.first { $0.value.pl.lowercased() == n || $0.value.en.lowercased() == n }?.key
    }

    public static func name(_ code: String, polish: Bool) -> String {
        guard let n = names[code] else { return code }
        return polish ? n.pl : n.en
    }
}
