import Foundation

// Invoices through inFakt (ADR-633): the small types an invoice is made of. Nothing here talks to
// the network. The rules come from the owner's research (docs/research/2026-10-24/
// research_expert_modes_PL.md section 5): Doddy never guesses a NIP, an address or a VAT rate, and
// the sums are worked out by code, in integer grosze, not by the model.
//
// Platforms: iPhone and iPad. Pure logic; tested on Linux.

/// Where a field's value came from. A value the model proposed is not an invoice's data until the
/// person has said it or confirmed it: validation counts such a value as missing.
public enum FieldSource: String, Codable, Sendable {
    /// The person said or typed it.
    case saidByUser
    /// The person's own saved default (for example their usual VAT rate), shown as such.
    case userDefault
    /// The model suggested it. Never enough on its own.
    case proposedByModel
}

public struct Sourced<Value: Equatable & Sendable & Codable>: Equatable, Sendable, Codable {
    public let value: Value
    public let source: FieldSource

    public init(_ value: Value, source: FieldSource) {
        self.value = value
        self.source = source
    }

    /// True when the person said it or it is their own default.
    public var isConfirmed: Bool { source != .proposedByModel }
}

/// A Polish tax number (NIP): ten digits, the last a check digit (weights 6, 5, 7, 2, 3, 4, 5, 6, 7,
/// the weighted sum modulo 11). A number whose sum gives 10 is invalid. Accepts a leading "PL",
/// spaces and dashes; keeps only the ten digits.
public struct Nip: Equatable, Hashable, Sendable, Codable {
    public let digits: String

    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.uppercased().hasPrefix("PL") { text = String(text.dropFirst(2)) }
        let digits = text.filter { $0 != "-" && $0 != " " }
        guard digits.count == 10, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let values = digits.compactMap(\.wholeNumberValue)
        let weights = [6, 5, 7, 2, 3, 4, 5, 6, 7]
        let sum = zip(values.prefix(9), weights).reduce(0) { $0 + $1.0 * $1.1 }
        guard sum % 11 == values[9] else { return nil }
        self.digits = digits
    }

    /// "106-000-60-24".
    public var display: String {
        let d = Array(digits)
        return "\(String(d[0..<3]))-\(String(d[3..<6]))-\(String(d[6..<8]))-\(String(d[8..<10]))"
    }
}

/// A calendar day with no time and no time zone: an invoice's dates are days, not instants.
public struct CalendarDate: Equatable, Hashable, Comparable, Sendable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (2000...2100).contains(year), (1...12).contains(month), day >= 1,
              day <= Self.daysIn(month: month, year: year) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// "YYYY-MM-DD", exactly, and a real day.
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public static func < (a: CalendarDate, b: CalendarDate) -> Bool { a.serial < b.serial }

    /// The day `days` after this one (before it when negative); nil outside 2000 to 2100.
    public func adding(days: Int) -> CalendarDate? {
        let (y, m, d) = Self.civil(fromSerial: serial + days)
        return CalendarDate(year: y, month: m, day: d)
    }

    // Days since 1970-01-01 and back (Howard Hinnant's civil-date algorithms).
    private var serial: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    private static func civil(fromSerial z0: Int) -> (Int, Int, Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

/// A VAT rate as a Polish invoice states it: 23, 8, 5 or 0 percent, "zw" (exempt) or "np" (not
/// subject to VAT). The symbols are the ones inFakt's own help center lists for its invoice action;
/// whether the raw API takes exactly these is still to be confirmed in the sandbox
/// (docs/implementation/INFAKT_STATUS.md).
public enum VatRate: Equatable, Hashable, Sendable, Codable {
    case percent(Int)
    case exempt
    case notSubject

    public static let allowedPercents = [23, 8, 5, 0]

    public init?(symbol: String) {
        switch symbol.lowercased().trimmingCharacters(in: .whitespaces) {
        case "zw": self = .exempt
        case "np": self = .notSubject
        case let text:
            guard let value = Int(text), Self.allowedPercents.contains(value) else { return nil }
            self = .percent(value)
        }
    }

    public var symbol: String {
        switch self {
        case .percent(let value): String(value)
        case .exempt: "zw"
        case .notSubject: "np"
        }
    }

    /// The percentage tax is worked out with: 0 for exempt and not subject.
    public var percent: Int {
        if case .percent(let value) = self { return value }
        return 0
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let rate = VatRate(symbol: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown VAT symbol"))
        }
        self = rate
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(symbol)
    }
}

/// Currencies inFakt's invoice action lists (PLN, EUR, USD, GBP).
public enum InvoiceCurrency: String, Codable, CaseIterable, Sendable {
    case pln = "PLN", eur = "EUR", usd = "USD", gbp = "GBP"
}

/// How the buyer pays; the values inFakt's help center lists.
public enum InvoicePayment: String, Codable, CaseIterable, Sendable {
    case transfer, cash, card, paypal, barter, cod

    /// Needs a due date on the invoice: everything that is paid later than at the till.
    var needsDueDate: Bool { self == .transfer || self == .cod || self == .barter || self == .paypal }
}

/// Money as text. Amounts are integer grosze (or cents) everywhere; text is only made at the edge.
public enum MoneyText {
    /// "1 230,00 PLN" in Polish, "1,230.00 PLN" otherwise. Negative amounts keep their minus.
    public static func format(_ minor: Int, currency: InvoiceCurrency, polish: Bool) -> String {
        let negative = minor < 0
        let absolute = minor.magnitude
        let whole = String(absolute / 100)
        var grouped = ""
        for (offset, character) in whole.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 { grouped.append(polish ? "\u{00A0}" : ",") }
            grouped.append(character)
        }
        let digits = String(grouped.reversed())
        let cents = String(format: "%02d", absolute % 100)
        return "\(negative ? "-" : "")\(digits)\(polish ? "," : ".")\(cents) \(currency.rawValue)"
    }
}
