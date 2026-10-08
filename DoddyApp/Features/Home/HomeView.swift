import DoddyCore
import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: AppTab

    @Environment(MemoryStore.self) private var store
    @State private var showCapture = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A little less to carry.")
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("Save a useful detail. Find it when you need it.")
                            .foregroundStyle(Theme.secondaryText)
                    }

                    CandidateCharacterView(assetName: "Doddy_waving")
                        .frame(maxWidth: .infinity)

                    if let problem = store.environment.storageProblem {
                        ProblemView(message: problem)
                    }

                    VStack(spacing: 12) {
                        Button { showCapture = true } label: {
                            HStack { Text("Save a detail"); Spacer(); Image(systemName: "arrow.right") }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!store.isStorageAvailable)
                        .accessibilityIdentifier("home.save")

                        Button { selectedTab = .memories } label: {
                            HStack { Text("Find something"); Spacer(); Image(systemName: "magnifyingglass") }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("home.find")
                    }

                    recent

                    Text("Stored on this iPhone only. Doddy is an AI assistant, not a person; AI answers are an optional preview you can turn on in Settings (untested on a device); voice and reminders aren't built yet.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("home.status")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(Theme.canvas)
            .navigationTitle("Doddy")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { MemoryDetailView(memoryID: $0) }
            .sheet(isPresented: $showCapture) { CaptureView() }
        }
        .foregroundStyle(Theme.ink)
    }

    @ViewBuilder
    private var recent: some View {
        if !store.memories.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recently saved")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(store.memories.prefix(3)) { record in
                    NavigationLink(value: record.id) {
                        MemoryRow(record: record)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        } else if store.hasLoaded {
            Text("Nothing saved yet. You choose what stays.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}
