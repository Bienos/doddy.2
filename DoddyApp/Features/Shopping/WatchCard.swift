import DoddyCore
import SwiftUI

// "Pilnuj ceny" on a pick (docs/implementation/SHOPPING_WATCH.md section 4). One sheet in two steps. First the
// user's price (suggested: 5 percent below, rounded down to whole złoty; they can type another), which makes
// Doddy's server read the shop's own page once and hold a draft. Then the card shows what the server read
// and the exact promise, and only the user's tap on "Tak, pilnuj" approves that draft by its digest. Nothing
// is watched before that tap, and the card says "watching" only when the server said so. Doddy only tells
// the user; nothing is bought. The sentences come from DoddyCore (`WatchWords`), where tests hold them.

/// The button under a pick. Only for an offer whose price was read from the shop's own page.
struct WatchPriceButton: View {
    let offer: ShoppingOffer
    @State private var showCard = false

    var body: some View {
        Button {
            showCard = true
        } label: {
            Label("Watch the price", systemImage: "bell")
        }
        .accessibilityIdentifier("watch.start")
        .sheet(isPresented: $showCard) { WatchCard(offer: offer) }
    }
}

struct WatchCard: View {
    let offer: ShoppingOffer
    @Environment(\.dismiss) private var dismiss
    private let model = WatchModel.shared
    private let language = NotificationLanguage.current
    @State private var priceText: String

    init(offer: ShoppingOffer) {
        self.offer = offer
        let suggested = PriceWatchDraft.suggestedThresholdMinor(forPriceMinor: offer.price.minor)
        _priceText = State(initialValue: suggested.map { PriceWatchDraft.typedText(forMinor: $0, NotificationLanguage.current) } ?? "")
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
            productLines(title: offer.title, shop: offer.shop, url: offer.url)
            LabeledContent("Price when Doddy found it", value: offer.price.text(language))
        } header: {
            Text("What will be watched")
        }
        Section {
            HStack {
                TextField("Your price", text: $priceText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("watch.price")
                Text(verbatim: offer.price.currency).foregroundStyle(Theme.secondaryText)
            }
            if let typed = typedMinor {
                if typed >= offer.price.minor {
                    Text(String(format: NSLocalizedString("The price in the result is %@. Type something lower.", comment: ""),
                                offer.price.text(language)))
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            } else if !priceText.isEmpty {
                Text(WatchWords.notAPrice(language)).font(.footnote).foregroundStyle(Theme.error)
            }
        } header: {
            Text("Your price")
        } footer: {
            Text("I'll tell you when the price I read is at or below this. Suggested: 5 percent below the price, rounded down to whole złoty. Type another if you like.")
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
        PriceWatchDraft.parseThresholdMinor(priceText, currency: offer.price.currency)
    }

    private func check() async {
        guard let minor = typedMinor else { return }
        await model.start(PriceWatchDraft(watching: offer, thresholdMinor: minor, language: language == .polish ? "pl" : "en"))
    }
}
