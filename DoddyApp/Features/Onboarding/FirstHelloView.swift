import SwiftUI

/// Minimal First Hello: honest introduction with equal-weight Start and Skip. It saves no
/// preferences, asks no questions and starts no setup wizard (M0 scope).
struct FirstHelloView: View {
    let onFinish: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Hey. I'm Doddy.")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("I'm an AI assistant, not a person. This is an early development build, so I can't save anything, answer questions, listen, or set reminders yet. Nothing you do here leaves your phone.")

                CandidateCharacterView(assetName: "Doddy_waving")
                    .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    Button(action: onFinish) {
                        Text("Take a look around")
                            .foregroundStyle(Theme.canvas)
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.ink)
                    .accessibilityIdentifier("firstHello.start")

                    Button(action: onFinish) {
                        Text("Skip")
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.ink)
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
