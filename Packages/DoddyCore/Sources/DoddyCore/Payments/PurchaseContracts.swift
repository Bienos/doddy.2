import Foundation

// Swift mirror of Doddy's purchases API (contracts/purchases/README.md, ADR-530). The server and
// these types decode the same fixtures in contracts/purchases/, so a change on one side that the
// other doesn't know fails a test before it reaches a phone.

/// `native`: paid inside Doddy with Apple Pay or BLIK, to Doddy's Stripe account on test keys in
/// this milestone. `checkout`: the shop's own checkout page, opened inside Doddy; the user pays the
/// shop there and Doddy never sees the money.
public enum PurchaseKind: String, Codable, Sendable {
    case native, checkout
}

/// Where the server's payments come from.
public enum PurchaseMode: String, Codable, Sendable {
    /// The server's demo mode: nothing reaches Stripe.
    case mock
    /// Stripe with test keys: real Stripe calls, no real money.
    case test
}

public enum PurchaseMethod: String, Codable, Sendable, CaseIterable {
    case applePay = "apple_pay"
    case blik

    public var title: String {
        switch self {
        case .applePay: "Apple Pay"
        case .blik: "BLIK"
        }
    }
}

public enum PurchaseStatus: String, Codable, Sendable, CaseIterable {
    /// Prepared and shown on the card; nothing paid.
    case awaitingTap = "awaiting_tap"
    /// Sent to Stripe, no answer yet.
    case paying
    /// BLIK code sent; the user approves in the bank app.
    case waitingForBank = "waiting_for_bank"
    /// Stripe says the payment went through. The only status Doddy calls paid.
    case paid
    /// It didn't go through, or was never sent. Nothing was charged.
    case failed
    /// Sent, but Doddy can't tell yet whether it went through. Never shown as paid, never retried by itself.
    case outcomeUnknown = "outcome_unknown"
    case cancelled
    /// The card's approval ran out before the user paid.
    case expired
    /// The shop's checkout page was opened; Doddy can't see what happened there.
    case handedOff = "handed_off"
    /// After a hand-off, the user said they paid. Doddy didn't see the payment itself.
    case userReportedPaid = "user_reported_paid"

    /// Worth asking the server again: the payment is in flight or its outcome isn't known yet.
    public var needsStatusCheck: Bool {
        switch self {
        case .paying, .waitingForBank, .outcomeUnknown: true
        case .awaitingTap, .paid, .failed, .cancelled, .expired, .handedOff, .userReportedPaid: false
        }
    }

    /// Nothing will change any more, whatever the user or the server does.
    public var isFinal: Bool {
        switch self {
        case .paid, .failed, .cancelled, .expired, .userReportedPaid: true
        case .awaitingTap, .paying, .waitingForBank, .outcomeUnknown, .handedOff: false
        }
    }
}

/// One purchase as the server keeps it. `summary` is a plain sentence for the screen and the agent.
public struct PurchaseView: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let kind: PurchaseKind
    public let merchantName: String
    public let description: String
    /// Whole grosze (PLN is the only currency in this milestone).
    public let amountMinor: Int
    public let currency: String
    /// Checkout only: the host of the page that opens.
    public let checkoutHost: String?
    public let status: PurchaseStatus
    public let method: PurchaseMethod?
    /// Native purchases on Stripe test keys or the server's demo mode: no real money moves.
    public let testMode: Bool
    public let summary: String
    public let createdAt: String
    public let updatedAt: String

    public init(
        id: UUID, kind: PurchaseKind, merchantName: String, description: String, amountMinor: Int, currency: String,
        checkoutHost: String?, status: PurchaseStatus, method: PurchaseMethod?, testMode: Bool, summary: String,
        createdAt: String, updatedAt: String
    ) {
        self.id = id
        self.kind = kind
        self.merchantName = merchantName
        self.description = description
        self.amountMinor = amountMinor
        self.currency = currency
        self.checkoutHost = checkoutHost
        self.status = status
        self.method = method
        self.testMode = testMode
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// The card's data: the purchase, and a single-use approval bound by the server to exactly what
/// the card shows. It runs out at `expiresAt`.
public struct PurchasePrepareResult: Codable, Equatable, Sendable {
    public let mode: PurchaseMode
    public let purchase: PurchaseView
    public let approvalId: UUID
    public let expiresAt: String
    /// Native: Apple Pay and BLIK. Checkout: none, the shop's page offers its own.
    public let methods: [PurchaseMethod]
    /// Native: the name on the Apple Pay sheet (who is actually paid). Checkout: the page's host.
    public let payee: String

    public init(mode: PurchaseMode, purchase: PurchaseView, approvalId: UUID, expiresAt: String, methods: [PurchaseMethod], payee: String) {
        self.mode = mode
        self.purchase = purchase
        self.approvalId = approvalId
        self.expiresAt = expiresAt
        self.methods = methods
        self.payee = payee
    }

    /// When the approval runs out, or nil when the server's date can't be read (then the server decides).
    public var expiryDate: Date? { PurchaseDates.parse(expiresAt) }
}

public struct PurchaseResult: Codable, Equatable, Sendable {
    public let mode: PurchaseMode
    public let purchase: PurchaseView
}

public struct HandoffResult: Codable, Equatable, Sendable {
    public let mode: PurchaseMode
    public let purchase: PurchaseView
    public let checkoutUrl: String
}

public struct PurchasesList: Codable, Equatable, Sendable {
    public let purchases: [PurchaseView]
}

// MARK: Requests

public struct PreparePurchaseRequest: Encodable, Equatable, Sendable {
    public let kind: PurchaseKind
    public let merchantName: String
    public let description: String
    public let amountMinor: Int
    public let currency: String
    /// Checkout only; left out of the JSON for native purchases.
    public let checkoutUrl: String?

    public init(kind: PurchaseKind, merchantName: String, description: String, amountMinor: Int, currency: String, checkoutUrl: String?) {
        self.kind = kind
        self.merchantName = merchantName
        self.description = description
        self.amountMinor = amountMinor
        self.currency = currency
        self.checkoutUrl = checkoutUrl
    }
}

/// What the Apple Pay sheet returned, passed through to Doddy's server untouched. The phone never
/// reads the card behind it.
public struct ApplePayTokenData: Encodable, Equatable, Sendable {
    /// `PKPaymentToken.paymentData` as a UTF-8 string. Empty only in the simulator.
    public let paymentData: String
    public let network: String?
    public let instrumentName: String?
    public let transactionId: String?

    public init(paymentData: String, network: String?, instrumentName: String?, transactionId: String?) {
        self.paymentData = paymentData
        self.network = network
        self.instrumentName = instrumentName
        self.transactionId = transactionId
    }
}

public enum PurchasePayment: Equatable, Sendable {
    case applePay(ApplePayTokenData)
    /// Exactly six digits (`BlikCode.normalize`). Sent once, never kept on the phone or the server.
    case blik(code: String)

    public var method: PurchaseMethod {
        switch self {
        case .applePay: .applePay
        case .blik: .blik
        }
    }
}

struct PayRequestBody: Encodable, Equatable {
    let purchaseId: String
    let approvalId: String
    let method: PurchaseMethod
    let applePay: ApplePayTokenData?
    let blikCode: String?

    init(purchaseId: UUID, approvalId: UUID, payment: PurchasePayment) {
        self.purchaseId = purchaseId.uuidString.lowercased()
        self.approvalId = approvalId.uuidString.lowercased()
        method = payment.method
        switch payment {
        case .applePay(let token):
            applePay = token
            blikCode = nil
        case .blik(let code):
            applePay = nil
            blikCode = code
        }
    }
}

struct PurchaseIDBody: Encodable, Equatable {
    let purchaseId: String
    init(_ id: UUID) { purchaseId = id.uuidString.lowercased() }
}

struct HandoffBody: Encodable, Equatable {
    let purchaseId: String
    let approvalId: String
    init(purchaseId: UUID, approvalId: UUID) {
        self.purchaseId = purchaseId.uuidString.lowercased()
        self.approvalId = approvalId.uuidString.lowercased()
    }
}

struct ReportBody: Encodable, Equatable {
    let purchaseId: String
    let paid: Bool
    init(purchaseId: UUID, paid: Bool) {
        self.purchaseId = purchaseId.uuidString.lowercased()
        self.paid = paid
    }
}

/// The server's ISO 8601 timestamps, with or without milliseconds.
public enum PurchaseDates {
    public static func parse(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}
