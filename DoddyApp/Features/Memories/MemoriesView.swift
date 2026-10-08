import SwiftUI
import DoddyCore

/// Placeholder only. No list, sample rows or history are shown because none exist.
struct MemoriesView: View {
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CandidateCharacterView(assetName: "Doddy_memory_card", size: 150)
                    Text("No memories yet")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Saving: \(StatusCopy.text(for: environment.capabilities.status(of: .memoryStorage))). When it exists, only what you choose to save will appear here — nothing is added automatically, and nothing on this screen is a sample.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("memories.empty")
            }
            .background(Theme.canvas)
            .navigationTitle("Memories")
            .navigationBarTitleDisplayMode(.inline)
        }
        .foregroundStyle(Theme.ink)
    }
}
