import DoddyCore
import SwiftUI

// A shopping task's result (docs/implementation/SHOPPING.md 3): the three picks with the price, shop,
// where the price came from and when; Doddy's reasons; what to watch out for, what isn't known and
// what was left out; "Buy at …", which opens the shop's own page in Safari (the shop takes the
// payment there; Doddy records only that the page was opened, never that anything was bought; no web
// view inside the app, scripts/check_forbidden_capabilities.sh); and the PDF report drawn on this iPhone. Every price and time here is the one the server's code registered.

struct ShoppingResultSections: View {
    let errand: StoredErrand
    let result: ErrandResult
    let shopping: ShoppingResult

    @Environment(\.openURL) private var openURL
    @State private var reportURL: URL?
    @State private var reportProblem: String?
    private let language = NotificationLanguage.current

    var body: some View {
        Section {
            Text(result.answer).font(.body.weight(.semibold)).foregroundStyle(Theme.ink).textSelection(.enabled)
            if !shopping.priorities.isEmpty {
                Text(String(format: NSLocalizedString("Your order: %@", comment: "priorities"),
                            shopping.priorities.joined(separator: ", ")))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if let stats = shopping.stats {
                Text(String(format: NSLocalizedString("%lld offers looked at, in %lld shops.", comment: ""), stats.offersSeen, stats.shops))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if let budget = shopping.budget {
                Text(String(format: NSLocalizedString("Your budget: %@", comment: ""), budget.text(language)))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityIdentifier("shopping.summary")

        ForEach(Array(shopping.picksInDisplayOrder.enumerated()), id: \.offset) { _, row in
            Section(row.pick.role.label(language)) {
                PickRow(pick: row.pick, offer: row.offer, language: language)
                if let url = ShopPage.url(row.offer.buyUrl ?? row.offer.url) {
                    Button {
                        let page = ShopPage(url: url, offer: row.offer)
                        openURL(url) { opened in if opened { ShopPage.record(page) } }
                    } label: {
                        Label(String(format: NSLocalizedString("Buy at %@", comment: "opens the shop's page"), row.offer.shop),
                              systemImage: "bag")
                    }
                    .accessibilityIdentifier("shopping.buy")
                    // A partner link is said right under the button, before it is tapped (ADR-612).
                    if row.offer.isAffiliate {
                        Text("Partner link: the page goes through an affiliate network on its way to the shop, and Doddy may earn a commission if you buy. Prices and the order of the picks don't change.")
                            .font(.footnote).foregroundStyle(Theme.secondaryText)
                            .accessibilityIdentifier("shopping.partnerNote")
                    }
                }
            }
        }

        lines("How I chose", shopping.howChosen, symbol: "list.number")
        lines("Watch out for", shopping.watchOuts, symbol: "exclamationmark.circle")
        lines("What I don't know", shopping.unknowns, symbol: "questionmark.circle")
        lines("Left out, and why", shopping.rejected, symbol: "xmark.circle")

        Section {
            if let reportURL {
                ShareLink(item: reportURL) {
                    Label("Share the PDF report", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("shopping.shareReport")
            } else {
                Button {
                    makeReport()
                } label: {
                    Label("Make a PDF report", systemImage: "doc.richtext")
                }
                .accessibilityIdentifier("shopping.makeReport")
            }
            if let reportProblem {
                Label(reportProblem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
            }
            Text("The report is made on this iPhone from this result. Nothing is sent to make it.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            Text("Prices can change after the time they were checked. Buying happens on the shop's page: you pay the shop with Apple Pay, BLIK or a card, and Doddy doesn't see the payment.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder
    private func lines(_ title: LocalizedStringKey, _ items: [String], symbol: String) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, line in
                    Label(line, systemImage: symbol).foregroundStyle(Theme.ink)
                }
            }
        }
    }

    private func makeReport() {
        reportProblem = nil
        let report = ShoppingReport(title: errand.title, words: errand.draft.words, result: result, shopping: shopping,
                                    language: language, madeAt: Date())
        do {
            reportURL = try report.temporaryFile()
        } catch {
            reportProblem = NSLocalizedString("The report couldn't be made on this iPhone. Try again.", comment: "")
        }
    }
}

private struct PickRow: View {
    let pick: ShoppingPick
    let offer: ShoppingOffer
    let language: NotificationLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(offer.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            HStack(alignment: .firstTextBaseline) {
                Text(offer.price.text(language)).font(.title2.weight(.heavy)).foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("shopping.price")
                Spacer(minLength: 8)
                Text(offer.shop).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            Text(verbatim: "\(offer.evidence.label(language)) \(offer.seenAt.formatted(date: .omitted, time: .shortened))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(offer.evidence == .shopPage ? Theme.confirmed : Theme.secondaryText)
            if let delivery = offer.delivery { Text(delivery).font(.footnote).foregroundStyle(Theme.ink) }
            Text(pick.why).foregroundStyle(Theme.ink)
            if let tradeoff = pick.tradeoff { Text(tradeoff).font(.footnote).foregroundStyle(Theme.secondaryText) }
            if let notes = offer.notes { Text(notes).font(.footnote).foregroundStyle(Theme.secondaryText) }
            if let over = pick.overBudget {
                Text(String(format: NSLocalizedString("%@ over your budget", comment: ""), over.text(language)))
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.error)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A shop's page opened from a pick, in Safari. Only https and http addresses are opened.
struct ShopPage: Identifiable {
    let id = UUID()
    let url: URL
    let offer: ShoppingOffer

    static func url(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https" || url.scheme == "http", url.host() != nil else { return nil }
        return url
    }

    /// One line in What Doddy did: the shop's page was opened. Doddy can't see what happens there, so
    /// it is never recorded as bought (constitution: done only on a provider's confirmation).
    @MainActor
    static func record(_ page: ShopPage) {
        ActivityLogStore.shared.append(ActivityEntry(
            at: Date(), app: .web,
            title: String(format: NSLocalizedString("Opened %@'s page", comment: "activity log"), page.offer.shop),
            detail: page.offer.title, outcome: .opened))
    }
}
