import Foundation

// prepare_purchase (ADR-490): the agent's arguments, checked before anything goes to the server.
//
//   kind          "native" (Apple Pay or BLIK inside Doddy, test mode in this milestone) or
//                 "checkout" (the shop's own page, opened inside Doddy)
//   merchant      the shop or service, as the user named it
//   description   what is bought ("2 tickets, Friday 19:30")
//   amount_pln    the price in złoty the user heard, e.g. 56 or 56.5
//   currency      optional; only "PLN"
//   checkout_url  checkout only: the shop's https page

extension VoiceToolRequest {
    static func parsePurchase(_ args: Arguments, name: String) -> VoiceToolRequest {
        guard let rawKind = args.text("kind"), let kind = PurchaseKind(rawValue: rawKind.lowercased()) else {
            return .invalid(name: name, reason: "kind must be native or checkout")
        }
        guard let merchant = args.text("merchant")?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .invalid(name: name, reason: "missing merchant")
        }
        guard merchant.count <= PurchaseLimits.merchantNameLength else {
            return .invalid(name: name, reason: "merchant is longer than \(PurchaseLimits.merchantNameLength) characters")
        }
        guard let description = args.text("description")?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .invalid(name: name, reason: "missing description")
        }
        guard description.count <= PurchaseLimits.descriptionLength else {
            return .invalid(name: name, reason: "description is longer than \(PurchaseLimits.descriptionLength) characters")
        }
        if let currency = args.text("currency"), currency.uppercased() != PurchaseLimits.currency {
            return .invalid(name: name, reason: "only PLN is supported")
        }
        guard let major = args.number("amount_pln") else { return .invalid(name: name, reason: "missing amount_pln") }
        guard let amount = PurchaseMoney.minor(fromMajor: major) else {
            return .invalid(name: name, reason: "amount_pln must be a positive price in złoty with at most two decimals")
        }
        switch kind {
        case .native:
            if args.has("checkout_url") { return .invalid(name: name, reason: "checkout_url is only for kind checkout") }
            guard amount >= PurchaseLimits.nativeMinimumMinor else {
                return .invalid(name: name, reason: "amount_pln must be at least 2 złoty for a payment inside Doddy")
            }
            return .preparePurchase(PurchaseDraft(kind: .native, merchantName: merchant, description: description, amountMinor: amount, checkoutURL: nil))
        case .checkout:
            guard let raw = args.text("checkout_url") else { return .invalid(name: name, reason: "missing checkout_url") }
            guard let url = CheckoutLink.validate(raw) else {
                return .invalid(name: name, reason: "checkout_url must be the shop's https page")
            }
            return .preparePurchase(PurchaseDraft(kind: .checkout, merchantName: merchant, description: description, amountMinor: amount, checkoutURL: url))
        }
    }
}
