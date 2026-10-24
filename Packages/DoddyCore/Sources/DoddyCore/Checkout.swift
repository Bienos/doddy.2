import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// Buying through Doddy, stage 3 of shopping mode (docs/implementation/SHOPPING_CHECKOUT.md, ADR-613).
// The owner asked on 24 Oct 2026 to start in-app payment. What can be built before any payment
// provider, shop agreement or legal opinion exists is the rules, as typed code that tests can hold:
//
//  - the user's yes is bound to the exact cart (a SHA-256 digest of its canonical form, like errands);
//  - a purchase is sent to the provider at most once, and only after that yes;
//  - "ordered" is only ever said after the shop's own confirmation with its order reference;
//  - a send with no trustworthy answer is `unknown`: never success, never failure, never sent again;
//    the only thing allowed afterwards is a read-only look-up (constitution: external writes,
//    `unknown_status_must_not_claim_success`, `ambiguous_write_retry: reconciliation_first`).
//
// Nothing here moves money, talks to a provider or is reachable from the app: there is no provider,
// no server route and no screen yet, and no tool for the voice agent. Do not read this file as "payments
// work".

// MARK: - The cart

public struct CheckoutLine: Equatable, Sendable {
    public let title: String
    public let quantity: Int
    /// Price of one, in minor units (grosze), in the cart's currency.
    public let unitMinor: Int

    public init(title: String, quantity: Int, unitMinor: Int) {
        self.title = title
        self.quantity = quantity
        self.unitMinor = unitMinor
    }
}

/// Why a cart can't be shown for approval or sent. Never mentions what the user typed.
public enum CheckoutIssue: Equatable, Sendable {
    case emptyField(String)
    case badShopHost
    case badCurrency
    case noLines
    case tooManyLines
    case badQuantity(line: Int)
    case badPrice(line: Int)
    case badShippingOrTotal
    case totalDoesNotAddUp
    case overTheLimit
    case badExpiry
}

/// The exact order the user is asked to approve: what the shop quoted, written once and never changed
/// after the approval. `shopReference` is the shop's own reference for this cart or quote, so what the
/// user approved is what the shop will take.
public struct CheckoutDraft: Equatable, Sendable {
    public static let maxLines = 10
    public static let maxQuantity = 99
    /// Doddy's own ceiling for one order, in minor units (5,000 zł). A placeholder until the owner
    /// decides (ADR-613, open): it is a guard against a misheard amount, not a bank's or a shop's limit.
    public static let maxTotalMinor = 500_000

    /// The shop's name as the user knows it.
    public let shop: String
    /// The shop's own host (`mediaexpert.pl`): where the order goes, shown on the card.
    public let shopHost: String
    public let shopReference: String
    public let currency: String
    public let lines: [CheckoutLine]
    public let shippingMinor: Int
    /// What the user will pay, as the shop quoted it: the lines plus shipping.
    public let totalMinor: Int
    /// When the shop's quote lapses, as the shop wrote it (ISO 8601).
    public let quoteExpiresAt: String

    public init(shop: String, shopHost: String, shopReference: String, currency: String = "PLN", lines: [CheckoutLine],
                shippingMinor: Int, totalMinor: Int, quoteExpiresAt: String) {
        self.shop = shop
        self.shopHost = shopHost
        self.shopReference = shopReference
        self.currency = currency
        self.lines = lines
        self.shippingMinor = shippingMinor
        self.totalMinor = totalMinor
        self.quoteExpiresAt = quoteExpiresAt
    }

    public func validationIssues() -> [CheckoutIssue] {
        var issues: [CheckoutIssue] = []
        func clean(_ text: String, max: Int) -> Bool {
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= max
                && !text.unicodeScalars.contains { $0.value < 0x20 }
        }
        if !clean(shop, max: 80) { issues.append(.emptyField("shop")) }
        if !clean(shopReference, max: 200) { issues.append(.emptyField("shopReference")) }
        if !Self.isHost(shopHost) { issues.append(.badShopHost) }
        if currency.unicodeScalars.count != 3 || !currency.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) }) {
            issues.append(.badCurrency)
        }
        if lines.isEmpty { issues.append(.noLines) }
        if lines.count > Self.maxLines { issues.append(.tooManyLines) }
        var sum = 0
        for (index, line) in lines.enumerated() {
            if !clean(line.title, max: 160) { issues.append(.emptyField("line \(index + 1) title")) }
            if line.quantity < 1 || line.quantity > Self.maxQuantity { issues.append(.badQuantity(line: index + 1)) }
            if line.unitMinor < 1 || line.unitMinor > 100_000_000 { issues.append(.badPrice(line: index + 1)) }
            else if line.quantity >= 1 && line.quantity <= Self.maxQuantity { sum += line.quantity * line.unitMinor }
        }
        if shippingMinor < 0 || shippingMinor > 100_000_000 || totalMinor < 1 { issues.append(.badShippingOrTotal) }
        else if sum + shippingMinor != totalMinor { issues.append(.totalDoesNotAddUp) }
        if totalMinor > Self.maxTotalMinor { issues.append(.overTheLimit) }
        if ServerDates.parse(quoteExpiresAt) == nil { issues.append(.badExpiry) }
        return issues
    }

    public var isValid: Bool { validationIssues().isEmpty }

    public func isExpired(at now: Date) -> Bool {
        guard let expires = ServerDates.parse(quoteExpiresAt) else { return true }
        return now >= expires
    }

    private static func isHost(_ text: String) -> Bool {
        guard text.count <= 100, text.contains("."), !text.hasPrefix("."), !text.hasSuffix("."),
              !text.hasPrefix("-"), !text.hasSuffix("-") else { return false }
        return text.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "." || $0 == "-" }
    }

    /// The exact text the digest is taken over: keys sorted, no spaces, strings escaped as JavaScript's
    /// `JSON.stringify` does (fixture checkout_draft_v1.json, so a future server computes the same).
    var canonicalJSON: String {
        let items = lines.map { "{\"quantity\":\($0.quantity),\"title\":\(ErrandDraft.jsonString($0.title)),\"unitMinor\":\($0.unitMinor)}" }
        return "{\"currency\":\(ErrandDraft.jsonString(currency)),\"lines\":[\(items.joined(separator: ","))],"
            + "\"quoteExpiresAt\":\(ErrandDraft.jsonString(quoteExpiresAt)),\"shippingMinor\":\(shippingMinor),"
            + "\"shop\":\(ErrandDraft.jsonString(shop)),\"shopHost\":\(ErrandDraft.jsonString(shopHost)),"
            + "\"shopReference\":\(ErrandDraft.jsonString(shopReference)),\"totalMinor\":\(totalMinor)}"
    }

    /// SHA-256 (hex) over `canonicalJSON`. The approval is bound to this digest: change a quantity, a
    /// price, the shop or the quote and it is a different cart that needs its own yes.
    public var digest: String {
        SHA256.hash(data: Data(canonicalJSON.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - The order's life

/// What came back after the order was sent (or when it was looked up afterwards).
public enum CheckoutAnswer: Equatable, Sendable {
    /// The shop confirmed the order and gave its own order reference.
    case confirmed(reference: String)
    /// The shop's provider said, in a trusted answer, that it did not take the order.
    case declined
    /// Anything else: no answer in time, a lost connection, a server error, an answer that can't be read, or a
    /// confirmation without an order reference.
    case noTrustworthyAnswer
}

/// The constitution's trusted statuses for a purchase (docs/trust/config/doddy_rules.yaml `action_policy`).
public enum CheckoutStatus: Equatable, Sendable {
    /// On the card, waiting for the user's tap. Nothing was sent.
    case needsApproval
    /// Approved and sent to the provider, once. Not ordered yet.
    case executing
    /// Confirmed by the shop with its order reference. The only status that may be called "ordered".
    case confirmed(reference: String)
    /// The shop did not take the order.
    case failed
    /// Sent, and no trustworthy answer came. Not success, not failure, never sent again.
    case unknown
    /// The user said no before anything was sent.
    case cancelled
}

public enum CheckoutError: Error, Equatable, Sendable {
    case notWaitingForApproval
    case digestDoesNotMatch
    case notValid([CheckoutIssue])
    case quoteExpired
    case notSent
    case notUnknown
}

/// One purchase from the card to the end. Only these moves exist, and none of them can send the order twice.
public struct CheckoutSession: Equatable, Sendable {
    public let draft: CheckoutDraft
    public private(set) var status: CheckoutStatus = .needsApproval
    /// How many times the order was handed to the provider. Zero or one, never more.
    public private(set) var timesSent = 0

    public init(draft: CheckoutDraft) {
        self.draft = draft
    }

    /// The user's tap on the card. `shownDigest` is the digest of the cart the card showed; it must be this
    /// cart's. Only a valid, unexpired cart waiting for approval can be approved, once.
    public mutating func approve(shownDigest: String, now: Date) throws {
        guard status == .needsApproval, timesSent == 0 else { throw CheckoutError.notWaitingForApproval }
        guard shownDigest == draft.digest else { throw CheckoutError.digestDoesNotMatch }
        let issues = draft.validationIssues()
        guard issues.isEmpty else { throw CheckoutError.notValid(issues) }
        guard !draft.isExpired(at: now) else { throw CheckoutError.quoteExpired }
        status = .executing
        timesSent = 1
    }

    /// The user said no. Only possible before anything was sent.
    public mutating func cancel() {
        if status == .needsApproval { status = .cancelled }
    }

    /// What the provider answered for the order that was sent. A confirmation counts only with an order
    /// reference; everything else that isn't a clear "declined" is `unknown`.
    public mutating func sendFinished(_ answer: CheckoutAnswer) throws {
        guard status == .executing else { throw CheckoutError.notSent }
        status = Self.status(for: answer, otherwise: .unknown)
    }

    /// A read-only look-up of an `unknown` order afterwards (never a second send). It can settle the order as
    /// confirmed or failed; with no trustworthy answer the order stays `unknown`.
    public mutating func reconcile(_ answer: CheckoutAnswer) throws {
        guard status == .unknown else { throw CheckoutError.notUnknown }
        status = Self.status(for: answer, otherwise: .unknown)
    }

    private static func status(for answer: CheckoutAnswer, otherwise: CheckoutStatus) -> CheckoutStatus {
        switch answer {
        case .confirmed(let reference):
            let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? otherwise : .confirmed(reference: trimmed)
        case .declined: return .failed
        case .noTrustworthyAnswer: return otherwise
        }
    }

    /// What the voice agent may say for this status, as a tool result (data for the agent, in English). The only
    /// status whose words allow "ordered" is `confirmed`.
    public var agentWords: String {
        switch status {
        case .needsApproval:
            "needs_approval: the user hasn't tapped the card yet. Nothing was sent to the shop and nothing was bought."
        case .executing:
            "executing: the order was sent to the shop and Doddy is waiting for the shop's confirmation. It is not ordered yet; don't say it is."
        case .confirmed(let reference):
            "confirmed: the shop confirmed the order, reference \"\(ErrandsPrompt.clip(reference, 80))\". Only now may you say it is ordered."
        case .failed:
            "failed: the shop did not take the order. Nothing is ordered."
        case .unknown:
            "unknown: the order was sent, but the shop's answer never came or couldn't be trusted. Don't say it is ordered and don't say it failed. Tell the user to check the shop's email or their bank, and that Doddy won't send it again."
        case .cancelled:
            "cancelled: the user said no. Nothing was sent or bought."
        }
    }
}
