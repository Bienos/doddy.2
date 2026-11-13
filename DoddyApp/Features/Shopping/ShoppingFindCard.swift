import DoddyCore
import SwiftUI

// "Find me this" (docs/implementation/SHOPPING.md 1), the field the Shopping screen opens with, and the same field on
// each kind's page (owner, 13 Nov 2026). The words and what matters most are typed here; the same yes card as a typed
// task (TypedHandOverSheet) shows exactly what goes to Doddy's server before anything is sent. On a kind's page the
// kind is one more line under the words (`ShopCategoryRequest`), so the card shows it and the digest covers it.
// Nothing here is new capability: it is the hub's old "Find me this" card, moved so both screens share it.

struct ShoppingFindCard: View {
    /// The kind of shop the search is about; nil on the Shopping screen itself.
    let category: ShopCategory?
    private let model = ErrandsModel.shared
    @State private var words = ""
    /// What matters most, in the order it was tapped.
    @State private var priorities: [String] = []
    /// A priority of the person's own, being typed.
    @State private var ownPriority = ""
    @State private var asking: TypedAsk?
    @State private var note: HandOverNote?
    @FocusState private var typing: Bool

    init(category: ShopCategory? = nil) {
        self.category = category
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading
            field
            counter
            prioritiesPicker
            findButton
            noteLine
            DoddyFinePrint(text: Text("Nothing is sent until you say yes on the next card. Doddy works on it in the background; the picks wait here, in Tasks and in Messages."))
        }
        .doddyCard(padding: 18, accent: true)
        .sheet(item: $asking) { ask in
            TypedHandOverSheet(draft: ask.draft) { outcome in finished(outcome) }
        }
    }

    // MARK: Parts

    private var heading: some View {
        HStack(alignment: .center, spacing: 12) {
            DoddyIconBadge(systemName: "magnifyingglass", size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Find me this")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let category {
                    Text(verbatim: String(format: NSLocalizedString("Looking in: %@", comment: "the kind of shop a search is about"), category.title))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Text("Up to three picks from shops in Poland, side by side.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var field: some View {
        TextField("Find me this", text: $words, prompt: Text(prompt), axis: .vertical)
            .font(.body)
            .lineLimit(2...6)
            .focused($typing)
            .doddyField()
            .onChange(of: words) { _, new in if !new.isEmpty { note = nil } }
            .accessibilityIdentifier("shopping.words")
    }

    /// An example for the kind, so the field says what it is for.
    private var prompt: String {
        switch category {
        case .groceries?: NSLocalizedString("For example: washing powder for 60 washes, the cheapest per wash", comment: "Find me this, groceries")
        case .fashion?: NSLocalizedString("For example: white leather trainers, size 42, under 400 zł", comment: "Find me this, fashion")
        case .electronics?: NSLocalizedString("For example: noise-cancelling headphones under 600 zł", comment: "Find me this, electronics")
        case .home?: NSLocalizedString("For example: a cordless drill for the house, under 400 zł", comment: "Find me this, home")
        case .other?: NSLocalizedString("For example: dry food for a large dog, 12 kg", comment: "Find me this, other")
        case nil: NSLocalizedString("For example: a quiet 45 cm dishwasher under 2000 zł", comment: "")
        }
    }

    /// The words exactly as the server would get them, with the kind's line.
    private var sentWords: String {
        ShopCategoryRequest.words(words, category: category, language: language)
    }

    private var language: String {
        ErrandDraft.typedLanguage(Bundle.main.preferredLocalizations.first ?? "en")
    }

    @ViewBuilder
    private var counter: some View {
        let count = sentWords.utf16.count
        if count > ErrandDraft.maxWords - 200 {
            Text(verbatim: "\(count) / \(ErrandDraft.maxWords)")
                .font(.caption).monospacedDigit()
                .foregroundStyle(count > ErrandDraft.maxWords ? Theme.error : Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// "What matters most?": tap in the order that matters. The number on a chip is its place.
    private var prioritiesPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What matters most? Tap in your order.")
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            ChipFlow(spacing: 8) {
                ForEach(choices, id: \.self) { choice in
                    PriorityChip(choice: choice, place: ShoppingPriorities.place(of: choice, in: priorities)) {
                        priorities = ShoppingPriorities.toggled(choice, in: priorities)
                    }
                }
            }
            if priorities.count < ErrandDraft.maxPriorities {
                TextField("Something else", text: $ownPriority, prompt: Text("Something else, e.g. white, made in the EU"))
                    .font(.subheadline)
                    .submitLabel(.done)
                    .onSubmit { addOwnPriority() }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .overlay { Capsule().strokeBorder(Theme.separator, lineWidth: 1) }
                    .accessibilityIdentifier("shopping.ownPriority")
            }
        }
    }

    private var findButton: some View {
        Button {
            typing = false
            ask()
        } label: {
            Label("Find it", systemImage: "magnifyingglass")
        }
        .buttonStyle(DoddyAccentButtonStyle())
        .disabled(words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.isServerConfigured || model.isHandingOver)
        .accessibilityIdentifier("shopping.find")
    }

    @ViewBuilder
    private var noteLine: some View {
        if let note {
            Label(note.text, systemImage: note.kind.symbol)
                .font(.subheadline)
                .foregroundStyle(note.kind.color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("shopping.findNote")
        }
    }

    // MARK: Priorities

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

    // MARK: Handing it over

    /// Checks here first (the server checks again): no link, not too long, Connections not paused.
    /// Only then does the card ask; nothing has been sent at this point.
    private func ask() {
        let draft = ErrandDraft.typedShopping(sentWords, priorities: priorities, language: language)
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
}

/// One "what matters most" choice: an outline, or orange with its place in the order.
private struct PriorityChip: View {
    let choice: String
    let place: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let place {
                    Text(verbatim: "\(place)").font(.caption.weight(.bold)).monospacedDigit()
                }
                Text(verbatim: choice).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .foregroundStyle(place == nil ? Theme.ink : Theme.inkOnOrange)
            .background(place == nil ? Theme.canvas : Theme.orangeCue, in: Capsule())
            .overlay { if place == nil { Capsule().strokeBorder(Theme.separator, lineWidth: 1) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: choice))
        .accessibilityValue(Text(verbatim: place.map { String(format: NSLocalizedString("Number %lld", comment: "a shopping priority's place in the order"), $0) } ?? ""))
        .accessibilityAddTraits(place == nil ? [] : .isSelected)
        .accessibilityIdentifier("shopping.priority")
    }
}
