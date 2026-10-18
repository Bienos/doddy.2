import DoddyCore
import PassKit
import SwiftUI

// The only file that uses PassKit (ADR-530; scripts/check_forbidden_capabilities.sh). The Apple
// Pay sheet's encrypted token goes to Doddy's server untouched; the phone never sees the card.

/// Whether this build and this iPhone can show the Apple Pay sheet. Apple Pay needs a merchant
/// ID in the build (`DODDY_APPLE_PAY_MERCHANT_ID`, project.yml) with the Apple Pay entitlement,
/// which a paid Apple developer team must turn on; without it the card offers BLIK only.
enum ApplePaySupport {
    static let networks: [PKPaymentNetwork] = [.visa, .masterCard, .maestro]

    static var merchantIdentifier: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "DoddyApplePayMerchantID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // An unexpanded or empty build setting means Apple Pay isn't set up in this build.
        guard !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    @MainActor static var isAvailable: Bool {
        merchantIdentifier != nil && PKPaymentAuthorizationController.canMakePayments()
    }
}

/// Apple's own "Buy with Apple Pay" button.
struct ApplePayButton: View {
    let action: () -> Void

    var body: some View {
        PayWithApplePayButton(.buy, action: action)
            .payWithApplePayButtonStyle(.automatic)
            .frame(height: 48)
            .accessibilityIdentifier("purchase.applePay")
    }
}

enum ApplePayOutcome: Equatable, Sendable {
    /// The sheet couldn't be shown (not set up, or another sheet is open). Nothing was paid.
    case notShown
    /// The user closed the sheet without paying. Nothing was paid.
    case cancelled
    /// The user paid with Face ID and the token went to Doddy's server; the server's answer decides.
    case authorized
}

/// Shows the Apple Pay sheet once and hands the token to `authorize`, which returns true only when
/// Doddy's server says Stripe confirmed the payment; the sheet then shows a tick, otherwise a cross.
@MainActor
final class ApplePayPresenter: NSObject, PKPaymentAuthorizationControllerDelegate {
    typealias Authorize = @MainActor @Sendable (ApplePayTokenData) async -> Bool

    private var controller: PKPaymentAuthorizationController?
    private var authorize: Authorize?
    private var didAuthorize = false
    private var finished: CheckedContinuation<ApplePayOutcome, Never>?

    func present(_ sheet: ApplePaySheet, authorize: @escaping Authorize) async -> ApplePayOutcome {
        guard controller == nil, let merchant = ApplePaySupport.merchantIdentifier else { return .notShown }
        let request = PKPaymentRequest()
        request.merchantIdentifier = merchant
        request.countryCode = sheet.countryCode
        request.currencyCode = sheet.currency
        request.supportedNetworks = ApplePaySupport.networks
        request.merchantCapabilities = .threeDSecure
        request.paymentSummaryItems = sheet.lines.map {
            PKPaymentSummaryItem(label: $0.label, amount: NSDecimalNumber(decimal: $0.amount), type: .final)
        }
        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        controller.delegate = self
        self.controller = controller
        self.authorize = authorize
        didAuthorize = false
        let presented: Bool = await withCheckedContinuation { continuation in
            controller.present { continuation.resume(returning: $0) }
        }
        guard presented else {
            self.controller = nil
            self.authorize = nil
            return .notShown
        }
        return await withCheckedContinuation { finished = $0 }
    }

    // MARK: PKPaymentAuthorizationControllerDelegate

    /// The async form of PassKit's delegate method (Swift's import of its `handler:` block), so
    /// no non-Sendable completion block has to cross to the main actor.
    nonisolated func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment
    ) async -> PKPaymentAuthorizationResult {
        // Read the token here into plain values; only those cross to the main actor.
        let transaction = payment.token.transactionIdentifier
        let token = ApplePayTokenData(
            paymentData: String(data: payment.token.paymentData, encoding: .utf8) ?? "",
            network: payment.token.paymentMethod.network?.rawValue,
            instrumentName: payment.token.paymentMethod.displayName,
            transactionId: transaction.isEmpty ? nil : transaction)
        let paid = await send(token)
        return PKPaymentAuthorizationResult(status: paid ? .success : .failure, errors: nil)
    }

    nonisolated func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        Task { @MainActor in self.finish() }
    }

    private func send(_ token: ApplePayTokenData) async -> Bool {
        didAuthorize = true
        guard let authorize else { return false }
        return await authorize(token)
    }

    private func finish() {
        controller?.dismiss(completion: nil)
        controller = nil
        authorize = nil
        let outcome: ApplePayOutcome = didAuthorize ? .authorized : .cancelled
        finished?.resume(returning: outcome)
        finished = nil
    }
}
