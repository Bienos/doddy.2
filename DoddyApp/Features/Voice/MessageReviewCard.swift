import DoddyCore
import SwiftUI

/// The exact message being reviewed, shared by Home and the transcript screen.
struct MessageReviewCard: View {
    let recipientName: String
    let address: String
    @Binding var message: String
    let status: VoiceSessionController.MessageReviewStatus?
    let canConfirmByVoice: Bool
    let open: () -> Void
    let cancel: () -> Void

    private var isWaitingForReadBack: Bool { status == .preparing || status == .reading }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Review message", systemImage: "text.bubble")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: NSLocalizedString("Message for %@.", comment: "Recipient in message review"), recipientName))
                    .font(.subheadline.weight(.semibold))
                Text(address)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .textSelection(.enabled)
            }

            TextField("Message text", text: $message, axis: .vertical)
                .font(.body)
                .lineLimit(3...8)
                .padding(12)
                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.separator, lineWidth: 1))
                .accessibilityLabel("Message to \(recipientName)")
                .accessibilityIdentifier("voice.message.body")

            reviewStatus
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("voice.message.status")

            Text("Messages opens a draft. You still tap Send.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)

            Button(action: open) {
                HStack {
                    Text("Open in Messages")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isWaitingForReadBack)
            .accessibilityIdentifier("voice.message.open")

            Button("Cancel", action: cancel)
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("voice.message.cancel")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.separator, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice.message.review")
    }

    @ViewBuilder private var reviewStatus: some View {
        switch status {
        case .some(.preparing):
            Label("Preparing spoken review…", systemImage: "waveform")
        case .some(.reading):
            Label("Reading message aloud. Use Cancel if you want to stop.", systemImage: "waveform")
        case .some(.ready) where canConfirmByVoice:
            Label("Say “open it” or “cancel”, or use the buttons.", systemImage: "waveform")
        case .some(.ready):
            Text("Review the draft, then choose a button.")
        case .some(.unavailable):
            Text("Doddy couldn't read it aloud. Review the recipient and text, then choose a button.")
        case .none:
            Text("Review the draft, then choose a button.")
        }
    }
}
