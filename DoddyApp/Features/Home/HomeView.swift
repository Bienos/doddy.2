import DoddyCore
import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @Binding var showFind: Bool

    @Environment(MemoryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var modal: MemoryModal?
    private var router: ShortcutRouter { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .center) {
                        DoddyWordmark()
                        Spacer()
                        Text("Your mate in\nyour pocket")
                            .font(.caption2).multilineTextAlignment(.trailing)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    JourneyHeading(eyebrow: "", title: "A little less\nto carry.",
                                   subtitle: "Save a detail.\nFind it when you need it.")
                    UploadedCharacterView(assetName: "UploadedDoddy_Sitting", height: 210)
                        .frame(maxWidth: .infinity)

                    if let problem = store.environment.storageProblem {
                        ProblemView(message: problem)
                    }

                    VStack(spacing: 12) {
                        Button { router.isVoicePresented = true } label: {
                            HStack { Text("Talk with Doddy"); Spacer(); Image(systemName: "waveform") }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!store.environment.capabilities.isAvailable(.voiceInput))
                        .accessibilityIdentifier("home.talk")

                        // Choose one layout rather than keeping off-screen copies
                        // of the same actions in ViewThatFits' accessibility tree.
                        if textSize.isAccessibilitySize {
                            VStack(spacing: 10) { saveAction; findAction }
                        } else {
                            HStack(spacing: 10) { saveAction; findAction }
                        }
                    }
                    Text("Only the things you choose to save.")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                    if router.setup.phase == .notStarted {
                        backTapCard
                    }

                    recent

                    Text("Doddy is an AI, not a person. Notes stay on this iPhone; while a conversation is open they and your last few conversations go to ElevenLabs so Doddy knows them. Reminders and other apps aren't built yet.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("home.status")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(Theme.canvas)
            .toolbar(.hidden, for: .navigationBar, .tabBar)
            .navigationDestination(for: UUID.self) { MemoryDetailView(memoryID: $0) }
            .sheet(item: $modal) { _ in CaptureView() }
        }
        .foregroundStyle(Theme.ink)
    }

    private var saveAction: some View {
        Button { modal = .capture } label: { HomeActionTile(title: "Save a detail", icon: "plus") }
            .buttonStyle(.plain).disabled(!store.isStorageAvailable).accessibilityIdentifier("home.save")
    }

    private var findAction: some View {
        Button { selectedTab = .memories; showFind = true } label: { HomeActionTile(title: "Find something", icon: "magnifyingglass") }
            .buttonStyle(.plain).accessibilityIdentifier("home.find")
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

private struct HomeActionTile: View {
    let title: String
    let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).accessibilityHidden(true)
            Text(title).font(.subheadline)
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Theme.separator, lineWidth: 1))
    }
}
