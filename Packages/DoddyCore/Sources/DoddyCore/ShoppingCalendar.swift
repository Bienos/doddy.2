import Foundation

// When shops in Poland are open (ADR-661; research docs/research/2026-10-28/research_deals_better.md
// §5 #5): a leaflet price "until Sunday" is no use if Sunday is a closed Sunday. Worked out from the
// law, by code, for any year; no network and no time zone (a `DealDay` is a calendar day in Poland).
//
// - Sundays are closed except the trading Sundays of the Act of 10 January 2018 as amended (from
//   2025): the last Sunday of January, April, June and August, the Sunday before Easter, and the
//   three Sundays before 24 December.
// - Public holidays are closed (Act of 18 January 1951 on days off work, with 24 December from 2025):
//   1 and 6 January, Easter Sunday and Monday, 1 and 3 May, Pentecost Sunday, Corpus Christi,
//   15 August, 1 and 11 November, 24, 25 and 26 December. A holiday on a trading Sunday is closed.
// - Holy Saturday (the day before Easter): shops close at 14:00.
// - Shops the owner runs in person may open (the Act's exemption); many Żabka shops do, so Doddy
//   never calls a Żabka closed: it says "most shops".
//
// Platforms: iPhone (the deals screen, the checklist, the voice tool's answer). Pure logic; tested on Linux.

public enum PolishHoliday: String, CaseIterable, Sendable {
    case newYear, epiphany, easter, easterMonday, labourDay, constitutionDay, pentecost, corpusChristi
    case assumption, allSaints, independenceDay, christmasEve, christmas, secondDayOfChristmas
}

/// What a day is for shopping.
public enum ShoppingDayKind: Equatable, Sendable {
    case open
    /// Open until 14:00 (Holy Saturday).
    case closesEarly(hour: Int)
    /// A Sunday that isn't a trading Sunday.
    case closedSunday
    case closedHoliday(PolishHoliday)

    public var isClosed: Bool {
        switch self {
        case .closedSunday, .closedHoliday: true
        case .open, .closesEarly: false
        }
    }
}

public enum ShoppingCalendar {
    /// The latest year the rules are worked out for; later days count as open with no note.
    static let years = 2000...2199

    /// Today in Poland.
    public static func today(_ now: Date = Date()) -> DealDay? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw") ?? TimeZone(secondsFromGMT: 3600)!
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        return day(y, m, d)
    }

    /// What `day` is for shopping in Poland.
    public static func kind(_ day: DealDay) -> ShoppingDayKind {
        guard years.contains(day.year) else { return .open }
        if let holiday = holiday(day) { return .closedHoliday(holiday) }
        if weekday(day) == 7 { return isTradingSunday(day) ? .open : .closedSunday }
        if day == adding(-1, to: easter(day.year)) { return .closesEarly(hour: 14) }
        return .open
    }

    /// Whether most shops of `chain` are closed on `day`: never for Żabka, whose owner-run shops may open.
    public static func isClosed(_ day: DealDay, for chain: DealsChain) -> Bool {
        chain != .zabka && kind(day).isClosed
    }

    /// The last day on or before `last`, and not before `first`, on which `chain`'s shops are open.
    /// Nil when every day between is closed.
    public static func lastOpenDay(from first: DealDay, through last: DealDay, for chain: DealsChain) -> DealDay? {
        guard first <= last else { return nil }
        var day = last
        for _ in 0..<14 {
            if !isClosed(day, for: chain) { return day }
            day = adding(-1, to: day)
            if day < first { return nil }
        }
        return nil
    }

    /// The closed days from `first` through `last` (at most 14 days are looked at).
    public static func closedDays(from first: DealDay, through last: DealDay, for chain: DealsChain) -> [DealDay] {
        guard first <= last else { return [] }
        var out: [DealDay] = []
        var day = first
        for _ in 0..<14 {
            if isClosed(day, for: chain) { out.append(day) }
            if day == last { break }
            day = adding(1, to: day)
        }
        return out
    }

    // MARK: The rules

    static func holiday(_ day: DealDay) -> PolishHoliday? {
        switch (day.month, day.day) {
        case (1, 1): return .newYear
        case (1, 6): return .epiphany
        case (5, 1): return .labourDay
        case (5, 3): return .constitutionDay
        case (8, 15): return .assumption
        case (11, 1): return .allSaints
        case (11, 11): return .independenceDay
        case (12, 24) where day.year >= 2025: return .christmasEve
        case (12, 25): return .christmas
        case (12, 26): return .secondDayOfChristmas
        default: break
        }
        let easter = easter(day.year)
        switch days(from: easter, to: day) {
        case 0: return .easter
        case 1: return .easterMonday
        case 49: return .pentecost
        case 60: return .corpusChristi
        default: return nil
        }
    }

    /// One of the year's trading Sundays (whether or not a holiday falls on it).
    static func isTradingSunday(_ day: DealDay) -> Bool {
        guard weekday(day) == 7 else { return false }
        if [1, 4, 6, 8].contains(day.month), day.day + 7 > DealDay.days(in: day.month, of: day.year) { return true }
        if day == adding(-7, to: easter(day.year)) { return true }
        if let christmasEve = Self.day(day.year, 12, 24) {
            let before = days(from: day, to: christmasEve)
            return day.month == 12 && before >= 1 && before <= 21
        }
        return false
    }

    /// Easter Sunday (Gregorian computus, Meeus/Jones/Butcher).
    static func easter(_ year: Int) -> DealDay {
        let a = year % 19, b = year / 100, c = year % 100, d = b / 4, e = b % 4
        let f = (b + 8) / 25, g = (b - f + 1) / 3, h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let dayOfMonth = (h + l - 7 * m + 114) % 31 + 1
        return day(year, month, dayOfMonth)!
    }

    // MARK: Day arithmetic, with no time zone

    /// 1 = Monday … 7 = Sunday.
    public static func weekday(_ day: DealDay) -> Int {
        // 1970-01-01 was a Thursday (4).
        let n = ordinal(day)
        return ((n % 7 + 7) % 7 + 3) % 7 + 1
    }

    public static func adding(_ days: Int, to day: DealDay) -> DealDay {
        civil(ordinal(day) + days)
    }

    /// `to` minus `from`, in days.
    public static func days(from: DealDay, to: DealDay) -> Int {
        ordinal(to) - ordinal(from)
    }

    static func day(_ year: Int, _ month: Int, _ day: Int) -> DealDay? {
        DealDay(rawValue: String(format: "%04d-%02d-%02d", year, month, day))
    }

    /// Days since 1970-01-01 (H. Hinnant's days_from_civil).
    static func ordinal(_ day: DealDay) -> Int {
        let y = day.month <= 2 ? day.year - 1 : day.year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (day.month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day.day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civil(_ n: Int) -> DealDay {
        let z = n + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return day(yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)!
    }
}
