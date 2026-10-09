import DoddyCore
import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: AppTab

    @Environment(MemoryStore.self) private var store
    @Environment(ProfileStore.self) private var profiles
    @State private var showCapture = false
    @State private var showVoice = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(greeting)
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("home.greeting")
                        Text("Save a useful detail. Find it when you need it.")
                            .foregroundStyle(Theme.secondaryText)
                    }

                    CandidateCharacterView(assetName: "Doddy_waving")
                        .frame(maxWidth: .infinity)

                    if let problem = store.environment.storageProblem {
                        ProblemView(message: problem)
                    }

                    VStack(spacing: 12) {
                        Button { showVoice = true } label: {
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

                    aboutYou

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
            .fullScreenCover(isPresented: $showVoice) { VoiceView() }
        }
        .foregroundStyle(Theme.ink)
    }

    /// Uses only the approved name; without one, the neutral line.
    private var greeting: String {
        if let name = profiles.profile.value(.name) { return "Hi, \(name)." }
        return "A little less to carry."
    }

    /// What the user approved in the introduction, shown back plainly. Nothing is invented
    /// when the profile is empty.
    @ViewBuilder
    private var aboutYou: some View {
        let profile = profiles.profile
        let shown = [ProfileKey.context, .help, .style].filter { profile.value($0) != nil }
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("What you told me")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(shown, id: \.self) { key in
                    StatusRow(title: key.label, value: profile.value(key) ?? "")
                }
                Text("Change or forget these in Settings. Voice conversations don't use them yet.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(16)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("home.aboutYou")
        }
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
