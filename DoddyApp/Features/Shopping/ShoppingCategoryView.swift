import DoddyCore
import SwiftUI

// One kind of shop (owner, 13 Nov 2026), pushed from the Shopping screen's tiles (`ShopKindsSection`). What it
// holds, all from paths that already exist on the Shopping screen:
//   - a field for this kind: groceries go to "Cheapest this week" (the leaflets, at once, as the one field sends
//     them), every other kind to "Find me this" behind the same yes card (DOD-07), with the kind added as one line
//     under the person's words (`ShopCategoryRequest`, so the card shows it and the digest covers it);
//   - for groceries, the way into this week's deals;
//   - the shops by name with what Doddy does at each (`ShopDirectory`: the leaflet chains and Shopify's catalogue;
//     nothing Doddy can't reach);
//   - Shopify's search for every kind but groceries.
// Nothing is bought here. Every price shown elsewhere is one the server read on a shop's page or leaflet.

struct ShoppingCategoryView: View {
    let category: ShopCategory
    private let model = ErrandsModel.shared
    @State private var words = ""
    @State private var asking: TypedAsk?
    @State private var note: HandOverNote?
    @State private var leafletCheck: CategoryLeafletCheck?
    @State private var showDeals = false
    @State private var showShopify = false
    @FocusState private var typing: Bool

    private var scope: ReleaseScope { ReleaseScopeStore.current }
    private var shops: [ShopListing] { ShopDirectory.shops(in: category, shopify: scope.shows(.shopifyShopping)) }
    private var isGroceries: Bool { category == .groceries }
    private var trimmed: String { words.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DoddyHero(title: category.title, subtitle: subtitle)
                if !model.isServerConfigured {
                    Label("Doddy's server isn't set up in this build, so tasks can't run yet.", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.error)
                }
                if isGroceries ? scope.shows(.deals) : scope.shows(.errands) {
                    findCard
                }
                if isGroceries && scope.shows(.deals) {
                    dealsRow
                }
                shopsSection
                if !isGroceries && scope.shows(.shopifyShopping) {
                    shopifyRow
                }
                DoddyFootnote(text: NSLocalizedString("Your words and this kind go to Doddy's server and to Anthropic, whose Claude does the research, only after you say yes. Search phrases go to Google Shopping through Serper, and Doddy's server opens shops' pages.", comment: ""),
                              systemImage: "lock")
            }
            .padding(16)
            .readableColumn()
        }
        .scrollDismissesKeyboard(.interactively)
        .doddyScreen()
        .navigationTitle(Text(verbatim: category.title))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $asking) { ask in
            TypedHandOverSheet(draft: ask.draft) { outcome in finished(outcome) }
        }
        .sheet(item: $leafletCheck) { check in
            DealsView(start: check.items)
        }
        .sheet(isPresented: $showDeals) { DealsView() }
        .sheet(isPresented: $showShopify) { ShopifyLiveShoppingView() }
        .accessibilityIdentifier("shopping.kind.page")
    }

    private var subtitle: String {
        isGroceries
            ? NSLocalizedString("This week's leaflets, the cheapest shop for each thing on your list, and anything else found for you.", comment: "")
            : NSLocalizedString("Doddy looks across shops in Poland for up to three picks, each with a price read on the shop's own page, and can watch a price for you.", comment: "")
    }

    // MARK: The field for this kind

    private var findCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("What do you need?", text: $words, prompt: Text(verbatim: category.example), axis: .vertical)
                .lineLimit(2...5)
                .focused($typing)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.canvas))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
                .onChange(of: words) { _, new in if !new.isEmpty { note = nil } }
                .accessibilityIdentifier("shopping.kind.words")
            Button {
                typing = false
                go()
            } label: {
                if isGroceries {
                    Label("Check prices", systemImage: "tag")
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Find it", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(DoddyInkButtonStyle())
            .disabled(trimmed.isEmpty || (!isGroceries && !model.isServerConfigured) || model.isHandingOver)
            .accessibilityIdentifier("shopping.kind.go")
            if let note {
                Label(note.text, systemImage: note.kind.symbol)
                    .font(.subheadline)
                    .foregroundStyle(note.kind.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(isGroceries
                 ? NSLocalizedString("Leaflet prices come back in seconds, and nothing is handed over for them.", comment: "")
                 : NSLocalizedString("Nothing is sent until you say yes on the next card. The kind goes along with your words.", comment: ""))
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .doddyCard()
    }

    /// Groceries open this week's leaflets with the items; every other kind asks the yes card first.
    private func go() {
        guard !trimmed.isEmpty else { return }
        if isGroceries {
            let items = ShoppingRoute.route(trimmed, to: .leaflets).leaflets
            guard !items.isEmpty else { return }
            note = nil
            leafletCheck = CategoryLeafletCheck(items: items)
        } else {
            ask(ShopCategoryRequest.words(trimmed, category: category, language: requestLanguage))
        }
    }

    private var requestLanguage: String {
        ErrandDraft.typedLanguage(Bundle.main.preferredLocalizations.first ?? "en")
    }

    /// The same checks as the Shopping screen's field, here first (the server checks again). Nothing is sent here.
    private func ask(_ thing: String) {
        let draft = ErrandDraft.typedShopping(thing, priorities: [], language: requestLanguage)
        if let issue = draft.validationIssues().first {
            note = HandOverNote(text: ErrandText.issue(issue), kind: .problem)
            return
        }
        if UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) {
            note = HandOverNote(text: ErrandText.paused, kind: .problem)
            return
        }
        note = nil
        asking = TypedAsk(draft: draft)
    }

    /// "Looking" only when the server said it has the task.
    private func finished(_ outcome: ErrandsModel.HandOverOutcome) {
        switch outcome {
        case .started:
            words = ""
            note = HandOverNote(text: NSLocalizedString("Doddy is looking. The picks will wait in Shopping, in Tasks and in Messages.", comment: ""), kind: .confirmed)
        case .maybeStarted:
            note = HandOverNote(text: NSLocalizedString("Doddy couldn't confirm it started. It may be running: check Shopping or Tasks before you hand it over again.", comment: ""), kind: .unsure)
        case .notStarted(let error):
            note = HandOverNote(text: ErrandText.notStarted(error), kind: .problem)
        case .invalid(let issue):
            note = HandOverNote(text: ErrandText.issue(issue), kind: .problem)
        case .paused:
            note = HandOverNote(text: ErrandText.paused, kind: .problem)
        case .alreadySending:
            note = nil
        }
    }

    // MARK: This week's deals (groceries)

    private var dealsRow: some View {
        Button { showDeals = true } label: {
            HStack(spacing: 12) {
                DoddySymbolTile(systemImage: "newspaper")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cheapest this week").font(.headline).foregroundStyle(Theme.ink)
                    Text("Groceries and everyday things: where each is cheapest in this week's leaflets.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .doddyCard(padding: 14)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(DoddyTapStyle())
        .accessibilityIdentifier("shopping.kind.deals")
    }

    // MARK: The shops by name

    private var shopsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DoddySectionTitle(title: "Shops by name")
            if shops.isEmpty || shops == [ShopListing.shopify] {
                Text("No shop of this kind is connected by name yet. Doddy looks across shops in Poland and reads their own pages.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !shops.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .top)], alignment: .leading, spacing: 8) {
                    ForEach(shops) { shop in
                        shopChip(shop)
                    }
                }
                .accessibilityIdentifier("shopping.kind.shops")
            }
        }
    }

    /// A shop's name, no logo, with what Doddy does there underneath.
    private func shopChip(_ shop: ShopListing) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: shop.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(verbatim: shop.capabilities.map(\.words).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Shopify

    private var shopifyRow: some View {
        Button { showShopify = true } label: {
            HStack(spacing: 12) {
                DoddySymbolTile(systemImage: "bag")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shopify shops").font(.headline).foregroundStyle(Theme.ink)
                    Text("Search products in Shopify shops and prepare a cart at the shop. Doddy takes no payment.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .doddyCard(padding: 14)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(DoddyTapStyle())
        .accessibilityIdentifier("shopping.kind.shopify")
    }
}

/// The leaflet check a groceries page asked for: "Cheapest this week" opens with these items and checks them.
private struct CategoryLeafletCheck: Identifiable {
    let id = UUID()
    let items: [String]
}
