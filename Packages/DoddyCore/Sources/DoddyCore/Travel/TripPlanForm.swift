import Foundation

// The planner's form (owner, 13 Nov 2026: "trzeba skupić się na zaplanowaniu wyjazdu, na wyszukiwaniu lotów,
// hoteli"). Trips opens on a form: from, to, when, nights, who, bags, budget. What the person fills in, and what
// Doddy understood from their own words, is one `TripBrief`, so the server's rules (backend/src/travel/plan.ts:
// `cleanBrief`, `missing`, `assumptions`) see exactly what the screen shows. A complete form goes straight to
// the search (Kiwi.com through Doddy's server, no model); only typed words go through the "understand" step.

public struct TripPlanForm: Equatable, Sendable {
    public var from = ""
    public var to = ""
    /// The window of days to leave in. `departTo` nil, or equal to `departFrom`, is one exact day.
    public var departFrom: TripDay?
    public var departTo: TripDay?
    public var nightsMin: Int?
    public var nightsMax: Int?
    /// Shown on the form as a stepper, so always a number the person can see.
    public var adults = 1
    /// nil: not said; the search assumes none and the screen says so.
    public var children: Int?
    public var checkedBag: Bool?
    public var directOnly: Bool?
    public var package: Bool?
    /// The most the person would pay for the flights, in zł (the server searches in PLN).
    public var budget: Int?

    public static let adultsRange = 1...9
    public static let childrenRange = 0...8
    public static let nightsRange = 1...30
    /// The server drops a day further ahead than this (plan.ts `MAX_DAYS_AHEAD`).
    public static let daysAhead = 330
    /// The longest window to leave in (plan.ts `MAX_WINDOW_DAYS`).
    public static let maxWindowDays = 31
    public static let maxBudget = 1_000_000
    /// The server's longest place name.
    static let maxPlaceLength = 60

    public init() {}

    /// The brief sent to the server: blank places are unknown (null), numbers are kept in the server's ranges,
    /// a window back to front is one day, and a trip to where it starts has no destination (as `cleanBrief`).
    public var brief: TripBrief {
        var b = TripBrief()
        b.from = Self.place(from)
        b.to = Self.place(to)
        if let f = b.from, let t = b.to, f.lowercased() == t.lowercased() { b.to = nil }
        if let start = departFrom {
            var end = departTo ?? start
            if end < start { end = start }
            if start.days(to: end) > Self.maxWindowDays { end = start.adding(days: Self.maxWindowDays) }
            b.departFrom = start.description
            b.departTo = end.description
        }
        if let lo = nightsMin ?? nightsMax, let hi = nightsMax ?? nightsMin {
            b.nightsMin = Self.clamp(min(lo, hi), Self.nightsRange)
            b.nightsMax = Self.clamp(max(lo, hi), Self.nightsRange)
        }
        b.adults = Self.clamp(adults, Self.adultsRange)
        b.children = children.map { Self.clamp($0, Self.childrenRange) }
        b.checkedBagPerAdult = checkedBag
        b.directOnly = directOnly
        b.package = package
        b.budget = budget.flatMap { $0 >= 1 ? min($0, Self.maxBudget) : nil }
        return b
    }

    /// The form shows what the server understood. The brief sent with the words was this form, and the server
    /// keeps what the words don't change, so a field only changes when the words said something about it.
    public mutating func apply(_ b: TripBrief) {
        from = b.from ?? ""
        to = b.to ?? ""
        departFrom = TripDay(b.departFrom)
        departTo = departFrom == nil ? nil : TripDay(b.departTo)
        nightsMin = b.nightsMin
        nightsMax = b.nightsMax
        if let a = b.adults { adults = Self.clamp(a, Self.adultsRange) }
        children = b.children
        checkedBag = b.checkedBagPerAdult
        directOnly = b.directOnly
        package = b.package
        budget = b.budget
    }

    /// What a search can't run without, in the order Doddy asks for it.
    public var missing: [PlanNeed] { brief.missing }
    /// What the search will assume for what isn't filled in, said on the screen.
    public var assumptions: [PlanAssumption] { brief.assumptions }

    /// One number of nights for the stepper: the longest of the range.
    public var nights: Int? { nightsMax ?? nightsMin }

    public mutating func setNights(_ n: Int) {
        let v = Self.clamp(n, Self.nightsRange)
        nightsMin = v
        nightsMax = v
    }

    public mutating func swapPlaces() { (from, to) = (to, from) }

    /// The window around a day the person picked, "± flexDays", never before today nor past the last day the
    /// server searches.
    public static func window(around day: TripDay, flexDays: Int, today: TripDay) -> (from: TripDay, to: TripDay) {
        let flex = max(0, min(flexDays, maxWindowDays / 2))
        let last = today.adding(days: daysAhead)
        var start = day.adding(days: -flex)
        if start < today { start = today }
        var end = day.adding(days: flex)
        if end > last { end = last }
        if end < start { end = start }
        return (start, end)
    }

    /// A budget typed in the box: digits only ("1 500" is 1500), nil when there are none or it is 0.
    public static func budget(fromText text: String) -> Int? {
        let digits = String(text.filter { $0.isASCII && $0.isNumber }.prefix(9))
        guard let value = Int(digits), value >= 1 else { return nil }
        return min(value, maxBudget)
    }

    static func place(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : String(t.prefix(maxPlaceLength))
    }

    static func clamp(_ v: Int, _ r: ClosedRange<Int>) -> Int { min(max(v, r.lowerBound), r.upperBound) }
}

extension TripBrief {
    /// What a search can't run without, in the order Doddy asks: the server's `missing` (plan.ts).
    public var missing: [PlanNeed] {
        var out: [PlanNeed] = []
        if to == nil { out.append(.to) }
        if from == nil { out.append(.from) }
        if departFrom == nil { out.append(.when) }
        if nightsMin == nil { out.append(.nights) }
        if adults == nil { out.append(.who) }
        return out
    }

    /// What is assumed for what wasn't said: the server's `assumptions` (plan.ts).
    public var assumptions: [PlanAssumption] {
        var out: [PlanAssumption] = []
        if checkedBagPerAdult == nil { out.append(.noCheckedBag) }
        if directOnly == nil { out.append(.stopsAllowed) }
        if children == nil { out.append(.noChildren) }
        if departFrom != nil, departTo == departFrom { out.append(.exactDay) }
        return out
    }
}

extension PlanOption {
    /// The first night of a stay for this option, as the server's stay links use it (plan.ts `stayLinks`).
    public var checkInDay: TripDay? { TripDay(String(outbound.arrives.prefix(10))) }
    /// The day the stay ends: the return flight's day, or the arrival day for a one-way answer.
    public var checkOutDay: TripDay? { TripDay(String((inbound?.departs ?? outbound.arrives).prefix(10))) }
}

extension PlanLeg {
    /// Days between leaving and landing, in local times: 1 when the flight lands the next day.
    public var arrivalDayShift: Int {
        guard let a = TripDay(String(departs.prefix(10))), let b = TripDay(String(arrives.prefix(10))) else { return 0 }
        return max(0, a.days(to: b))
    }
}

/// What went wrong with a plan, in words the person can act on. The planner's own words: a failed flight
/// search is never shown as a Gmail problem.
public enum TripPlanProblem: Equatable, Sendable {
    case notSetUp, dailyLimit, incomplete, flightsUnavailable, wordsUnavailable

    /// `searching`: the error came from the flight search, not from reading the person's words.
    public init(_ error: OnlineAccountsError, searching: Bool) {
        switch error {
        case let .server(code, _, _, _):
            switch code {
            case "live_not_configured": self = .notSetUp
            case "quota_exceeded", "rate_limited": self = .dailyLimit
            case "invalid_request": self = .incomplete
            default: self = searching ? .flightsUnavailable : .wordsUnavailable
            }
        case .notConfigured: self = .notSetUp
        default: self = searching ? .flightsUnavailable : .wordsUnavailable
        }
    }

    public func text(polish: Bool) -> String {
        switch self {
        case .notSetUp:
            polish ? "Planowanie wyjazdów nie jest jeszcze włączone na serwerze Doddy'ego." : "Trip planning isn't set up on Doddy's server yet."
        case .dailyLimit:
            polish ? "Na dziś wyczerpany limit. Spróbuj jutro." : "Today's limit is used up. Try again tomorrow."
        case .incomplete:
            polish ? "Czegoś brakuje albo data jest za daleko (najwyżej 330 dni naprzód). Sprawdź miejsca i daty."
                : "Something is missing, or a date is too far ahead (330 days at most). Check the places and dates."
        case .flightsUnavailable:
            polish ? "Kiwi.com nie odpowiedziało. Nic nie zostało zarezerwowane; spróbuj za chwilę."
                : "Kiwi.com didn't answer. Nothing was booked; try again in a moment."
        case .wordsUnavailable:
            polish ? "Nie udało się teraz odczytać twoich słów. Wypełnij pola albo spróbuj za chwilę."
                : "Your words couldn't be read just now. Fill in the fields, or try again in a moment."
        }
    }
}

// MARK: - Words for the form and the flight cards (Polish and English)

extension TripPlanText {
    /// "742 zł" / "742 PLN": the price as Kiwi.com answered it.
    public static func money(_ o: PlanOption, polish: Bool) -> String {
        o.currency == "PLN" && polish ? "\(o.price) zł" : "\(o.price) \(o.currency)"
    }

    /// "za 2 osoby, bez walizki": who the price is for and what bags it counts.
    public static func party(_ o: PlanOption, people: Int, polish: Bool) -> String {
        let who = polish
            ? "za \(people) \(plural(people, one: "osobę", few: "osoby", many: "osób"))"
            : (people == 1 ? "for 1 person" : "for \(people) people")
        let bags = o.checkedBagsIncluded > 0
            ? (polish ? ", walizki wliczone: \(o.checkedBagsIncluded)" : ", checked bags included: \(o.checkedBagsIncluded)")
            : (polish ? ", bez walizki" : ", no checked bag")
        return who + bags
    }

    public static func stops(_ n: Int, polish: Bool) -> String {
        switch n {
        case 0: polish ? "bez przesiadek" : "direct"
        case 1: polish ? "1 przesiadka" : "1 stop"
        default: polish ? "przesiadki: \(n)" : "\(n) stops"
        }
    }

    /// "9 h 50 min" / "9 godz. 50 min".
    public static func duration(minutes: Int, polish: Bool) -> String {
        let h = max(0, minutes) / 60, m = max(0, minutes) % 60
        let hours = polish ? "\(h) godz." : "\(h) h"
        if h == 0 { return "\(m) min" }
        return m == 0 ? hours : "\(hours) \(m) min"
    }

    /// "4 noce", "3–4 nights".
    public static func nights(min lo: Int, max hi: Int, polish: Bool) -> String {
        let count = lo == hi ? "\(hi)" : "\(lo)–\(hi)"
        if polish { return "\(count) \(plural(hi, one: "noc", few: "noce", many: "nocy"))" }
        return "\(count) \(hi == 1 && lo == hi ? "night" : "nights")"
    }

    public static func adults(_ n: Int, polish: Bool) -> String {
        polish ? (n == 1 ? "1 dorosły" : "\(n) dorosłych") : (n == 1 ? "1 adult" : "\(n) adults")
    }

    public static func children(_ n: Int, polish: Bool) -> String {
        polish ? (n == 1 ? "1 dziecko" : "\(n) dzieci") : (n == 1 ? "1 child" : "\(n) children")
    }

    /// "2 dorosłych, 1 dziecko" / "2 adults".
    public static func people(adults a: Int, children c: Int, polish: Bool) -> String {
        c > 0 ? "\(adults(a, polish: polish)), \(children(c, polish: polish))" : adults(a, polish: polish)
    }

    /// "12 lutego", "9–15 lutego", "28 February – 3 March".
    public static func window(from a: TripDay, to b: TripDay, polish: Bool) -> String {
        if a == b { return TripCheckText.day(a, polish: polish) }
        if a.year == b.year, a.month == b.month { return "\(a.day)–\(TripCheckText.day(b, polish: polish))" }
        return "\(TripCheckText.day(a, polish: polish)) – \(TripCheckText.day(b, polish: polish))"
    }

    /// The assumption in two or three words, for a chip.
    public static func assumptionShort(_ a: PlanAssumption, polish: Bool) -> String {
        switch a {
        case .noCheckedBag: polish ? "Bez walizki" : "No checked bag"
        case .stopsAllowed: polish ? "Przesiadki OK" : "Stops are fine"
        case .noChildren: polish ? "Bez dzieci" : "No children"
        case .exactDay: polish ? "Dokładnie ten dzień" : "Exactly that day"
        }
    }

    /// What a search was for, as the server echoed the brief: one short phrase per chip.
    public static func searched(_ b: TripBrief, polish: Bool) -> [String] {
        var out: [String] = []
        if let f = b.from, let t = b.to { out.append("\(f) → \(t)") }
        if let a = TripDay(b.departFrom) { out.append(window(from: a, to: TripDay(b.departTo) ?? a, polish: polish)) }
        if let lo = b.nightsMin { out.append(nights(min: lo, max: b.nightsMax ?? lo, polish: polish)) }
        out.append(people(adults: b.adults ?? 1, children: b.children ?? 0, polish: polish))
        out.append(b.checkedBagPerAdult == true
            ? (polish ? "Walizka na osobę" : "A checked bag each")
            : (polish ? "Bez walizki" : "No checked bag"))
        out.append(b.directOnly == true ? (polish ? "Bez przesiadek" : "Direct only") : (polish ? "Przesiadki OK" : "Stops are fine"))
        if let budget = b.budget { out.append(polish ? "Do \(budget) zł" : "Up to \(budget) PLN") }
        return out
    }

    /// Polish plural forms: 1 osobę, 2–4 osoby (not 12–14), 5 osób.
    static func plural(_ n: Int, one: String, few: String, many: String) -> String {
        if n == 1 { return one }
        let lastTwo = n % 100, last = n % 10
        if (2...4).contains(last), !(12...14).contains(lastTwo) { return few }
        return many
    }
}
