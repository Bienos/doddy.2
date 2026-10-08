import SwiftUI

/// First Hello: honest introduction with equal-weight Start and Skip. Saves no preferences
/// and asks nothing.
struct FirstHelloView: View {
    let onFinish: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Hey. I'm Doddy.")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("I'm an AI assistant, not a person. You can talk to me, and I keep the details you choose to save and help you find them again. Your notes stay on this iPhone; when we talk, your voice goes to ElevenLabs to run the conversation. I can't set reminders or use other apps yet.")

                CandidateCharacterView(assetName: "Doddy_waving")
                    .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    Button(action: onFinish) {
                        HStack { Text("Take a look around"); Spacer(); Image(systemName: "arrow.right") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("firstHello.start")

                    Button(action: onFinish) {
                        Text("Skip")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("firstHello.skip")
                }
            }
            .padding(24)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
        .accessibilityIdentifier("firstHello")
    }
}
