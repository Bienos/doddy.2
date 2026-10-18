import Foundation

// Rules for paying for things by voice (ADR-530), with no UI so they run on Linux. The server
// checks all of it again; these checks give the agent a precise reason before anything is sent.

/// What the agent proposed, after the app's checks. Nothing is charged from this: the server turns
/// it into a purchase and a single-use approval, the card shows that, and only the user's Apple
/// Pay, BLIK or "Open checkout" tap uses it.
public struct PurchaseDraft: Equatable, Sendable {
    public let kind: PurchaseKind
    public let merchantName: String
    public let description: String
    public let amountMinor: Int
    public let currency: String
    /// Checkout only.
    public let checkoutURL: URL?

    public init(kind: PurchaseKind, merchantName: String, description: String, amountMinor: Int, currency: String = "PLN", checkoutURL: URL?) {
        self.kind = kind
        self.merchantName = merchantName
        self.description = description
        self.amountMinor = amountMinor
        self.currency = currency
        self.checkoutURL = checkoutURL
    }

    public var request: PreparePurchaseRequest {
        PreparePurchaseRequest(
            kind: kind, merchantName: merchantName, description: description, amountMinor: amountMinor,
            currency: currency, checkoutUrl: checkoutURL?.absoluteString)
    }
}

public enum PurchaseLimits {
    public static let merchantNameLength = 80
    public static let descriptionLength = 200
    /// Stripe's smallest PLN charge.
    public static let nativeMinimumMinor = 200
    /// A sanity bound on what the agent may propose; the server's own caps are far lower.
    public static let proposalMaximumMinor = 10_000_000
    public static let checkoutURLLength = 2_048
    /// PLN only in this milestone: BLIK is PLN-only and the Apple Pay sheet is set up for Poland.
    public static let currency = "PLN"
}

public enum PurchaseMoney {
    /// "56,00 zł", "1 234,50 zł": how Polish shops write prices. Other currencies keep their code.
    public static func format(minor: Int, currency: String = PurchaseLimits.currency) -> String {
        let sign = minor < 0 ? "-" : ""
        let value = abs(minor)
        let whole = value / 100
        let fraction = value % 100
        var digits = String(whole)
        var grouped = ""
        while digits.count > 3 {
            grouped = " " + String(digits.suffix(3)) + grouped
            digits.removeLast(3)
        }
        let amount = "\(sign)\(digits)\(grouped),\(fraction < 10 ? "0" : "")\(fraction)"
        return currency.uppercased() == "PLN" ? "\(amount) zł" : "\(amount) \(currency.uppercased())"
    }

    /// Whole grosze from an amount in złoty the agent said ("56", 56.5). More than two decimals,
    /// zero, negative or absurd amounts are refused, never rounded into something the user didn't hear.
    public static func minor(fromMajor value: Double) -> Int? {
        guard value.isFinite, value > 0 else { return nil }
        let scaled = value * 100
        let rounded = scaled.rounded()
        guard abs(scaled - rounded) < 0.000_1, rounded <= Double(PurchaseLimits.proposalMaximumMinor) else { return nil }
        return Int(rounded)
    }

    /// The amount for the Apple Pay sheet.
    public static func decimal(minor: Int) -> Decimal {
        Decimal(minor) / 100
    }
}

/// A BLIK code from the user's bank app: six digits, valid for two minutes. Spaces and dashes the
/// user typed are dropped; anything else is refused.
public enum BlikCode {
    public static func normalize(_ raw: String) -> String? {
        let digits = raw.filter { !$0.isWhitespace && $0 != "-" }
        guard digits.count == 6, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return digits
    }
}

/// The checkout page a hand-off opens. Mirrors the server's rule (the server decides): https, a
/// real host name, no user name or password, not an IP address or localhost, at most 2048 characters.
public enum CheckoutLink {
    public static func validate(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= PurchaseLimits.checkoutURLLength,
              let url = URL(string: text),
              url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              let host = host(of: url) else { return nil }
        return isAllowedHost(host) ? url : nil
    }

    /// Lowercased host without brackets, or nil when there is none.
    public static func host(of url: URL) -> String? {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        return host
    }

    static func isAllowedHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") { return false }
        if host.contains(":") { return false } // IPv6 literal
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 4, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) { return false } // IPv4 literal
        // A name with at least one dot, made of letters, digits and hyphens.
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        return host.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }
    }
}

/// The lines of the Apple Pay sheet: what is bought, then the total, labelled with who is really
/// paid (`payee`, e.g. "Doddy (test)"), never the shop's name when the shop isn't the one paid.
public struct ApplePaySheet: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public let label: String
        public let amount: Decimal
    }

    public let lines: [Line]
    public let currency: String
    public let countryCode: String

    public init(prepared: PurchasePrepareResult) {
        let purchase = prepared.purchase
        let amount = PurchaseMoney.decimal(minor: purchase.amountMinor)
        let item = purchase.testMode ? "\(purchase.merchantName) (test, no real money)" : purchase.merchantName
        lines = [Line(label: item, amount: amount), Line(label: prepared.payee, amount: amount)]
        currency = purchase.currency.uppercased()
        countryCode = "PL"
    }
}

/// How long the app keeps asking about a BLIK payment the bank app hasn't approved yet: every
/// two seconds at first, then less often, for two minutes (a BLIK code's own lifetime). After
/// that the card says Doddy isn't sure and offers "Check again"; nothing is paid twice.
public enum PurchasePolling {
    public static let blikWindowSeconds: Double = 120

    public static func delays(window: Double = blikWindowSeconds) -> [Double] {
        var delays: [Double] = []
        var total = 0.0
        while total < window {
            let next = total < 20 ? 2.0 : (total < 60 ? 4.0 : 8.0)
            let step = min(next, window - total)
            delays.append(step)
            total += step
        }
        return delays
    }
}

extension VoiceToolReply {
    /// The result the agent hears once the card is settled. Only "paid:" counts as done, and only
    /// when Stripe confirmed it through Doddy's server.
    public static func purchaseOutcome(_ purchase: PurchaseView) -> String {
        let test = purchase.testMode ? " Say it was a test payment with no real money." : ""
        switch purchase.status {
        case .paid:
            return "paid: \(purchase.summary) Tell the user in one sentence.\(test)"
        case .failed:
            return "failed: \(purchase.summary) Nothing was charged."
        case .outcomeUnknown, .paying, .waitingForBank:
            return "unknown: \(purchase.summary) Ask the user to check their bank app before trying again. Don't try again yourself."
        case .cancelled:
            return "declined: the user chose not to pay for \(purchase.merchantName). Nothing was paid."
        case .expired:
            return "failed: the card ran out before the user paid. Nothing was paid; offer to prepare it again."
        case .handedOff:
            return "opened: \(purchase.summary) Don't say it was paid."
        case .userReportedPaid:
            return "opened: \(purchase.summary) Don't say Doddy confirmed it."
        case .awaitingTap:
            return "unknown: the card was closed before the user chose. Nothing was paid."
        }
    }

    /// The server or the network said no before a card was shown. Nothing can have been paid.
    public static func purchaseNotPrepared(_ error: PaymentsError) -> String {
        switch error {
        case .notConfigured:
            "failed: Payments aren't set up in this version of the app. Tell the user in one sentence. Nothing was paid."
        case .unauthenticated:
            "failed: Doddy's server didn't accept this device. Tell the user to check Settings. Nothing was paid."
        case .server(_, let message, _):
            "failed: \(message) Nothing was paid."
        case .transport, .unreadableResponse:
            "failed: Doddy's server couldn't prepare the payment. Nothing was paid."
        }
    }

    /// The user paid on the card but the answer was lost on the way back: it may have gone through.
    public static func purchaseLost(_ merchantName: String) -> String {
        "unknown: the app lost the answer while paying \(merchantName). It may have gone through; ask the user to check their bank app before trying again. Don't try again yourself."
    }
}
