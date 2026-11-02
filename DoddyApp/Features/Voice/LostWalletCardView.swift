import DoddyCore
import SwiftUI

/// "I lost my wallet" (ADR-692): the official steps, most urgent first. Each step's page opens, or
/// its number is dialled, only on the person's tap; the tick is theirs alone and says only that they
/// did the step. Doddy can't block a card, cancel an ID or reserve a PESEL, and the card never says
/// it did.
struct LostWalletCardView: View {
    let card: VoiceSessionController.LostWalletCard
    let onOpen: (LostWalletStep) -> Void
    let onToggle: (LostWalletStepID) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("What to do now", systemImage: "wallet.pass")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            Text("Most urgent first. Doddy can't do these for you: each button opens the official page or calls the number when you tap it.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            ForEach(Array(card.steps.enumerated()), id: \.element.id) { index, step in
                stepRow(step, number: index + 1, done: card.done.contains(step.id))
            }
            Text("Tick a step when you've done it. Doddy can't see your bank or mObywatel, so only you know it's done.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("voice.lostWalletCard")
    }

    private func stepRow(_ step: LostWalletStep, number: Int, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { onToggle(step.id) } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? Theme.orangeCue : Theme.secondaryText)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? Text("Done") : Text("Mark as done"))
            .accessibilityValue(Text(verbatim: step.title))
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "\(number). \(step.title)")
                    .font(.body.weight(.semibold))
                    .strikethrough(done)
                Text(step.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let label = step.actionLabel, step.action != nil {
                    Button { onOpen(step) } label: {
                        Label(label, systemImage: step.systemImage)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("voice.lostWallet.\(step.id.rawValue)")
                }
            }
        }
    }
}

private extension LostWalletStep {
    var systemImage: String {
        if case .some(.call) = action { return "phone" }
        return "safari"
    }
}
