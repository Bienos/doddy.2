import Foundation

// Swift mirror of the payments API v1 (backend/src/payments/contracts.ts). Both sides decode the
// shared fixtures in contracts/payments/, written by the backend (`npm run fixtures`), so they
// cannot drift silently. Nothing here can name a wallet, an amount or a recipient: the app only
// ever sends a page address and an approval, and shows what the server says.

public enum PaymentWalletKind: String, Codable, Sendable {
    /// No wallet is set up on the server: nothing can be paid.
    case none
    /// The offline demo wallet: no real money, ever.
    case mock
    case coinbaseCdp = "coinbase_cdp"
}

public struct PaymentWalletInfo: Codable, Equatable, Sendable {
    public let kind: PaymentWalletKind
    public let configured: Bool
    /// Shortened account, e.g. "0x1234…abcd"; nil when there is no wallet.
    public let account: String?
    public let network: String
    /// True for a test network: no real money moves.
    public let testNetwork: Bool
}

public struct PaymentLimits: Codable, Equatable, Sendable {
    public let perPayment: String
    public let perDay: String
    public let usedToday: String
    public let asset: String
}

public struct PaymentStatus: Codable, Equatable, Sendable {
    public let mode: ConnectedAppsMode
    public let wallet: PaymentWalletInfo
    /// The person's own switch. It starts off.
    public let enabled: Bool
    public let limits: PaymentLimits
    /// Payments that were sent but never confirmed. The person should check the wallet's history.
    public let unresolved: Int
}

/// Sanitized record of one payment step. Site name and amount only, never the page path or query.
public struct PaymentReceipt: Codable, Equatable, Sendable, Identifiable {
    public enum Operation: String, Codable, Sendable {
        case switchPayments = "switch"
        case prepare, pay
    }

    public let operationId: UUID
    public let operation: Operation
    public let timestamp: String
    public let mode: ConnectedAppsMode
    public let status: ReceiptStatus
    public let summary: String
    public let errorCode: String?
    public let host: String?
    /// USDC, e.g. "0.05".
    public let amount: String?
    /// Only when the seller's settlement answer was valid; never invented.
    public let transaction: String?

    public var id: UUID { operationId }
}

public struct PaymentPreview: Codable, Equatable, Sendable {
    public let title: String
    public let lines: [String]
    public let confirmLabel: String
}

public struct PaymentPrepared: Codable, Equatable, Sendable {
    public let mode: ConnectedAppsMode
    public let preview: PaymentPreview
    /// USDC, e.g. "0.25": what the person must type when `confirmAmountRequired`.
    public let amount: String
    /// From the server's threshold up, the person must also type the amount. The server refuses a payment without it.
    public let confirmAmountRequired: Bool
    public let approvalId: UUID
    public let expiresAt: String

    /// When the approval stops working. Nil if the server's time can't be read (the server decides anyway).
    public var expiryDate: Date? { PaymentTime.parse(expiresAt) }
}

public struct PaymentResult: Codable, Equatable, Sendable {
    public let mode: ConnectedAppsMode
    /// Written for the voice agent. The app shows `receipt`, not this.
    public let text: String
    public let receipt: PaymentReceipt
}

public struct PaymentSwitchResult: Codable, Equatable, Sendable {
    public let status: PaymentStatus
    public let receipt: PaymentReceipt
}

public struct PaymentReceiptsResponse: Codable, Equatable, Sendable {
    public let receipts: [PaymentReceipt]
}

public struct PaymentErrorBody: Codable, Equatable, Sendable {
    public struct Detail: Codable, Equatable, Sendable {
        public let code: String
        public let message: String
        public let correlationId: String
        public let retryAfterSeconds: Int?
        public let receipt: PaymentReceipt?
    }
    public let error: Detail
}

public enum PaymentTime {
    /// The server writes ISO 8601 with milliseconds ("2026-10-12T10:02:00.000Z").
    public static func parse(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
