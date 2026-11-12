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

struct ShoppingHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    private let model = ErrandsModel.shared
    private let watches = WatchModel.shared
    @State private var words = ""
    /// What matters most, in the order it was tapped.
    @State private var priorities: [String] = []
    /// A priority of the person's own, being typed.
    @State private var ownPriority = ""
    @State private var asking: TypedAsk?
    @State private var note: HandOverNote?
    @State private var opened: UUID?
    @State private var showDeals = false
    /// "Check this": the link being pasted, the person's own name for the product, and the page whose card is open.
    @State private var link = ""
    @State private var linkName = ""
    @State private var watchPage: SharedShopPage?
    @FocusState private var typing: Bool

    private var scope: ReleaseScope { ReleaseScopeStore.current }
    private var shoppingTasks: [StoredErrand] { model.errands.filter { $0.draft.kind == .shopping } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if !model.isServerConfigured {
                        Label("Doddy's server isn't set up in this build, so tasks can't run yet.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                            .tasksCard()
                    }
                    if scope.shows(.errands) {
                        findCard
                        if !shoppingTasks.isEmpty { searches }
                    }
                    if scope.shows(.priceWatch) {
                        checkThisCard
                        WatchesSection()
                        if watches.watches.isEmpty && watches.loadProblem == nil && watches.message == nil { watchHint }
                    }
                    if scope.shows(.deals) { leafletsLink }
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
            .sheet(item: $watchPage) { WatchCard(page: $0) }
            .refreshable { await reload() }
            .task {
                await model.load()
                await reload()
            }
        }
        .accessibilityIdentifier("shopping.hub")
    }

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
                Text("What are you looking for?")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text("I look through shops in Poland and bring back up to three picks, each with a price I read on the shop's own page. You buy in the shop; I never buy anything.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    // MARK: Find me this

    private var findCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find me this").font(.headline).accessibilityAddTraits(.isHeader)
            TextField("Find me this", text: $words, prompt: Text("For example: a quiet 45 cm dishwasher under 2000 zł"), axis: .vertical)
                .lineLimit(2...5)
                .focused($typing)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.canvas))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
                .onChange(of: words) { _, new in if !new.isEmpty { note = nil } }
                .accessibilityIdentifier("shopping.words")
            if words.utf16.count > ErrandDraft.maxWords - 200 {
                Text(verbatim: "\(words.utf16.count) / \(ErrandDraft.maxWords)")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(words.utf16.count > ErrandDraft.maxWords ? Theme.error : Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            prioritiesPicker
            Button {
                typing = false
                ask()
            } label: {
                Label("Find it", systemImage: "magnifyingglass")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.isServerConfigured || model.isHandingOver)
            .accessibilityIdentifier("shopping.find")
            if let note {
                Label(note.text, systemImage: note.kind.symbol)
                    .font(.subheadline)
                    .foregroundStyle(note.kind.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("shopping.findNote")
            }
            Text("Nothing is sent until you say yes on the next card. Doddy works on it in the background; the result waits here.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tasksCard()
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
    /// Only then does the card ask; nothing has been sent at this point.
    private func ask() {
        let language = ErrandDraft.typedLanguage(Bundle.main.preferredLocalizations.first ?? "en")
        let draft = ErrandDraft.typedShopping(words, priorities: priorities, language: language)
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
