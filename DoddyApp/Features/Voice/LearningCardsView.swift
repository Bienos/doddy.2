import DoddyCore
import SwiftUI

/// "I noticed…" after a conversation (ADR-324): the exact words, where they came from, and
/// Save / Not now / Never this. Shown only when "Learn from how I use Doddy" is on. "Saved"
/// appears only after the row was read back from the store.
struct LearningCardsView: View {
    let learning: LearningStore

    private var visible: [LearningCard] { learning.cards.filter { $0.state != .dismissed } }

    var body: some View {
        ForEach(visible) { card in
            VStack(alignment: .leading, spacing: 12) {
                Text(title(card.item)).font(.headline)
                content(card.item)
                actions(card)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("voice.learningCard")
        }
    }

    private func title(_ item: LearningCardItem) -> String {
        switch item {
        case .fact: NSLocalizedString("Remember this about you?", comment: "")
        case .procedure: NSLocalizedString("Save this routine?", comment: "")
        }
    }

    @ViewBuilder
    private func content(_ item: LearningCardItem) -> some View {
        switch item {
        case .fact(let fact):
            Text(verbatim: "“\(fact.value)”").font(.body)
            Text("Doddy noticed this in what you said. It stays on this iPhone. It is handed to Doddy in a conversation only if you turned that on in Settings, What I've learned.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        case .procedure(let procedure):
            Text(procedure.triggerText).font(.body.weight(.semibold))
            ForEach(procedure.steps, id: \.number) { step in
                Text(LearnedView.stepText(step)).font(.subheadline)
            }
            Text("You did these in this order on three different days. If you save it, you can ask Doddy for it by name. Every step still asks you first, every time.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder
    private func actions(_ card: LearningCard) -> some View {
        switch card.state {
        case .offered, .failed:
            if case .failed(let message) = card.state {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Not saved.", systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
                    Text(verbatim: message).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            HStack {
                Button("Save") { Task { await learning.saveCard(card.id) } }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("voice.learning.save")
                Button("Not now") { learning.dismissCard(card.id) }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("voice.learning.notNow")
            }
            Button("Never this") { Task { await learning.neverCard(card.id) } }
                .font(.footnote)
                .accessibilityIdentifier("voice.learning.never")
        case .saving:
            ProgressView().frame(maxWidth: .infinity)
        case .saved:
            Label("Saved. You can change or remove it in Settings, What I've learned.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.confirmed)
            Button("OK") { learning.dismissCard(card.id) }
                .buttonStyle(SecondaryButtonStyle())
        case .dismissed:
            EmptyView()
        }
    }
}
