import Foundation
import Observation

/// What iOS said when asked to confirm a payment with Face ID (or Touch ID, or the passcode).
public enum PaymentAuthResult: Equatable, Sendable {
    case confirmed
    /// The person cancelled or failed the check. Nothing was paid.
    case cancelled
    /// This iPhone has no Face ID, Touch ID or passcode to ask. A payment is never allowed without a check.
    case unavailable
}

/// Asks the person to prove it is them, fresh, for this one payment. The app's implementation lives
/// next to the app lock (the only file that may use LocalAuthentication); tests supply a fake.
@MainActor
public protocol PaymentAuthenticator {
    func confirm(reason: String) async -> PaymentAuthResult
}

/// The card that asks "pay this?" and what follows. One payment, one pass through these states:
///
///     idle -> preparing -> awaitingApproval -> authenticating -> paying -> paid
///                                  |                 |             |-> failed       (nothing was paid)
///                                  |                 |             `-> unconfirmed  (may have been paid)
///                                  `-> idle (cancel) `-> awaitingApproval (Face ID not confirmed)
///
/// The rules that matter, each enforced by the shape of this type rather than by the screen:
/// - The server is asked to pay at most once per approval: `pay` is reachable only from `authenticating`
///   after a confirmed check, and the next state is never one that can reach it again.
/// - Face ID is asked every time, right before paying; there is no remembered "yes".
/// - After the server has been asked to pay, anything unclear is `unconfirmed`, never `failed`: the
///   screen must not invite a retry that could pay twice.
/// - Cancelling or dismissing is impossible while the payment is being sent.
/// - What is shown is exactly what the server returned. The app never composes an amount or a recipient.
@MainActor
@Observable
public final class PaymentApprovalModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case preparing
        case awaitingApproval(PaymentPrepared)
        case authenticating(PaymentPrepared)
        case paying(PaymentPrepared)
        case paid(PaymentResult)
        /// The server said nothing was paid (or refused before trying). Safe to start again.
        case failed(String, PaymentReceipt?)
        /// The payment may or may not have gone through. Do not offer "pay again".
        case unconfirmed(String, PaymentReceipt?)
    }

    public private(set) var phase: Phase = .idle
    /// A short note that doesn't end the flow (e.g. Face ID wasn't confirmed).
    public private(set) var notice: String?

    private let client: any PaymentsClient
    private let authenticator: any PaymentAuthenticator
    private let now: @Sendable () -> Date
    private var url: String?
    private var sentAt: Date?

    public init(client: (any PaymentsClient)?, authenticator: any PaymentAuthenticator, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client ?? UnconfiguredPaymentsClient()
        self.authenticator = authenticator
        self.now = now
    }

    /// True while a payment is being decided or sent: the card must stay up and Cancel must be off.
    public var isBusy: Bool {
        switch phase {
        case .preparing, .authenticating, .paying: true
        default: false
        }
    }

    /// Dismissing the card is allowed only when nothing is in flight.
    public var canDismiss: Bool { !isBusy }

    /// The terms on screen, while there are any.
    public var prepared: PaymentPrepared? {
        switch phase {
        case .awaitingApproval(let p), .authenticating(let p), .paying(let p): p
        default: nil
        }
    }

    /// Seconds left on the approval, if the server's time can be read.
    public func secondsLeft() -> Int? {
        guard let prepared, let expiry = prepared.expiryDate else { return nil }
        return max(0, Int(expiry.timeIntervalSince(now()).rounded(.up)))
    }

    // MARK: Start

    /// Asks the server for the exact terms of paying this page. Pays nothing.
    public func start(url address: String) async {
        guard case .idle = phase else { return }
        let page = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !page.isEmpty else {
            phase = .failed("Enter the web address of the page to pay.", nil)
            return
        }
        notice = nil
        url = page
        phase = .preparing
        do {
            phase = .awaitingApproval(try await client.prepare(url: page))
        } catch {
            phase = .failed(error.userMessage, error.receipt)
        }
    }

    // MARK: Approve

    /// The person tapped the pay button. Face ID first, then (once) the payment.
    public func approve() async {
        // A second tap while the first is in flight lands here and does nothing.
        guard case .awaitingApproval(let prepared) = phase, let url else { return }
        if isExpired(prepared) {
            phase = .failed("This confirmation ran out. Nothing was paid. Start again to see the current price.", nil)
            return
        }
        notice = nil
        phase = .authenticating(prepared)
        let check = await authenticator.confirm(reason: prepared.preview.confirmLabel)
        guard case .authenticating = phase else { return }
        switch check {
        case .cancelled:
            phase = .awaitingApproval(prepared)
            notice = "Face ID wasn't confirmed. Nothing was paid."
            return
        case .unavailable:
            phase = .failed("Doddy can only pay after Face ID, Touch ID or a passcode. Set one up on this iPhone first. Nothing was paid.", nil)
            return
        case .confirmed:
            break
        }
        // The person may have taken a while to look at their face. Don't even ask the server with a stale approval.
        if isExpired(prepared) {
            phase = .failed("This confirmation ran out while you were confirming. Nothing was paid. Start again to see the current price.", nil)
            return
        }
        phase = .paying(prepared)
        sentAt = now()
        do {
            let result = try await client.pay(url: url, approvalId: prepared.approvalId)
            // Only a succeeded receipt is "paid". Anything else on a 200 is not trusted.
            if result.receipt.status == .succeeded {
                phase = .paid(result)
            } else {
                phase = .unconfirmed("Doddy's server answered, but didn't confirm the payment. It may or may not have gone through. Check your wallet's history before paying again.", result.receipt)
            }
        } catch {
            if error.mightHaveBeenPaid {
                let message = error.receipt?.status == .outcomeUnknown
                    ? error.userMessage
                    : "Doddy lost contact with its server while paying. The payment may or may not have gone through. Don't pay again yet: check your wallet's history."
                phase = .unconfirmed(message, error.receipt)
            } else {
                phase = .failed(error.userMessage, error.receipt)
            }
        }
    }

    // MARK: Cancel, finish, check again

    /// Cancel before paying. Nothing was sent to the wallet or the seller; the approval simply runs out.
    public func cancel() {
        guard case .awaitingApproval = phase else { return }
        phase = .idle
        notice = nil
        url = nil
    }

    /// Back to the start, after an outcome has been read.
    public func finish() {
        switch phase {
        case .paid, .failed, .unconfirmed:
            phase = .idle
            notice = nil
            url = nil
            sentAt = nil
        default:
            break
        }
    }

    /// The sheet was closed (swipe or button). Cancels before paying, clears an outcome that was read, and
    /// does nothing while a payment is being decided or sent.
    public func dismiss() {
        cancel()
        finish()
    }

    /// After an unconfirmed payment: ask Doddy's server what it recorded. The server's receipt, not a guess.
    public func checkAgain() async {
        guard case .unconfirmed(let message, _) = phase, let url, let sentAt else { return }
        let host = URL(string: url)?.host?.lowercased()
        let receipts: [PaymentReceipt]
        do {
            receipts = try await client.receipts()
        } catch {
            notice = error.userMessage
            return
        }
        // Newest first; the payment started after `sentAt` (a second of slack for clock rounding).
        let floor = sentAt.addingTimeInterval(-1)
        let mine = receipts.first { receipt in
            receipt.operation == .pay
                && receipt.host?.lowercased() == host
                && (PaymentTime.parse(receipt.timestamp).map { $0 >= floor } ?? false)
        }
        guard let mine else {
            notice = "Doddy's server has no record yet. Check your wallet's history."
            return
        }
        switch mine.status {
        case .succeeded:
            phase = .paid(PaymentResult(mode: mine.mode, text: mine.summary, receipt: mine))
            notice = nil
        case .failed, .blocked, .canceled:
            phase = .failed(mine.summary, mine)
            notice = nil
        case .outcomeUnknown:
            phase = .unconfirmed(message, mine)
            notice = "Still not confirmed. Check your wallet's history."
        }
    }

    private func isExpired(_ prepared: PaymentPrepared) -> Bool {
        guard let expiry = prepared.expiryDate else { return false } // unreadable: the server decides
        return expiry <= now()
    }
}
