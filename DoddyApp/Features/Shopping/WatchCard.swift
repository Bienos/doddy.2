import DoddyCore
import SwiftUI

// "Pilnuj ceny" on a pick (docs/implementation/SHOPPING_WATCH.md section 4). One sheet in two steps. First the
// user's price (suggested: 5 percent below, rounded down to whole złoty; they can type another), which makes
// Doddy's server read the shop's own page once and hold a draft. Then the card shows what the server read
// and the exact promise, and only the user's tap on "Tak, pilnuj" approves that draft by its digest. Nothing
// is watched before that tap, and the card says "watching" only when the server said so. Doddy only tells
// the user; nothing is bought. The sentences come from DoddyCore (`WatchWords`), where tests hold them.

/// The button under a pick. Only for an offer whose price was read from the shop's own page. Prominent (orange, in
/// "Compare"): the way to hunt for a deal on that pick (owner, 13 Nov 2026: "ustawienia cen, szukanie okazji").
struct WatchPriceButton: View {
    let offer: ShoppingOffer
    let prominent: Bool
    @State private var showCard = false

    init(offer: ShoppingOffer, prominent: Bool = false) {
        self.offer = offer
        self.prominent = prominent
    }

    var body: some View {
        Group {
            if prominent {
                Button {
                    showCard = true
                } label: {
                    Label("Watch the price", systemImage: "bell.badge")
                }
                .buttonStyle(DoddyAccentButtonStyle())
            } else {
                Button {
                    showCard = true
                } label: {
                    Label("Watch the price", systemImage: "bell.badge")
                        .font(.body.weight(.semibold))
                }
            }
        }
        .accessibilityIdentifier("watch.start")
        .accessibilityHint("Give the price you'd pay; Doddy tells you once when the shop's page shows it or less.")
        .sheet(isPresented: $showCard) { WatchCard(offer: offer) }
    }
}

/// What a watch card is about: a pick's offer, whose price Doddy read, or a page the person pasted
/// ("Sprawdź to", SHOPPING.md "Check this"), whose price nobody has read yet. The card's second step shows
/// what the server read either way.
enum WatchSubject {
    case offer(ShoppingOffer)
    case page(SharedShopPage)

    var title: String {
        switch self {
        case .offer(let offer): offer.title
        case .page(let page): page.title
        }
    }

    var shop: String {
        switch self {
        case .offer(let offer): offer.shop
        case .page(let page): page.shop
        }
    }

    var url: String {
        switch self {
        case .offer(let offer): offer.url
        case .page(let page): page.url
        }
    }

    var currency: String {
        switch self {
        case .offer(let offer): offer.price.currency
        case .page: "PLN"
        }
    }

    /// The price Doddy read when it found the offer. Nil for a pasted page.
    var knownPrice: Money? {
        switch self {
        case .offer(let offer): offer.price
        case .page: nil
        }
    }

    func draft(thresholdMinor: Int, language: String) -> PriceWatchDraft {
        switch self {
        case .offer(let offer): PriceWatchDraft(watching: offer, thresholdMinor: thresholdMinor, language: language)
        case .page(let page): page.watchDraft(thresholdMinor: thresholdMinor, language: language)
        }
    }
}

struct WatchCard: View {
    let subject: WatchSubject
    @Environment(\.dismiss) private var dismiss
    private let model = WatchModel.shared
    private let language = NotificationLanguage.current
    @State private var priceText: String

    init(offer: ShoppingOffer) {
        self.subject = .offer(offer)
        let suggested = PriceWatchDraft.suggestedThresholdMinor(forPriceMinor: offer.price.minor)
        _priceText = State(initialValue: suggested.map { PriceWatchDraft.typedText(forMinor: $0, NotificationLanguage.current) } ?? "")
    }

    /// A page the person pasted: no price is known, so nothing is suggested.
    init(page: SharedShopPage) {
        self.subject = .page(page)
        _priceText = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                switch model.phase {
                case .idle, .reading:
                    entry
                case .preview(let draft, let preview):
                    confirmation(draft, preview, starting: false)
                case .starting(let draft, let preview):
                    confirmation(draft, preview, starting: true)
                case .started(let draft):
                    started(draft)
                case .unsure:
                    unsure
                }
                if let problem = model.problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
                            .accessibilityIdentifier("watch.problem")
                    }
                }
            }
            .navigationTitle("Watch this price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(model.phase.isInFlight)
                }
            }
            .interactiveDismissDisabled(model.phase.isInFlight)
            .onAppear { model.beginCard() }
            .onDisappear { Task { await model.cardClosed() } }
        }
    }

    // MARK: Step one: the user's price

    @ViewBuilder
    private var entry: some View {
        Section {
            productLines(title: subject.title, shop: subject.shop, url: subject.url)
            if let known = subject.knownPrice {
                LabeledContent("Price when Doddy found it", value: known.text(language))
            }
        } header: {
            Text("What will be watched")
        }
        Section {
            HStack {
                TextField("Your price", text: $priceText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("watch.price")
                Text(verbatim: subject.currency).foregroundStyle(Theme.secondaryText)
            }
            if let typed = typedMinor {
                if let known = subject.knownPrice, typed >= known.minor {
                    Text(String(format: NSLocalizedString("The price in the result is %@. Type something lower.", comment: ""),
                                known.text(language)))
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            } else if !priceText.isEmpty {
                Text(WatchWords.notAPrice(language)).font(.footnote).foregroundStyle(Theme.error)
            }
        } header: {
            Text("Your price")
        } footer: {
            if subject.knownPrice != nil {
                Text("I'll tell you when the price I read is at or below this. Suggested: 5 percent below the price, rounded down to whole złoty. Type another if you like.")
            } else {
                Text("I'll tell you when the price I read is at or below this. Not sure what to type? Type a price you'd be happy to pay: the next step shows what the page costs now, and you can still say no.")
            }
        }
        Section {
            promise
        }
        Section {
            Button {
                Task { await check() }
            } label: {
                Label("Check the page", systemImage: "magnifyingglass")
            }
            .disabled(typedMinor == nil || model.phase == .reading)
            .accessibilityIdentifier("watch.check")
            if model.phase == .reading { ProgressView("Reading the page…") }
            Button("No", role: .cancel) { dismiss() }
                .disabled(model.phase == .reading)
                .accessibilityIdentifier("watch.no")
        }
    }

    // MARK: Step two: the server's draft and the user's yes

    @ViewBuilder
    private func confirmation(_ draft: PriceWatchDraft, _ preview: WatchPreview, starting: Bool) -> some View {
        Section {
            productLines(title: draft.title, shop: draft.shop, url: draft.url)
        } header: {
            Text("What will be watched")
        }
        Section {
            LabeledContent("Price on the page now", value: preview.current.text(language))
            LabeledContent("Your price", value: draft.threshold.text(language))
            Text(String(format: NSLocalizedString("Page read %@.", comment: ""), DateText.full(preview.checkedAt)))
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        Section {
            promise
        }
        Section {
            Button("Yes, watch") { Task { await model.approve() } }
                .disabled(starting)
                .accessibilityIdentifier("watch.confirm")
            if starting { ProgressView("Starting the watch…") }
            Button("No", role: .cancel) {
                Task {
                    await model.decline()
                    dismiss()
                }
            }
            .disabled(starting)
            .accessibilityIdentifier("watch.decline")
        }
    }

    @ViewBuilder
    private func started(_ draft: PriceWatchDraft) -> some View {
        Section {
            Label(WatchWords.started(threshold: draft.threshold, language), systemImage: "checkmark.circle")
                .foregroundStyle(Theme.confirmed)
                .accessibilityIdentifier("watch.started")
            Button("Done") { dismiss() }
                .accessibilityIdentifier("watch.done")
        }
    }

    @ViewBuilder
    private var unsure: some View {
        Section {
            Label(WatchWords.notSure(language), systemImage: "questionmark.circle").foregroundStyle(Theme.ink)
                .accessibilityIdentifier("watch.unsure")
            Button("Done") { dismiss() }
                .accessibilityIdentifier("watch.done")
        }
    }

    // MARK: Pieces

    /// The commitment in words, and what goes to Doddy's server.
    @ViewBuilder
    private var promise: some View {
        Text(WatchWords.promise(language)).foregroundStyle(Theme.ink)
            .accessibilityIdentifier("watch.promise")
        Text("Doddy's server gets the shop's name and page address, the title and your price, and reads that page for you. You can stop or delete the watch any time.")
            .font(.footnote).foregroundStyle(Theme.secondaryText)
    }

    private func productLines(title: String, shop: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title).font(.headline).foregroundStyle(Theme.ink)
            Text(verbatim: shop).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            Text("Page address").font(.caption).foregroundStyle(Theme.secondaryText)
            Text(verbatim: url).font(.footnote).foregroundStyle(Theme.ink).textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    /// The price the user typed, in minor units; nil when it isn't a price.
    private var typedMinor: Int? {
        PriceWatchDraft.parseThresholdMinor(priceText, currency: subject.currency)
    }

    private func check() async {
        guard let minor = typedMinor else { return }
        await model.start(subject.draft(thresholdMinor: minor, language: language == .polish ? "pl" : "en"))
    }
}
