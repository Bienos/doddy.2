import SwiftUI
import DoddyCore

struct HomeView: View {
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your mate in your pocket.")
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("DODDY is an AI assistant, not a person. This is an early development build.")
                            .foregroundStyle(Theme.secondaryText)
                    }

                    CandidateCharacterView(assetName: "Doddy_waving")
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Right now")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text("This build only shows its own screens, privacy summary and appearance settings. It cannot save or find memories, answer questions, listen, or set reminders, and it sends nothing anywhere.")
                        ForEach([Capability.memoryStorage, .memoryRecall, .cloudAssistant], id: \.self) { capability in
                            StatusRow(
                                title: capability.displayName,
                                value: StatusCopy.text(for: environment.capabilities.status(of: capability)))
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("home.status")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(Theme.canvas)
            .navigationTitle("Doddy")
            .navigationBarTitleDisplayMode(.inline)
        }
        .foregroundStyle(Theme.ink)
    }
}
