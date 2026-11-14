import DoddyCore
import SwiftUI

// Shopping in one place (owner, 11 Nov 2026: "skończ co już mamy"; docs/strategy/SKLEP_PROPOZYCJA_2026-11.md).
// Nothing here is a new capability: it gathers what already existed on three screens.
//   - "Find me this" (docs/implementation/SHOPPING.md 1), until now only by voice: the words and what matters
//     most are typed here, and the same yes card as a typed task shows exactly what goes to Doddy's server.
//   - The shopping tasks already handed over, with their state; a tap opens the result and its picks.
//   - Watched prices (SHOPPING_WATCH.md), the same section as on Tasks.
//   - "Cheapest this week" (the leaflets), opened from here as from Home's menu.
// Every price shown is one the server confirmed on a shop's own page; this screen writes none itself.
// Since 13 Nov 2026 (owner's review, docs/strategy/PRZEGLAD_APLIKACJI_2026-11-12.md 1.5; decision
// 2026-11-13-shopping-one-field) one field at the top, "What do you need?", with "From my list", takes every kind of
// shopping. `ShoppingRoute` (DoddyCore) decides where the words go, and the card says it before the tap:
//   - everyday things: "Cheapest this week" opens with them and checks this week's leaflets at once;
//   - a thing to compare online: "Find me this", behind the same yes card as before (DOD-07);
//   - things in between: the leaflets now, and online shops offered under the answer as the next step;
//   - a product link: the "Check this" card below, which still asks for its own tap.
// The person can pick the other place before the tap. Leaflet prices are the leaflets' as the server parsed them.

struct ShoppingHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(MemoryStore.self) private var store
    private let model = ErrandsModel.shared
    private let watches = WatchModel.shared
    /// Price alerts (decision 2026-11-14-price-alerts-screen): the row shows only once the server says they are on.
    private let priceAlerts = PriceAlertsModel.shared
    @State private var showPriceAlerts = false
    @State private var words = ""
    /// The person's own pick of where the words go; nil lets the code decide.
    @State private var place: ShoppingRoute.Place?
    /// Where the chip says the words go: `route.place` once the words have settled (`settlesRoute`, ShoppingMotion.swift).
    @State private var shownPlace: ShoppingRoute.Place = .nothing
    /// What matters most, in the order it was tapped.
    @State private var priorities: [String] = []
    /// A priority of the person's own, being typed.
    @State private var ownPriority = ""
    @State private var asking: TypedAsk?
    @State private var note: HandOverNote?
    @State private var opened: UUID?
    @State private var showDeals = false
    /// The leaflet check the field asked for: "Cheapest this week" opens with these items and checks them.
    @State private var leafletCheck: LeafletCheck?
    /// More things for online shops than one yes card holds: each offered after the first, one tap each.
    @State private var moreOnline: [String] = []
    @State private var moreOnlinePriorities: [String] = []
    @State private var showShopify = false
    /// "Check this": the link being pasted, the person's own name for the product, and the page whose card is open.
    @State private var link = ""
    @State private var linkName = ""
    @State private var watchPage: SharedShopPage?
    @FocusState private var typing: Bool

    /// Set when a link arrives from the Share Sheet, so the screen scrolls to the "Check this" card.
    @State private var scrollToCheckThis = false

    private var router: ShortcutRouter { .shared }
    private var scope: ReleaseScope { ReleaseScopeStore.current }
    private var shoppingTasks: [StoredErrand] { model.errands.filter { $0.draft.kind == .shopping } }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if !model.isServerConfigured {
                        Label("Doddy's server isn't set up in this build, so tasks can't run yet.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                            .tasksCard()
                    }
                    if scope.shows(.errands) || scope.shows(.deals) {
                        findCard
                    }
                    if scope.shows(.errands) {
                        OnlineNextCard(things: moreOnline, priorities: moreOnlinePriorities)
                        if !shoppingTasks.isEmpty { searches }
                    }
                    // Shops by kind (decision 2026-11-13-shopping-by-kind): groceries, fashion, electronics, home, other.
                    if scope.shows(.errands) || scope.shows(.deals) {
                        ShopKindsSection()
                    }
                    if scope.shows(.deals), priceAlerts.availability == .available {
                        PriceAlertsRow { showPriceAlerts = true }
                    }
                    if scope.shows(.priceWatch) {
                        checkThisCard.id(Self.checkThisCardID)
                        WatchesSection()
                        if watches.watches.isEmpty && watches.loadProblem == nil && watches.message == nil { watchHint }
                    }
                    if scope.shows(.deals) { leafletsLink }
                    if scope.shows(.shopifyShopping) { shopifyLink }
                    howItWorks
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .readableColumn()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .foregroundStyle(Theme.ink)
            .navigationTitle("Shopping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(item: $opened) { id in ErrandDetailView(id: id) }
            .sheet(item: $asking) { ask in
                TypedHandOverSheet(draft: ask.draft) { outcome in finished(outcome) }
            }
            .sheet(isPresented: $showDeals) { DealsView() }
            .sheet(item: $leafletCheck) { check in
                DealsView(start: check.items, online: check.online, onlinePriorities: check.priorities)
            }
            .sheet(isPresented: $showShopify) { ShopifyLiveShoppingView() }
            .sheet(item: $watchPage) { WatchCard(page: $0) }
            .sheet(isPresented: $showPriceAlerts) { PriceAlertsView() }
            .refreshable { await reload() }
            .task {
                await model.load()
                await reload()
            }
            // Whether the server keeps price alerts (it says so by answering the list): the row waits for that.
            .task { await priceAlerts.refresh() }
            // A price-alert push, tapped (decision 2026-11-14-price-alerts-screen): the alerts open, where what each found is.
            .onChange(of: router.isPriceAlertsRequested, initial: true) { _, requested in
                guard requested else { return }
                router.isPriceAlertsRequested = false
                guard scope.shows(.deals) else { return }
                showPriceAlerts = true
            }
            // A product link shared from Safari or a shop app with "Check the price": it fills the "Check this" card and
            // the screen scrolls there. The card still asks for a tap before anything is read or sent.
            .onChange(of: router.priceCheckLink, initial: true) { _, shared in
                guard shared != nil, let taken = router.takePriceCheckLink() else { return }
                link = taken
                linkName = ""
                scrollToCheckThis = true
            }
            .onChange(of: scrollToCheckThis) { _, go in
                guard go else { return }
                scrollToCheckThis = false
                withAnimation { proxy.scrollTo(Self.checkThisCardID, anchor: .top) }
            }
            }
        }
        .accessibilityIdentifier("shopping.hub")
    }

    private static let checkThisCardID = "shopping.checkThisCard"

    private func reload() async {
        await model.refresh()
        if scope.shows(.priceWatch) { await watches.refresh() }
    }

    // MARK: What this screen is

    private var hero: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                                  : AnyLayout(HStackLayout(alignment: .bottom, spacing: 12))
        return layout {
            WholeDoddyView(pose: .kneelingInspect, height: 112)
            VStack(alignment: .leading, spacing: 6) {
                Text("What do you need?")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text("Groceries: I check this week's leaflets right away. Things to compare: I look through online shops in Poland in the background. You buy in the shop; I never buy anything.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    // MARK: The one field

    /// Where the words go now: the person's pick, or the code's (`ShoppingRoute`), within what this build shows.
    private var route: ShoppingRoute {
        var pick = place
        if !scope.shows(.errands) { pick = .leaflets } else if !scope.shows(.deals) { pick = .online }
        return ShoppingRoute.route(words, to: pick)
    }

    private var findCard: some View {
        let route = self.route
        return VStack(alignment: .leading, spacing: 12) {
            TextField("What do you need?", text: $words, prompt: Text("Milk, butter, coffee, or a quiet 45 cm dishwasher under 2000 zł"), axis: .vertical)
                .lineLimit(2...5)
                .focused($typing)
                .shoppingFieldChrome(focused: typing)
                .onChange(of: words) { _, new in
                    if !new.isEmpty { note = nil }
                    if new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { place = nil }
                }
                .accessibilityIdentifier("shopping.words")
            if words.utf16.count > ErrandDraft.maxWords - 200 {
                Text(verbatim: "\(words.utf16.count) / \(ErrandDraft.maxWords)")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(words.utf16.count > ErrandDraft.maxWords ? Theme.error : Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            fromListButton
            if shownPlace != .nothing {
                whereItGoes(route)
            }
            if !route.online.isEmpty, shownPlace == .online || shownPlace == .both {
                prioritiesPicker
            }
            Button {
                typing = false
                go(route)
            } label: {
                goLabel(shownPlace)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canGo(route))
            .accessibilityIdentifier("shopping.find")
            if let note {
                Label(note.text, systemImage: note.kind.symbol)
                    .font(.subheadline)
                    .foregroundStyle(note.kind.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("shopping.findNote")
            }
            Text("Leaflet prices come back in seconds, and nothing is handed over for them. For online shops nothing is sent until you say yes on the next card; Doddy works on it in the background and the result waits here.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tasksCard()
        .settlesRoute(route.place, typing: typing, shown: $shownPlace)
    }

    /// Where the words go, said before the tap, with a way to pick the other place.
    private func whereItGoes(_ route: ShoppingRoute) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ShoppingRouteChip(place: shownPlace, online: route.online)
            Spacer(minLength: 4)
            if shownPlace != .link, scope.shows(.errands), scope.shows(.deals) {
                Menu {
                    Button("Let Doddy decide") { place = nil }
                    Button("Only this week's leaflets") { place = .leaflets }
                    Button("Only online shops") { place = .online }
                } label: {
                    Text("Change").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accentText)
                }
                .accessibilityIdentifier("shopping.place")
            }
        }
        .accessibilityIdentifier("shopping.route")
    }

    @ViewBuilder
    private func goLabel(_ place: ShoppingRoute.Place) -> some View {
        switch place {
        case .online: Label("Find it", systemImage: "magnifyingglass")
        case .link: Label("Check this page", systemImage: "magnifyingglass")
        default: Label("Check prices", systemImage: "tag")
        }
    }

    private func canGo(_ route: ShoppingRoute) -> Bool {
        // Only once the chip says where the words go: the card says it before the tap.
        guard shownPlace == route.place else { return false }
        return switch route.place {
        case .nothing: false
        case .link: true
        case .leaflets, .both: DealsModel.shared.phase != .checking
        case .online: model.isServerConfigured && !model.isHandingOver
        }
    }

    /// The tap: the leaflets open and check at once; online shops get the yes card; a link fills "Check this".
    private func go(_ route: ShoppingRoute) {
        switch route.place {
        case .nothing:
            return
        case .link:
            guard scope.shows(.priceWatch), let text = route.link else {
                note = HandOverNote(text: ErrandText.issue(.containsLink), kind: .problem)
                return
            }
            link = text
            linkName = ""
            words = ""
            note = nil
            scrollToCheckThis = true
        case .leaflets, .both:
            note = nil
            moreOnline = []
            leafletCheck = LeafletCheck(items: route.leaflets, online: route.online, priorities: priorities)
        case .online:
            moreOnline = Array(route.online.dropFirst())
            moreOnlinePriorities = priorities
            if let first = route.online.first { ask(first) }
        }
    }

    /// "From my list": the list's open items fill the field, one per line (a comma inside an item would split it).
    @ViewBuilder
    private var fromListButton: some View {
        let lists = store.lists.filter { !$0.open.isEmpty }
        if lists.count == 1, let list = lists.first {
            Button {
                fill(from: list)
            } label: {
                Label(String(format: NSLocalizedString("From my list: %@", comment: "fills the items from a shopping list"), list.name), systemImage: "list.bullet")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accentText)
            .accessibilityIdentifier("shopping.fromList")
        } else if lists.count > 1 {
            Menu {
                ForEach(lists) { list in
                    Button(list.name) { fill(from: list) }
                }
            } label: {
                Label("From my list", systemImage: "list.bullet")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Theme.accentText)
            .accessibilityIdentifier("shopping.fromList")
        }
    }

    private func fill(from list: DoddyList) {
        words = list.open.map { $0.text.replacingOccurrences(of: ",", with: " ") }.joined(separator: "\n")
        place = nil
        note = nil
    }

    /// "What matters most?": tap in the order that matters. The number on a chip is its place.
    private var prioritiesPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What matters most? Tap in your order.")
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            ChipFlow(spacing: 8) {
                ForEach(choices, id: \.self) { choice in
                    let place = ShoppingPriorities.place(of: choice, in: priorities)
                    Button {
                        priorities = ShoppingPriorities.toggled(choice, in: priorities)
                    } label: {
                        HStack(spacing: 6) {
                            if let place {
                                Text(verbatim: "\(place)").font(.caption.weight(.bold)).monospacedDigit()
                            }
                            Text(verbatim: choice).font(.subheadline)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(minHeight: 36)
                        .foregroundStyle(place == nil ? Theme.ink : Theme.inkOnOrange)
                        .background(Capsule().fill(place == nil ? Theme.canvas : Theme.orangeCue))
                        .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: place == nil ? 1 : 0))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: choice))
                    .accessibilityValue(Text(verbatim: place.map { String(format: NSLocalizedString("Number %lld", comment: "a shopping priority's place in the order"), $0) } ?? ""))
                    .accessibilityAddTraits(place == nil ? [] : .isSelected)
                    .accessibilityIdentifier("shopping.priority")
                }
            }
            .choiceMotion(priorities)
            if priorities.count < ErrandDraft.maxPriorities {
                TextField("Something else", text: $ownPriority, prompt: Text("Something else, e.g. white, made in the EU"))
                    .font(.subheadline)
                    .submitLabel(.done)
                    .onSubmit { addOwnPriority() }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
                    .accessibilityIdentifier("shopping.ownPriority")
            }
        }
    }

    /// The suggestions, then whatever the person added themselves (so it can be tapped back out).
    private var choices: [String] {
        let own = priorities.filter { chosen in !Self.suggestions.contains { $0.lowercased() == chosen.lowercased() } }
        return Self.suggestions + own
    }

    private static var suggestions: [String] {
        [
            NSLocalizedString("Price", comment: "a shopping priority"),
            NSLocalizedString("Quality", comment: "a shopping priority"),
            NSLocalizedString("Fast delivery", comment: "a shopping priority"),
            NSLocalizedString("Good reviews", comment: "a shopping priority"),
            NSLocalizedString("Warranty", comment: "a shopping priority"),
            NSLocalizedString("Brand", comment: "a shopping priority"),
        ]
    }

    private func addOwnPriority() {
        let word = ownPriority.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        // Already chosen: leave it in (a second tap on its chip takes it out), just clear the field.
        if ShoppingPriorities.place(of: word, in: priorities) == nil {
            priorities = ShoppingPriorities.toggled(word, in: priorities)
        }
        ownPriority = ""
    }

    /// Checks here first (the server checks again): no link, not too long, Connections not paused.
    /// Only then does the card ask; nothing has been sent at this point. `thing` is the field's words when they
    /// name one thing, exactly as typed (trimmed), or one of several things.
    private func ask(_ thing: String) {
        let language = ErrandDraft.typedLanguage(Bundle.main.preferredLocalizations.first ?? "en")
        let draft = ErrandDraft.typedShopping(thing, priorities: priorities, language: language)
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

    /// The card closed with an answer. "Looking" only when the server said it has the task.
    private func finished(_ outcome: ErrandsModel.HandOverOutcome) {
        switch outcome {
        case .started:
            words = ""
            priorities = []
            ownPriority = ""
            note = HandOverNote(text: NSLocalizedString("Doddy is looking. The picks will wait here, in Tasks and in Messages.", comment: ""), kind: .confirmed)
        case .maybeStarted:
            note = HandOverNote(text: NSLocalizedString("Doddy couldn't confirm it started. It may be running: pull down to check before you hand it over again.", comment: ""), kind: .unsure)
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

    // MARK: What was already looked for

    private var searches: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your searches").font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(shoppingTasks.enumerated()), id: \.element.id) { index, errand in
                    if index > 0 { Divider().overlay(Theme.separator) }
                    Button { opened = errand.id } label: {
                        ErrandCardRow(errand: errand, isNew: model.unseenFinished.contains(errand.id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shopping.search")
                }
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.quietSurface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
        }
    }

    // MARK: Check this

    /// The page in the pasted text, with the person's own name for it. Nothing has been sent: reading the text is
    /// done here, and Doddy's server gets the page only when the card's own button says "Check the page".
    private var pastedPage: SharedShopPage? {
        SharedShopPage.parse(link)?.titled(linkName)
    }

    private var checkThisCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Check this").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Paste the link to a product you're looking at in a shop. Doddy's server reads the page and shows its price; then you can ask Doddy to watch it.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Product link", text: $link, prompt: Text(verbatim: "https://…"), axis: .vertical)
                .lineLimit(1...3)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.canvas))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
                .accessibilityIdentifier("shopping.link")
            if let page = pastedPage {
                Label(String(format: NSLocalizedString("Page at %@", comment: "the shop a pasted link points to"), page.shop),
                      systemImage: "link")
                    .font(.subheadline)
                TextField("What is it? (optional)", text: $linkName)
                    .font(.subheadline)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
                    .accessibilityIdentifier("shopping.linkName")
            } else if !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("That isn't a web address Doddy can read. It must start with https://.", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                watchPage = pastedPage
            } label: {
                Label("Check this page", systemImage: "magnifyingglass")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(pastedPage == nil || !model.isServerConfigured)
            .accessibilityIdentifier("shopping.checkThis")
            Text("Nothing is sent until you tap “Check the page” on the next card. Some shops don't let Doddy's server read their pages; then Doddy tells you it couldn't read a price.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tasksCard()
    }

    // MARK: Watching a price

    /// Shown while nothing is watched: where a watch starts. It says nothing about whether one is on.
    private var watchHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Watched prices", systemImage: "bell").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Open a result and tap “Watch the price” on a pick. You give your price, and Doddy tells you once when the shop's page shows that price or less.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tasksCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("shopping.watchHint")
    }

    // MARK: The leaflets

    private var leafletsLink: some View {
        Button { showDeals = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "cart").font(.title3).foregroundStyle(Theme.accentText).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cheapest this week").font(.subheadline.weight(.semibold))
                    Text("Groceries and everyday things: where each is cheapest in this week's leaflets.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .tasksCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shopping.leaflets")
    }

    // MARK: Shopify shops

    private var shopifyLink: some View {
        Button { showShopify = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "bag").font(.title3).foregroundStyle(Theme.accentText).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shopify shops").font(.subheadline.weight(.semibold))
                    Text("Search products in Shopify shops and prepare a cart at the shop. Doddy takes no payment.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .tasksCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shopping.shopify")
    }

    // MARK: How it works

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it works").font(.headline).accessibilityAddTraits(.isHeader)
            Label("You say what you need and what matters most. By voice works too: “find me a quiet dishwasher”.", systemImage: "1.circle")
            Label("Doddy looks for offers and reads each shop's own page. A price he couldn't confirm there isn't shown, and he says so.", systemImage: "2.circle")
            Label("You get up to three picks with the reason for each, and you can ask Doddy to watch a price.", systemImage: "3.circle")
            Label("The buy button opens the shop's own page in Safari. The shop takes the payment.", systemImage: "4.circle")
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
        .tasksCard()
    }
}

/// The leaflet check the one field asked for, with the things it also sends to online shops.
private struct LeafletCheck: Identifiable {
    let id = UUID()
    let items: [String]
    let online: [String]
    let priorities: [String]
}
