import DoddyCore
import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: AppTab

    @Environment(MemoryStore.self) private var store
    @State private var showCapture = false
    private var router: ShortcutRouter { .shared }

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
                        Button { router.isVoicePresented = true } label: {
                            HStack { Text("Talk to Doddy"); Spacer(); Image(systemName: "waveform") }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!store.environment.capabilities.isAvailable(.voiceInput))
                        .accessibilityIdentifier("home.talk")

                        Button { showCapture = true } label: {
                            HStack { Text("Save a detail"); Spacer(); Image(systemName: "square.and.pencil") }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(!store.isStorageAvailable)
                        .accessibilityIdentifier("home.save")

                        Button { selectedTab = .memories } label: {
                            HStack { Text("Find something"); Spacer(); Image(systemName: "magnifyingglass") }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("home.find")
                    }

                    if router.setup.phase == .notStarted {
                        backTapCard
                    }

                    recent

                    Text("Doddy is an AI, not a person. Notes stay on this iPhone; talking uses ElevenLabs only while a conversation is open. Reminders and other apps aren't built yet.")
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

    /// Offered once; "Later" hides it (Settings can reopen the guide). Never shown as done
    /// unless the user reported a successful tap test.
    private var backTapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reach Doddy with two taps")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Double-tap the back of your iPhone to start talking. It takes a minute in Settings, and Doddy walks you through it.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 12) {
                Button("Set up") { router.isSetupPresented = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("home.backTap.setup")
                Button("Later") { router.setup.send(.deferSetup) }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("home.backTap.later")
            }
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
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
