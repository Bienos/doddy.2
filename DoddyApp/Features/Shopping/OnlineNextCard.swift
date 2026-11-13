import DoddyCore
import SwiftUI

// "Search online shops" (decision 2026-11-13-shopping-one-field; docs/strategy/PRZEGLAD_APLIKACJI_2026-11-12.md 1.4
// and 1.5): after a leaflet answer, the things worth comparing online are offered as the next step, one button
// each. Which things is code's (`ShoppingRoute.onlineNext`): those in between (a kettle, shoes), those for online
// shops, and an unknown item the leaflets had nothing for. Groceries never are.
// A button only prepares "Find me this": the same typed shopping task as on the Shopping screen, behind the same
// yes card that shows exactly what goes to Doddy's server (constitution DOD-07). Nothing is sent before "Yes, go".
// A start Doddy's server didn't confirm keeps its button off, so the same task isn't handed over twice blindly.

struct OnlineNextCard: View {
    /// The things to offer, in order, each in the person's words.
    let things: [String]
    /// What matters most, as tapped on the Shopping screen (empty from the leaflet screen on its own).
    var priorities: [String] = []

    @State private var asking: OnlineAsk?
    @State private var notes: [String: HandOverNote] = [:]
    /// Handed over, or maybe handed over: no second tap.
    @State private var sent: Set<String> = []
    private let model = ErrandsModel.shared

    var body: some View {
        if !things.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Online shops next", systemImage: "magnifyingglass")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Doddy can compare these in online shops in the background and bring back up to three picks, each with the price read on the shop's own page. Nothing is sent until you say yes on the next card.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(things, id: \.self) { thing in
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            ask(thing)
                        } label: {
                            Label(String(format: NSLocalizedString("Search online shops for “%@”", comment: "starts the Find me this card for one item"), thing),
                                  systemImage: "bag")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(sent.contains(thing) || !model.isServerConfigured || model.isHandingOver)
                        .accessibilityIdentifier("shopping.searchOnline")
                        if let note = notes[thing] {
                            Label(note.text, systemImage: note.kind.symbol)
                                .font(.footnote)
                                .foregroundStyle(note.kind.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if !model.isServerConfigured {
                    Label("Doddy's server isn't set up in this build, so tasks can't run yet.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.error)
                }
            }
            .tasksCard()
            .accessibilityIdentifier("shopping.onlineNext")
            .sheet(item: $asking) { ask in
                TypedHandOverSheet(draft: ask.draft) { outcome in finished(ask.thing, outcome) }
            }
        }
    }

    /// The same checks as the Shopping screen's field, here first (the server checks again). Nothing is sent here.
    private func ask(_ thing: String) {
        let language = ErrandDraft.typedLanguage(Bundle.main.preferredLocalizations.first ?? "en")
        let draft = ErrandDraft.typedShopping(thing, priorities: priorities, language: language)
        if let issue = draft.validationIssues().first {
            notes[thing] = HandOverNote(text: ErrandText.issue(issue), kind: .problem)
            return
        }
        if UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) {
            notes[thing] = HandOverNote(text: ErrandText.paused, kind: .problem)
            return
        }
        notes[thing] = nil
        asking = OnlineAsk(thing: thing, draft: draft)
    }

    /// "Looking" only when the server said it has the task.
    private func finished(_ thing: String, _ outcome: ErrandsModel.HandOverOutcome) {
        switch outcome {
        case .started:
            sent.insert(thing)
            notes[thing] = HandOverNote(text: NSLocalizedString("Doddy is looking. The picks will wait in Shopping, in Tasks and in Messages.", comment: ""), kind: .confirmed)
        case .maybeStarted:
            sent.insert(thing)
            notes[thing] = HandOverNote(text: NSLocalizedString("Doddy couldn't confirm it started. It may be running: check Shopping or Tasks before you hand it over again.", comment: ""), kind: .unsure)
        case .notStarted(let error):
            notes[thing] = HandOverNote(text: ErrandText.notStarted(error), kind: .problem)
        case .invalid(let issue):
            notes[thing] = HandOverNote(text: ErrandText.issue(issue), kind: .problem)
        case .paused:
            notes[thing] = HandOverNote(text: ErrandText.paused, kind: .problem)
        case .alreadySending:
            break
        }
    }
}

/// One thing and the draft its yes card asks about.
private struct OnlineAsk: Identifiable {
    let id = UUID()
    let thing: String
    let draft: ErrandDraft
}
