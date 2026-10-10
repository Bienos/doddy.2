import DoddyCore
import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @Binding var showFind: Bool
    @Binding var path: [UUID]

    @Environment(MemoryStore.self) private var store
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var modal: MemoryModal?
    @State private var showAsk = false
    /// Translate (ADR-209): the start sheet, and what the user chose on it.
    @State private var showTranslator = false
    @State private var translatorChoice: TranslatorSetup?
    @AppStorage(PreferenceKey.shareProfileWithVoice) private var shareProfileWithVoice = false
    private var router: ShortcutRouter { .shared }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    DueRemindersView()

                    HStack(alignment: .center) {
                        DoddyWordmark()
                        Spacer()
                        Text("Your mate in\nyour pocket")
                            .font(.caption2).multilineTextAlignment(.trailing)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    // JourneyHeading's look, with the approved name when there is one.
                    VStack(alignment: .leading, spacing: 12) {
                        Text(greeting)
                            .font(.largeTitle.weight(.medium)).tracking(-1)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("home.greeting")
                        Text("Save a detail.\nFind it when you need it.")
                            .font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                    UploadedCharacterView(assetName: "UploadedDoddy_Sitting", height: 210)
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

                        Button { showAsk = true } label: {
                            HStack { Text("Ask Doddy"); Spacer(); Image(systemName: "text.bubble") }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(!store.environment.capabilities.isAvailable(.textAssistant))
                        .accessibilityIdentifier("home.ask")

                        Button { showTranslator = true } label: {
                            HStack { Text("Translate"); Spacer(); Image(systemName: "character.bubble") }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(!store.environment.capabilities.isAvailable(.voiceInput))
                        .accessibilityHint("Doddy translates between you and someone who speaks another language.")
                        .accessibilityIdentifier("home.translate")

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

                    TodayCard(openSettings: { selectedTab = .settings })

                    if router.setup.phase == .notStarted {
                        backTapCard
                    }
                    aboutYou

                    recent

                    Text("Doddy is an AI, not a person. Notes stay on this iPhone; while a conversation is open they and your last few conversations go to ElevenLabs so Doddy knows them. Typed questions go to Doddy's server and OpenAI only if you turn on Ask Doddy in Settings. Calendar, reminders and contacts stay off until you turn them on in Settings, and Today reads them on this iPhone only; Google Calendar reading is in Settings › Connected Apps.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("home.status")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(Theme.canvas)
            .toolbar(.hidden, for: .navigationBar, .tabBar)
            .navigationDestination(for: UUID.self) { MemoryOrListView(id: $0) }
            .sheet(item: $modal) { _ in CaptureView() }
            .fullScreenCover(isPresented: $showAsk) { AskView(openSettings: { selectedTab = .settings }) }
            // The conversation opens once the start sheet has gone away.
            .sheet(isPresented: $showTranslator, onDismiss: {
                if let choice = translatorChoice {
                    translatorChoice = nil
                    router.openTranslator(choice)
                }
            }) { TranslatorStartView(chosen: $translatorChoice) }
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
                Text(shareProfileWithVoice
                    ? "Doddy knows these in voice conversations. Change or forget them in Settings."
                    : "Change or forget these in Settings. Voice conversations don't use them unless you turn that on there.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(16)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
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
