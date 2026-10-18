import DoddyCore
import Foundation
import Observation

/// One purchase card, from the agent's proposal to the receipt (ADR-490). Nothing is paid until the
/// user taps Apple Pay (and Face ID), sends a BLIK code they typed, or opens the shop's checkout.
/// The agent hears the result once (`settle`); after that the card stays as a receipt the user can
/// check again or close, and nothing on it is ever paid a second time.
@MainActor
@Observable
final class PurchaseFlow {
    enum Phase: Equatable {
        /// The card as prepared; nothing paid.
        case ready
        /// Sent to Doddy's server, waiting for its answer.
        case paying(PurchaseMethod)
        /// BLIK sent; the user approves in the bank app.
        case waitingForBank(PurchaseView)
        case openingCheckout
        /// The agent has its answer. The card is a receipt from here on.
        case settled(PurchaseView)
        /// The app lost the server's answer while paying: it may have gone through.
        case lost
    }

    /// What the agent hears, once.
    enum Settlement: Equatable {
        case purchase(PurchaseView)
        /// The user said no before paying.
        case declined
        /// The answer was lost on the way back; it may have gone through.
        case lost
        /// The checkout page couldn't be opened; nothing was paid.
        case notOpened(String)
    }

    let toolCallID: String
    let prepared: PrepareResult
    private(set) var phase: Phase = .ready
    /// A plain sentence under the buttons when something needs the user's attention.
    private(set) var problem: String?
    /// The shop's page, while it is open in Safari's view.
    var checkoutURL: URL?
    /// The page the server handed over, so the receipt can open it again.
    private(set) var handoffURL: URL?
    /// The BLIK field. Cleared the moment the code is sent; never kept or logged.
    var blikCode = ""
    var isEnteringBlik = false
    private(set) var isChecking = false

    var purchase: PurchaseView {
        switch phase {
        case .waitingForBank(let latest), .settled(let latest): latest
        default: prepared.purchase
        }
    }
    var applePayAvailable: Bool { prepared.methods.contains(.applePay) && ApplePaySupport.isAvailable }
    var blikAvailable: Bool { prepared.methods.contains(.blik) }
    var isCheckout: Bool { prepared.purchase.kind == .checkout }
    /// Shown, but no payment step was started: dropped when the conversation ends.
    var isUntouched: Bool { phase == .ready && !started }

    private let client: any PaymentsClient
    private let presenter = ApplePayPresenter()
    private let onStart: @MainActor () -> Void
    private let onSettle: @MainActor (Settlement) async -> Void
    @ObservationIgnored private var started = false
    @ObservationIgnored private var replied = false
    @ObservationIgnored private var lastAnswer: Result<PurchaseView, PaymentsError>?

    init(
        toolCallID: String, prepared: PrepareResult, client: any PaymentsClient,
        onStart: @escaping @MainActor () -> Void, onSettle: @escaping @MainActor (Settlement) async -> Void
    ) {
        self.toolCallID = toolCallID
        self.prepared = prepared
        self.client = client
        self.onStart = onStart
        self.onSettle = onSettle
    }

    // MARK: Paying inside Doddy

    func payWithApplePay() async {
        guard phase == .ready, applePayAvailable else { return }
        problem = nil
        lastAnswer = nil
        let outcome = await presenter.present(ApplePaySheet(prepared: prepared)) { [weak self] token in
            await self?.sendApplePay(token) ?? false
        }
        switch outcome {
        case .notShown:
            problem = NSLocalizedString("Apple Pay couldn't open. You can pay with BLIK instead.", comment: "Purchase card")
        case .cancelled:
            // Closed without paying: the card is as it was and its approval still holds.
            break
        case .authorized:
            switch lastAnswer {
            case .some(.success(let purchase)): await handle(purchase)
            case .some(.failure(let error)): await recover(after: error)
            case .none:
                phase = .lost
                await settleOnce(.lost)
            }
        }
    }

    private func sendApplePay(_ token: ApplePayTokenData) async -> Bool {
        markStarted()
        phase = .paying(.applePay)
        do {
            let answer = try await client.pay(purchaseId: prepared.purchase.id, approvalId: prepared.approvalId, payment: .applePay(token))
            lastAnswer = .success(answer.purchase)
            return answer.purchase.status == .paid
        } catch {
            lastAnswer = .failure(error)
            return false
        }
    }

    func payWithBlik() async {
        guard phase == .ready, blikAvailable else { return }
        guard let code = BlikCode.normalize(blikCode) else {
            problem = NSLocalizedString("Type the 6-digit BLIK code from your bank app.", comment: "Purchase card")
            return
        }
        blikCode = ""
        problem = nil
        markStarted()
        phase = .paying(.blik)
        do {
            let answer = try await client.pay(purchaseId: prepared.purchase.id, approvalId: prepared.approvalId, payment: .blik(code: code))
            await handle(answer.purchase)
        } catch {
            await recover(after: error)
        }
    }

    /// The server's answer to a payment, a status check or a cancel.
    private func handle(_ purchase: PurchaseView) async {
        switch purchase.status {
        case .waitingForBank:
            phase = .waitingForBank(purchase)
            await waitForBank(purchase)
        case .paying, .outcomeUnknown:
            phase = .waitingForBank(purchase)
            await waitForBank(purchase)
        case .paid, .failed, .cancelled, .expired, .handedOff, .userReportedPaid, .awaitingTap:
            phase = .settled(purchase)
            await settleOnce(.purchase(purchase))
        }
    }

    /// Asks the server every few seconds while the bank app or Stripe hasn't answered, for at most
    /// two minutes. Stops when the user cancels (the phase changes). Never pays again.
    private func waitForBank(_ purchase: PurchaseView) async {
        var latest = purchase
        for delay in PurchasePolling.delays() {
            try? await Task.sleep(for: .seconds(delay))
            guard case .waitingForBank = phase else { return }
            guard let answer = try? await client.status(purchaseId: latest.id) else { continue }
            latest = answer.purchase
            guard case .waitingForBank = phase else { return }
            if !latest.status.needsStatusCheck { break }
            phase = .waitingForBank(latest)
        }
        phase = .settled(latest)
        await settleOnce(.purchase(latest))
    }

    /// A payment call that didn't come back with a purchase: ask once what the server knows. A
    /// refusal before paying (an expired card) has the server's own status; anything else is unsure.
    private func recover(after error: PaymentsError) async {
        if let answer = try? await client.status(purchaseId: prepared.purchase.id) {
            if answer.purchase.status == .awaitingTap {
                // Refused before anything was sent: nothing paid, the card stays.
                phase = .ready
                problem = error.userMessage
                return
            }
            await handle(answer.purchase)
            return
        }
        phase = .lost
        await settleOnce(.lost)
    }

    // MARK: The shop's own checkout

    func openCheckout() async {
        guard phase == .ready, isCheckout else { return }
        problem = nil
        markStarted()
        phase = .openingCheckout
        do {
            let answer = try await client.handoff(purchaseId: prepared.purchase.id, approvalId: prepared.approvalId)
            guard let url = CheckoutLink.validate(answer.checkoutUrl) else {
                phase = .settled(answer.purchase)
                await settleOnce(.notOpened(NSLocalizedString("The shop's address wasn't safe to open.", comment: "Purchase card")))
                return
            }
            phase = .settled(answer.purchase)
            handoffURL = url
            checkoutURL = url
            // The agent hears "opened" now; whether the user paid is theirs to say on the receipt.
            await settleOnce(.purchase(answer.purchase))
        } catch {
            phase = .settled(prepared.purchase)
            await settleOnce(.notOpened(error.userMessage))
        }
    }

    func checkoutClosed() {
        checkoutURL = nil
    }

    /// The same page again, from the receipt. Opening it pays nothing by itself.
    func reopenCheckout() {
        guard case .settled(let current) = phase, current.status == .handedOff else { return }
        checkoutURL = handoffURL
    }

    /// After the shop's page: the user's own answer, recorded on the server as theirs.
    func reportCheckout(paid: Bool) async {
        guard case .settled(let current) = phase, current.status == .handedOff else { return }
        isChecking = true
        defer { isChecking = false }
        if let answer = try? await client.report(purchaseId: current.id, paid: paid) {
            phase = .settled(answer.purchase)
        } else {
            problem = NSLocalizedString("Doddy's server couldn't be reached. Try again.", comment: "Purchase card")
        }
    }

    // MARK: Cancelling and checking

    /// "Don't pay" before paying, or "Cancel" while BLIK waits for the bank.
    func cancel() async {
        switch phase {
        case .ready:
            phase = .settled(prepared.purchase)
            await settleOnce(.declined)
            // The server's purchase would run out in five minutes anyway; this ends it now.
            let client = client, id = prepared.purchase.id
            Task { _ = try? await client.cancel(purchaseId: id) }
        case .waitingForBank(let purchase):
            isChecking = true
            defer { isChecking = false }
            guard let answer = try? await client.cancel(purchaseId: purchase.id) else {
                problem = NSLocalizedString("Couldn't cancel. Decline it in your bank app.", comment: "Purchase card")
                return
            }
            if answer.purchase.status == .waitingForBank {
                problem = NSLocalizedString("Couldn't cancel. Decline it in your bank app.", comment: "Purchase card")
                return
            }
            phase = .settled(answer.purchase)
            await settleOnce(.purchase(answer.purchase))
        default:
            break
        }
    }

    /// On a receipt that isn't sure yet: ask the server again. Updates the card only.
    func checkAgain() async {
        let id = prepared.purchase.id
        switch phase {
        case .settled(let current) where current.status.needsStatusCheck: break
        case .lost: break
        default: return
        }
        isChecking = true
        defer { isChecking = false }
        guard let answer = try? await client.status(purchaseId: id) else {
            problem = NSLocalizedString("Doddy's server couldn't be reached. Try again.", comment: "Purchase card")
            return
        }
        problem = nil
        phase = .settled(answer.purchase)
    }

    // MARK: Private

    private func markStarted() {
        guard !started else { return }
        started = true
        onStart()
    }

    private func settleOnce(_ settlement: Settlement) async {
        guard !replied else { return }
        replied = true
        await onSettle(settlement)
    }
}
