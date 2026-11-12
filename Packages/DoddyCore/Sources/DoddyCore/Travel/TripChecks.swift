import Foundation

// What a trip asks of the person before they go (docs/implementation/TRAVEL.md section 3.10), worked out on
// the iPhone from the bookings and two hand-checked tables: when online check-in opens per airline, and
// which documents a Polish citizen needs per country. Each item says where its rule comes from. Items are
// suggestions shown on the trip; a reminder or calendar entry is only made from one on the person's tap
// (DOD-07), through the existing reminder and calendar cards.

public struct TripCheck: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// Online check-in for one flight. `rule` is nil when Doddy doesn't know the airline's rule;
        /// `opensAt` is nil also when the departure airport or time is unknown. `zone` is the airport's.
        case checkIn(flight: String, rule: CheckInRule?, opensAt: Date?, zone: String?)
        /// The last day to cancel without paying, from the stay's email; remind two days before.
        case freeCancellation(until: TripDay, time: String?, remindOn: TripDay)
        case deposit(amount: String, currency: String, when: String?)
        case payOnSite(what: String, amount: String, currency: String)
        /// Documents for one country, with the official page.
        case documents(country: String, rule: EntryRule)
        /// Paid, but the seller hasn't confirmed it yet.
        case waitingForSeller
        /// A sentence copied from the confirmation ("4th floor without elevator").
        case fromTheEmail(String)
    }

    public let id: String
    public let bookingId: String?
    public let kind: Kind
    /// Where the rule comes from; nil for facts copied from the person's own email.
    public let sourceURL: String?
}

/// When an airline opens online check-in (checked on the airlines' own help pages, 11 Nov 2026).
public struct CheckInRule: Equatable, Sendable {
    public let airline: String
    /// Without a paid seat.
    public let freeOpensHours: Int
    /// With a paid seat.
    public let seatOpensDays: Int
    public let closesHours: Int
    public let sourceURL: String

    public static let ryanair = CheckInRule(
        airline: "Ryanair", freeOpensHours: 72, seatOpensDays: 60, closesHours: 2,
        sourceURL: "https://help.ryanair.com/hc/en-ie/articles/12888949622417-When-can-I-check-in")
    public static let wizzAir = CheckInRule(
        airline: "Wizz Air", freeOpensHours: 24, seatOpensDays: 30, closesHours: 3,
        sourceURL: "https://www.wizzair.com/en-gb/help-centre/check-in-and-boarding/check-in/check-in-and-baggage-drop-off-times")

    /// The rule for a flight, from its number's airline code or the booking's seller; nil when unknown.
    public static func rule(flightNumber: String?, provider: String?) -> CheckInRule? {
        let number = (flightNumber ?? "").uppercased().replacingOccurrences(of: " ", with: "")
        let seller = (provider ?? "").lowercased()
        let isCode = { (codes: [String]) in codes.contains { number.hasPrefix($0) && number.dropFirst($0.count).first?.isNumber == true } }
        if isCode(["FR", "RK"]) || seller.contains("ryanair") { return .ryanair }
        if isCode(["W6", "W4", "W9", "5W"]) || seller.contains("wizz") { return .wizzAir }
        return nil
    }
}

/// What a Polish citizen needs to enter a country for a short trip. Only three rules are written down;
/// every other country gets the government's travel-advice page instead of a guess.
public enum EntryRule: Equatable, Sendable {
    /// EU, EEA and Switzerland: a valid ID card or passport.
    case idCardOrPassport
    /// The UK: a passport (an ID card isn't accepted without settled status) and an ETA for each person.
    case passportAndUKETA
    /// Türkiye: a passport valid 150 days from entry, or an ID card valid for the stay; mObywatel isn't accepted.
    case turkey
    /// Not written down here: check the official page.
    case checkOfficialPage

    static let freeMovement: Set<String> = [
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL",
        "PL", "PT", "RO", "SK", "SI", "ES", "SE", "IS", "LI", "NO", "CH",
    ]

    public static func forCountry(_ iso: String) -> EntryRule {
        if freeMovement.contains(iso) { return .idCardOrPassport }
        if iso == "GB" { return .passportAndUKETA }
        if iso == "TR" { return .turkey }
        return .checkOfficialPage
    }

    public var sourceURL: String {
        switch self {
        case .idCardOrPassport: "https://europa.eu/youreurope/citizens/travel/entry-exit/eu-citizen/index_en.htm"
        case .passportAndUKETA: "https://www.gov.uk/guidance/visiting-the-uk-as-an-eu-eea-or-swiss-citizen"
        case .turkey: "https://www.gov.pl/web/turcja/porady-dla-podrozujacych-do-turcji-i-przebywajacych-w-turcji"
        case .checkOfficialPage: "https://www.gov.pl/web/dyplomacja/informacje-dla-podrozujacych"
        }
    }
}

public enum TripChecks {
    public static func checks(for trip: Trip) -> [TripCheck] {
        var out: [TripCheck] = []
        for b in trip.bookings {
            if b.state == .waiting {
                out.append(TripCheck(id: "\(b.id).waiting", bookingId: b.id, kind: .waitingForSeller, sourceURL: nil))
                continue
            }
            for (i, s) in b.facts.segments.enumerated() {
                let flight = [s.number, [s.from.name ?? s.from.code, s.to.name ?? s.to.code].compactMap { $0 }.joined(separator: " → ")]
                    .compactMap { $0 }.joined(separator: " ")
                let rule = CheckInRule.rule(flightNumber: s.number, provider: b.provider)
                let airport = TravelAirports.airport(s.from.code)
                let zone = airport?.timeZone
                var opens: Date? = nil
                if let rule, let zone, let departs = TripDay(s.departDate)?.at(s.departTime, in: zone) {
                    opens = departs.addingTimeInterval(-Double(rule.freeOpensHours) * 3600)
                }
                out.append(TripCheck(
                    id: "\(b.id).checkin.\(i)", bookingId: b.id,
                    kind: .checkIn(flight: flight, rule: rule, opensAt: opens, zone: airport?.zone),
                    sourceURL: rule?.sourceURL))
            }
            if let deadline = b.facts.freeCancellationUntil, let day = TripDay(deadline.date) {
                out.append(TripCheck(
                    id: "\(b.id).cancel", bookingId: b.id,
                    kind: .freeCancellation(until: day, time: deadline.time, remindOn: day.adding(days: -2)), sourceURL: nil))
            }
            if let d = b.facts.deposit {
                out.append(TripCheck(id: "\(b.id).deposit", bookingId: b.id, kind: .deposit(amount: d.amount, currency: d.currency, when: d.when), sourceURL: nil))
            }
            for (i, c) in b.facts.payOnSite.enumerated() {
                out.append(TripCheck(id: "\(b.id).site.\(i)", bookingId: b.id, kind: .payOnSite(what: c.what, amount: c.amount, currency: c.currency), sourceURL: nil))
            }
            for (i, n) in b.facts.notes.enumerated() {
                out.append(TripCheck(id: "\(b.id).note.\(i)", bookingId: b.id, kind: .fromTheEmail(n), sourceURL: nil))
            }
        }
        // Documents last, per country the trip goes to, the strictest first.
        let rules = trip.countries.map { ($0, EntryRule.forCountry($0)) }
        let order: [EntryRule] = [.passportAndUKETA, .turkey, .checkOfficialPage, .idCardOrPassport]
        for (country, rule) in rules.sorted(by: { order.firstIndex(of: $0.1)! < order.firstIndex(of: $1.1)! }) {
            out.append(TripCheck(id: "\(trip.id).documents.\(country)", bookingId: nil, kind: .documents(country: country, rule: rule), sourceURL: rule.sourceURL))
        }
        return out
    }
}

// MARK: - Words (Polish and English)

public enum TripCheckText {
    /// "5 gru, 14:00" in a zone; day and month names don't depend on the device's language.
    static func dayTime(_ date: Date, zone: TimeZone, polish: Bool) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.day, .month, .hour, .minute], from: date)
        let pl = ["sty", "lut", "mar", "kwi", "maj", "cze", "lip", "sie", "wrz", "paź", "lis", "gru"]
        let en = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let month = (polish ? pl : en)[c.month! - 1]
        return String(format: "%d %@, %02d:%02d", c.day!, month, c.hour!, c.minute!)
    }

    public static func day(_ d: TripDay, polish: Bool) -> String {
        let pl = ["stycznia", "lutego", "marca", "kwietnia", "maja", "czerwca", "lipca", "sierpnia", "września", "października", "listopada", "grudnia"]
        let en = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        return polish ? "\(d.day) \(pl[d.month - 1])" : "\(d.day) \(en[d.month - 1])"
    }

    public static func title(_ check: TripCheck, polish: Bool) -> String {
        switch check.kind {
        case let .checkIn(flight, _, _, _): polish ? "Odprawa online: \(flight)" : "Online check-in: \(flight)"
        case .freeCancellation: polish ? "Darmowe anulowanie noclegu" : "Free cancellation of the stay"
        case let .deposit(amount, currency, _): polish ? "Kaucja \(amount) \(currency)" : "Deposit \(amount) \(currency)"
        case let .payOnSite(what, amount, currency): polish ? "Na miejscu: \(what) \(amount) \(currency)" : "Paid there: \(what) \(amount) \(currency)"
        case let .documents(country, _): polish ? "Dokumenty: \(TravelCountries.name(country, polish: true))" : "Documents: \(TravelCountries.name(country, polish: false))"
        case .waitingForSeller: polish ? "Rezerwacja czeka na potwierdzenie" : "Booking waiting for confirmation"
        case .fromTheEmail: polish ? "Z potwierdzenia" : "From the confirmation"
        }
    }

    /// The line under the title. `zone` is the departure airport's, for check-in times.
    public static func detail(_ check: TripCheck, trip: Trip, polish: Bool) -> String {
        switch check.kind {
        case let .checkIn(_, rule, opensAt, zoneID):
            guard let rule else {
                return polish
                    ? "Sprawdź u przewoźnika, kiedy otwiera się odprawa online. Bez niej linie zwykle pobierają opłatę na lotnisku."
                    : "Check with the airline when online check-in opens. Airlines usually charge for check-in at the airport."
            }
            let closes = rule.closesHours
            guard let opensAt, let zone = zoneID.flatMap(TimeZone.init(identifier:)) else {
                return polish
                    ? "\(rule.airline): bez wykupionego miejsca odprawa otwiera się \(rule.freeOpensHours) godz. przed wylotem, z miejscem \(rule.seatOpensDays) dni przed. Zamyka się \(closes) godz. przed wylotem."
                    : "\(rule.airline): without a paid seat, check-in opens \(rule.freeOpensHours) hours before departure, with one \(rule.seatOpensDays) days before. It closes \(closes) hours before departure."
            }
            let when = dayTime(opensAt, zone: zone, polish: polish)
            return polish
                ? "\(rule.airline): bez wykupionego miejsca odprawa otwiera się \(rule.freeOpensHours) godz. przed wylotem (\(when) czasu lokalnego), z miejscem \(rule.seatOpensDays) dni przed. Zamyka się \(closes) godz. przed wylotem; potem odprawa na lotnisku jest płatna."
                : "\(rule.airline): without a paid seat, check-in opens \(rule.freeOpensHours) hours before departure (\(when) local time), with one \(rule.seatOpensDays) days before. It closes \(closes) hours before departure; after that, airport check-in costs extra."
        case let .freeCancellation(until, time, remindOn):
            let at = time.map { polish ? ", do \($0)" : ", until \($0)" } ?? ""
            return polish
                ? "Bez kosztów do \(day(until, polish: true))\(at) czasu obiektu. Przypomnę \(day(remindOn, polish: true)), jeśli chcesz."
                : "Free until \(day(until, polish: false))\(at), the property's time. I can remind you on \(day(remindOn, polish: false))."
        case let .deposit(_, _, when):
            return when.map { polish ? "Z potwierdzenia: „\($0)”" : "From the confirmation: “\($0)”" }
                ?? (polish ? "Kaucja jest w potwierdzeniu, bez daty pobrania." : "The confirmation mentions a deposit, without when it is charged.")
        case .payOnSite:
            return polish ? "Nie jest wliczone w to, co już zapłacono." : "Not included in what you've paid."
        case let .documents(_, rule):
            switch rule {
            case .idCardOrPassport:
                return polish ? "Ważny dowód osobisty albo paszport, dla każdej osoby." : "A valid ID card or passport, for each person."
            case .passportAndUKETA:
                return polish
                    ? "Paszport (dowód osobisty nie wystarczy, chyba że masz status osiedlenia) i ETA, elektroniczne zezwolenie na podróż, dla każdej osoby, także dzieci. Złóż wniosek przed wylotem na gov.uk."
                    : "A passport (an ID card isn't enough unless you have settled status) and an ETA, the electronic travel authorisation, for each person, children too. Apply before you fly on gov.uk."
            case .turkey:
                return polish
                    ? "Paszport ważny co najmniej 150 dni od wjazdu albo dowód osobisty ważny przez cały pobyt. mObywatel nie wystarczy."
                    : "A passport valid at least 150 days from entry, or an ID card valid for the whole stay. mObywatel isn't accepted."
            case .checkOfficialPage:
                return polish ? "Sprawdź wymagania dla tego kraju na gov.pl przed wyjazdem." : "Check this country's entry rules on gov.pl before you go."
            }
        case .waitingForSeller:
            return polish ? "Sprzedawca jeszcze nie potwierdził. Nie planuję wokół niej, dopóki nie przyjdzie potwierdzenie." : "The seller hasn't confirmed it yet. I won't plan around it until they do."
        case let .fromTheEmail(text):
            return "„\(text)”"
        }
    }
}
