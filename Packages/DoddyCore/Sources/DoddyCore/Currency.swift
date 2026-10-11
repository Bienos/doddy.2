import Foundation

// Currency conversion by voice (ADR-291). The agent passes an amount and two currency codes; the
// app converts with the European Central Bank's euro reference rates, published once a working
// day as one public file. The iPhone downloads that file itself: nothing about the user is sent
// (no account, no key, no amount), only an ordinary request for the file. The answer always gives
// the rates' date, and says when they are the last ones the app has because it couldn't get
// newer ones. Nothing is guessed: with no rates, nothing is converted. Banks and cards use their
// own, usually worse, rates; the answer says so.

extension VoiceToolName {
    public static let convertCurrency = "convert_currency"
}

/// The ECB's euro reference rates for one day: how much of each currency one euro buys.
public struct ExchangeRates: Codable, Equatable, Sendable {
    /// The day the ECB published them for, YYYY-MM-DD.
    public let date: String
    /// Currency code (ISO 4217, upper case) → units per 1 EUR. EUR itself is 1.
    public let perEuro: [String: Double]

    public init(date: String, perEuro: [String: Double]) {
        self.date = date
        var rates = perEuro
        rates["EUR"] = 1
        self.perEuro = rates
    }

    public var codes: [String] { perEuro.keys.sorted() }
}

public enum ExchangeRateSource {
    /// The one file the app downloads. Fixed: the agent can't choose another address.
    public static let url = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    /// The file is about 2 KB; anything far larger isn't it.
    public static let maxBytes = 64 * 1024
    /// Fetched again after this long; the ECB publishes once a working day, around 16:00 CET.
    public static let refreshAfter: TimeInterval = 6 * 3600

    /// Reads the ECB file: one `time='YYYY-MM-DD'` and `currency='XXX' rate='1.234'` pairs.
    /// Nil when it isn't that file (no date, no rates, or a rate that isn't a positive number).
    public static func parse(_ xml: String) -> ExchangeRates? {
        guard let date = firstMatch(#"time=['"](\d{4}-\d{2}-\d{2})['"]"#, in: xml)?.first else { return nil }
        let pairs = allMatches(#"currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9]+(?:\.[0-9]+)?)['"]"#, in: xml)
        var rates: [String: Double] = [:]
        for pair in pairs {
            guard pair.count == 2, let rate = Double(pair[1]), rate > 0, rate.isFinite else { return nil }
            rates[pair[0]] = rate
        }
        guard rates.count >= 5 else { return nil }
        return ExchangeRates(date: date, perEuro: rates)
    }

    /// True when the app should try for newer rates.
    public static func needsRefresh(fetchedAt: Date?, now: Date) -> Bool {
        guard let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) >= refreshAfter || now < fetchedAt
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        allMatches(pattern, in: text).first
    }

    private static func allMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) }
            }
        }
    }
}

public struct CurrencyConversionRequest: Equatable, Sendable {
    public let amount: Double
    public let from: String
    public let to: String

    public init(amount: Double, from: String, to: String) {
        self.amount = amount
        self.from = from
        self.to = to
    }
}

public enum CurrencyConversion {
    public enum Failure: Error, Equatable, Sendable {
        case unknownCurrency(String)
        case notFinite
        case negative
    }

    public struct Result: Equatable, Sendable {
        public let amount: Double
        public let from: String
        public let converted: Double
        public let to: String
        /// 1 `from` in `to`.
        public let rate: Double
        public let date: String
    }

    /// Common spoken names the agent may pass instead of a code. Only names that mean one
    /// currency; "dollar", "crown" or "franc" alone stay ambiguous and must be a code.
    static let names: [String: String] = [
        "euro": "EUR", "euros": "EUR", "€": "EUR",
        "zloty": "PLN", "złoty": "PLN", "zlotys": "PLN", "złotych": "PLN", "zł": "PLN",
        "pound": "GBP", "pounds": "GBP", "sterling": "GBP", "£": "GBP",
        "yen": "JPY", "¥": "JPY",
        "forint": "HUF", "lei": "RON", "leu": "RON",
        "hryvnia": "UAH", "lira": "TRY", "rupee": "INR", "rupees": "INR",
    ]

    public static func code(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let named = names[trimmed.lowercased()] { return named }
        return trimmed.uppercased()
    }

    public static func convert(_ request: CurrencyConversionRequest, rates: ExchangeRates) -> Swift.Result<Result, Failure> {
        guard request.amount.isFinite else { return .failure(.notFinite) }
        guard request.amount >= 0 else { return .failure(.negative) }
        let from = code(request.from), to = code(request.to)
        guard let fromRate = rates.perEuro[from] else { return .failure(.unknownCurrency(from)) }
        guard let toRate = rates.perEuro[to] else { return .failure(.unknownCurrency(to)) }
        let rate = toRate / fromRate
        let converted = request.amount * rate
        guard converted.isFinite else { return .failure(.notFinite) }
        return .success(Result(amount: request.amount, from: from, converted: converted, to: to, rate: rate, date: rates.date))
    }

    /// Money as people say it: two decimals (none for currencies without minor units).
    public static func money(_ value: Double, _ code: String) -> String {
        let digits = ["JPY", "KRW", "ISK", "HUF"].contains(code) ? 0 : 2
        // Half away from zero, as people round money (printf alone rounds 0.5 to even).
        let scale = digits == 0 ? 1.0 : 100.0
        let rounded = (value * scale).rounded(.toNearestOrAwayFromZero) / scale
        return String(format: "%.\(digits)f", rounded) + " " + code
    }

    static func rateText(_ value: Double) -> String {
        String(format: value >= 100 ? "%.2f" : "%.4f", value)
    }
}

extension VoiceToolRequest {
    /// amount (a number), from and to (ISO codes such as EUR, PLN, USD).
    static func parseCurrency(_ args: Arguments, name: String) -> VoiceToolRequest {
        let amount = args.number("amount") ?? args.text("amount").flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard let amount, amount.isFinite else { return .invalid(name: name, reason: "amount must be a number written with a dot, e.g. 49.99") }
        guard let from = args.text("from"), let to = args.text("to") else { return .invalid(name: name, reason: "give from and to as currency codes, e.g. EUR and PLN") }
        return .convertCurrency(CurrencyConversionRequest(amount: amount, from: from, to: to))
    }
}

extension VoiceToolReply {
    /// `rates` nil: none could be fetched and none were kept. `isLastKnown`: newer ones couldn't
    /// be fetched, so these are the last the app has.
    public static func currency(_ request: CurrencyConversionRequest, rates: ExchangeRates?, isLastKnown: Bool) -> String {
        guard let rates else {
            return "failed: the exchange rates couldn't be fetched (no connection, or the European Central Bank didn't answer). Nothing was converted. Don't guess a rate; tell the user."
        }
        switch CurrencyConversion.convert(request, rates: rates) {
        case .success(let result):
            var text = "converted: \(CurrencyConversion.money(result.amount, result.from)) = \(CurrencyConversion.money(result.converted, result.to)), "
                + "at the European Central Bank reference rate for \(result.date) (1 \(result.from) = \(CurrencyConversion.rateText(result.rate)) \(result.to)). "
                + "Calculated by the app; say this number and the date, don't work it out again. A bank or card uses its own rate, usually a little worse."
            if isLastKnown {
                text += " These are the last rates the app has; it couldn't get newer ones, so say they're from \(result.date)."
            }
            return text
        case .failure(.unknownCurrency(let code)):
            return "failed: the European Central Bank publishes no rate for \"\(code)\". Use a three-letter code; it has: \(rates.codes.joined(separator: ", ")). Nothing was converted."
        case .failure(.notFinite):
            return "failed: the amount is too large to convert."
        case .failure(.negative):
            return "failed: the amount can't be negative. Nothing was converted."
        }
    }
}
