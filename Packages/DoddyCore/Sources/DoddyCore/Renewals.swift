import Foundation

// Bills and subscriptions (ADR-344). The user types in what renews and when: a name, an optional
// amount, how often, and the next date. Doddy shows them by date, adds up a rough monthly cost,
// and, if the user wants, sends one notification a few days before each next date. No bank,
// card or email is read; nothing leaves the iPhone. The voice agent can only read them
// (upcoming_renewals); adding and changing happen on the screen.

public enum RenewalCycle: String, Codable, CaseIterable, Sendable {
    case weekly, monthly, quarterly, yearly

    var component: (Calendar.Component, Int) {
        switch self {
        case .weekly: (.day, 7)
        case .monthly: (.month, 1)
        case .quarterly: (.month, 3)
        case .yearly: (.year, 1)
        }
    }

    /// How many times a year, for the monthly estimate.
    var perYear: Decimal {
        switch self {
        case .weekly: 52
        case .monthly: 12
        case .quarterly: 4
        case .yearly: 1
        }
    }

    public var spoken: String {
        switch self {
        case .weekly: "every week"
        case .monthly: "every month"
        case .quarterly: "every 3 months"
        case .yearly: "every year"
        }
    }
}

public struct Renewal: Codable, Equatable, Sendable, Identifiable {
    public static let maxRemindDays = 14
    public let id: UUID
    public var name: String
    /// Optional; the user's own number, never looked up.
    public var amount: Decimal?
    /// ISO code such as "PLN"; with an amount only.
    public var currency: String?
    public var cycle: RenewalCycle
    /// The first date the user gave; later dates follow from the cycle.
    public var start: Date
    /// Days before for the notification; nil means no notification.
    public var remindDaysBefore: Int?

    public init(id: UUID = UUID(), name: String, amount: Decimal? = nil, currency: String? = nil,
                cycle: RenewalCycle, start: Date, remindDaysBefore: Int? = 3) {
        self.id = id
        self.name = name
        self.amount = amount
        self.currency = currency
        self.cycle = cycle
        self.start = start
        self.remindDaysBefore = remindDaysBefore
    }

    /// The first renewal on or after the start of `now`'s day. Month ends stay sensible: a
    /// 31 January monthly renewal falls on 28/29 February, then 31 March.
    public func next(after now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let (unit, step) = cycle.component
        var index = 0
        var date = calendar.startOfDay(for: start)
        while date < today, index < 5000 {
            index += 1
            date = calendar.date(byAdding: unit, value: step * index, to: calendar.startOfDay(for: start)) ?? date
        }
        return date
    }

    /// 09:00 `remindDaysBefore` days before the next renewal that is still ahead of `now`.
    public func reminderDate(now: Date, calendar: Calendar) -> Date? {
        guard let days = remindDaysBefore else { return nil }
        var renewal = next(after: now, calendar: calendar)
        for _ in 0..<2 {
            if let day = calendar.date(byAdding: .day, value: -days, to: renewal),
               let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day), morning > now {
                return morning
            }
            let (unit, step) = cycle.component
            renewal = next(after: calendar.date(byAdding: unit, value: step, to: renewal) ?? renewal, calendar: calendar)
        }
        return nil
    }

    var monthlyAmount: Decimal? { amount.map { $0 * cycle.perYear / 12 } }
}

public enum RenewalProblem: Equatable, Sendable {
    case noName, badAmount, badCurrency, badReminder, full
}

public struct Renewals: Equatable, Sendable {
    public static let storageKey = "renewals"
    public static let limit = 100
    public private(set) var items: [Renewal]

    public init(stored: Data?) {
        items = stored.flatMap { try? JSONDecoder().decode([Renewal].self, from: $0) } ?? []
    }

    public var stored: Data { (try? JSONEncoder().encode(items)) ?? Data() }

    /// Checks and keeps one, new or changed. Nil when kept.
    public mutating func save(_ renewal: Renewal) -> RenewalProblem? {
        var cleaned = renewal
        cleaned.name = String(renewal.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !cleaned.name.isEmpty else { return .noName }
        if let amount = renewal.amount {
            guard amount > 0, amount < 1_000_000 else { return .badAmount }
            guard let code = renewal.currency, code.count == 3, code.allSatisfy(\.isLetter) else { return .badCurrency }
            cleaned.currency = code.uppercased()
        } else {
            cleaned.currency = nil
        }
        if let days = renewal.remindDaysBefore, !(0...Renewal.maxRemindDays).contains(days) { return .badReminder }
        if let index = items.firstIndex(where: { $0.id == renewal.id }) {
            items[index] = cleaned
        } else {
            guard items.count < Self.limit else { return .full }
            items.append(cleaned)
        }
        return nil
    }

    public mutating func remove(_ id: UUID) { items.removeAll { $0.id == id } }

    /// By next date, soonest first.
    public func upcoming(now: Date, calendar: Calendar) -> [(renewal: Renewal, next: Date)] {
        items.map { ($0, $0.next(after: now, calendar: calendar)) }.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.name < $1.0.name }
    }

    /// A rough monthly cost per currency (weekly ×52/12, yearly /12), rounded to 2 places.
    /// Renewals without an amount are left out and counted.
    public func monthlyTotals() -> (totals: [(currency: String, amount: Decimal)], withoutAmount: Int) {
        var sums: [String: Decimal] = [:]
        var missing = 0
        for item in items {
            guard let monthly = item.monthlyAmount, let currency = item.currency else { missing += 1; continue }
            sums[currency, default: 0] += monthly
        }
        let rounded = sums.map { currency, amount -> (String, Decimal) in
            var value = amount
            var result = Decimal()
            NSDecimalRound(&result, &value, 2, .plain)
            return (currency, result)
        }
        return (rounded.sorted { $0.0 < $1.0 }, missing)
    }
}

extension VoiceToolName {
    public static let upcomingRenewals = "upcoming_renewals"
}

extension VoiceToolRequest {
    static func parseRenewals(_ args: Arguments, name: String) -> VoiceToolRequest {
        let days = args.number("days").map { Int($0) } ?? 30
        guard (1...92).contains(days) else { return .invalid(name: name, reason: "days must be 1 to 92") }
        return .upcomingRenewals(days: days)
    }
}

extension VoiceToolReply {
    /// What renews in the next `days` days, as the user typed it. Never guesses an amount.
    public static func renewals(_ upcoming: [(renewal: Renewal, next: Date)], days: Int, calendar: Calendar, now: Date) -> String {
        let end = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now
        let due = upcoming.filter { $0.next < end }
        guard !due.isEmpty else {
            return upcoming.isEmpty
                ? "The user hasn't added any bills or subscriptions in Doddy. Say so; they can add them in Lists, Bills and subscriptions."
                : "Nothing the user added renews in the next \(days) days. Say so; don't guess."
        }
        var lines = ["Renewing in the next \(days) days (as the user typed them in Doddy; amounts are theirs, not checked):"]
        for (renewal, next) in due {
            var line = "- \(renewal.name) on \(LeaveBy.day(next, calendar: calendar)), \(renewal.cycle.spoken)"
            if let amount = renewal.amount, let currency = renewal.currency { line += ", \(amount) \(currency)" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}

extension Renewal {
    /// The notification: what renews, when, and the user's own amount. Nothing more.
    public func notification(next: Date, calendar: Calendar, language: NotificationLanguage = .english) -> (title: String, body: String) {
        let parts = calendar.dateComponents([.day, .month], from: next)
        let day = String(format: "%02d.%02d", parts.day ?? 0, parts.month ?? 0)
        let money = amount.flatMap { value in currency.map { " (\(value) \($0))" } } ?? ""
        switch language {
        case .english: return ("\(name) renews soon", "On \(day)\(money). You added this in Doddy.")
        case .polish: return ("\(name) wkrótce się odnawia", "Dnia \(day)\(money). Dodano to w Doddy.")
        }
    }
}
