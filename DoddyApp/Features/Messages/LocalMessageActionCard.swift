import DoddyCore
import SwiftUI

struct LocalMessageActionCard: View {
    let action: LocalMessageAction
    let busy: Bool
    let confirm: () -> Void
    let dismiss: () -> Void

    var body: some View {
        let polish = Locale.current.language.languageCode?.identifier == "pl"
        let card = action.card(polish: polish)
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: card.title).font(.headline)
            ForEach(Array(card.lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line).font(.callout).textSelection(.enabled)
            }
            Text(verbatim: polish ? "Wynik zostanie zapisany w tej rozmowie i jej kopii w Doddy Web." : "The result will be kept in this conversation and its copy in Doddy Web.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            HStack {
                if action.canExecute {
                    Button(action: confirm) { Text(verbatim: card.confirmLabel) }
                        .buttonStyle(PrimaryButtonStyle()).disabled(busy)
                        .accessibilityIdentifier("messages.confirmLocalAction")
                }
                Button("Not now", action: dismiss).buttonStyle(SecondaryButtonStyle()).disabled(busy)
                    .accessibilityIdentifier("messages.dismissLocalAction")
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.trailing, 24).accessibilityElement(children: .contain)
    }
}
