import DoddyCore
import Foundation
import SwiftUI

/// Screen-only UI for Shopify voice results. Prices and seller names come exclusively
/// from Shop MCP through Doddy's authenticated backend, never from the model.
enum ShopifyVoiceMoney {
    static func format(_ minor: Int, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let digits = max(0, min(3, formatter.maximumFractionDigits))
        let value = Double(minor) / pow(10, Double(digits))
        return formatter.string(from: NSNumber(value: value)) ?? "\(minor) \(currency) (minor units)"
    }
}

struct ShopifyVoiceResultsCard: View {
    let offers: [VoiceSessionController.ShopifyVoiceOffer]
    private var pl: Bool { NotificationLanguage.current == .polish }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(pl ? "Oferty Shopify na żywo" : "Live Shopify offers", systemImage: "bag")
                .font(.headline)
            ForEach(offers) { offer in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "\(offer.index). \(offer.productTitle)")
                        .font(.body.weight(.semibold))
                    if !offer.variant.title.isEmpty {
                        Text(verbatim: offer.variant.title)
                            .font(.subheadline)
                    }
                    HStack {
                        Text(verbatim: offer.variant.merchant)
                            .foregroundStyle(Theme.secondaryText)
                        Spacer(minLength: 10)
                        Text(verbatim: ShopifyVoiceMoney.format(offer.variant.priceMinor, currency: offer.variant.currency))
                            .font(.subheadline.monospacedDigit())
                    }
                    if let raw = offer.variant.productURL, let url = URL(string: raw), url.scheme == "https" {
                        Link(destination: url) {
                            Label(pl ? "Zobacz w sklepie" : "View at merchant", systemImage: "arrow.up.right")
                                .font(.footnote)
                        }
                    }
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("voice.shopify.offer.\(offer.index)")
            }
            Text(pl
                 ? "Ceny katalogowe przed dostawą i podatkami. Powiedz Doddy’emu, który numer wybrać, żeby przygotować koszyk."
                 : "Catalog prices before shipping and taxes. Tell Doddy which number to prepare as a checkout.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("voice.shopify.results")
    }
}

/// A checkout URL is a sensitive merchant-issued bearer link: show it ONLY inside the user's
/// iPhone screen, never in a voice tool result, transcript or local activity log.
struct ShopifyVoiceCheckoutCard: View {
    let confirmation: VoiceSessionController.ShopifyVoiceCheckout
    private var pl: Bool { NotificationLanguage.current == .polish }

    var body: some View {
        let info = confirmation.merchant
        VStack(alignment: .leading, spacing: 12) {
            Label(pl ? "Koszyk u sprzedawcy" : "Merchant checkout prepared", systemImage: "cart")
                .font(.headline)
            Text(verbatim: confirmation.offer.productTitle)
                .font(.body.weight(.semibold))
            Text(verbatim: "\(info.seller) • \(confirmation.quantity) ×")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)

            if let currency = info.currency {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(info.totals.enumerated()), id: \.offset) { _, total in
                        HStack {
                            Text(verbatim: total.displayText)
                            Spacer(minLength: 8)
                            Text(verbatim: ShopifyVoiceMoney.format(total.amount, currency: currency))
                                .monospacedDigit()
                        }
                        .font(total.type == "total" ? .subheadline.weight(.semibold) : .footnote)
                    }
                }
            }

            ForEach(Array(info.messages.enumerated()), id: \.offset) { _, notice in
                Text(verbatim: notice)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }

            if !info.links.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(pl ? "Warunki sprzedawcy" : "Merchant terms")
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(info.links.enumerated()), id: \.offset) { _, policy in
                        if let url = URL(string: policy.url), url.scheme == "https" {
                            Link(destination: url) {
                                Label(policy.title, systemImage: "arrow.up.right")
                                    .font(.footnote)
                            }
                        }
                    }
                }
            }

            if let url = URL(string: info.checkoutURL), url.scheme == "https" {
                Link(destination: url) {
                    Label(pl ? "Dokończ zakup u sprzedawcy" : "Continue at merchant checkout",
                          systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("voice.shopify.merchantCheckout")
            }

            Text(pl
                 ? "Doddy utworzył koszyk, ale nie złożył zamówienia i nie pobrał pieniędzy. Sprawdź ostateczny koszt, dostawę i warunki przed płatnością u sprzedawcy."
                 : "Doddy prepared a cart but placed no order and charged no money. Review the final total, delivery and terms at the merchant before paying.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("voice.shopify.checkout")
    }
}
