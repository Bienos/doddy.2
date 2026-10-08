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
                Text("I'm an AI assistant, not a person. For now I keep the details you choose to save and help you find them again, on this iPhone only. Answering questions is an optional cloud preview in Settings; I can't listen or set reminders yet.")

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
