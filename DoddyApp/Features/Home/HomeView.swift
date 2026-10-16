import DoddyCore
import SwiftUI
import UIKit

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @Binding var showFind: Bool
    @Binding var path: [UUID]
    @Binding var voiceController: VoiceSessionController?
    @Binding var voiceStarting: Bool
    let openVoiceTranscript: (VoiceSessionController) -> Void

    @Environment(MemoryStore.self) private var store
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Right after the opening (ADR-225) Doddy is ready to talk: the listening pose is up and the
    /// buttons slide in. Absent in previews and tests.
    @Environment(OpeningModel.self) private var opening: OpeningModel?
    @State private var modal: MemoryModal?
    /// Doddy's idle breaths are playing (ADR-313).
    @State private var breathing = false
    /// The first visit of a morning waves instead of breathing (ADR-380).
    @State private var helloMotion: DoddyMotion = .idle
    /// He has sat down on his box after the breaths (ADR-323).
    @State private var seated = HomeIdle.sat
    /// The sit plays only right after the breaths; a redraw meanwhile doesn't cut it short (ADR-331).
    @State private var sitPlays = false
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false
    @State private var showAsk = false
    @State private var tool: HomeTool?
    /// Translate (ADR-215): the start sheet, and what the user chose on it.
    @State private var showTranslator = false
    @State private var translatorChoice: TranslatorSetup?
    /// First visit (ADR-326): until a conversation has really connected, Home keeps to Talk to
    /// Doddy and holds back the voice picker (ADR-443) and the Back Tap and Today cards.
    @AppStorage(PreferenceKey.hadFirstConversation) private var hadFirstConversation = false
    @AppStorage(PreferenceKey.voiceAgentID) private var voiceAgentID = VoiceConfig.developmentAgentID
    @AppStorage(PreferenceKey.voiceTokenServer) private var voiceTokenServer = ""
    @AppStorage(VoiceConnection.calendar.preferenceKey) private var calendarOn = false
    @AppStorage(VoiceConnection.reminders.preferenceKey) private var remindersOn = false
    @State private var showDataFlow = false
    private var router: ShortcutRouter { .shared }

    private var voiceMode: VoiceConnectionMode {
        VoiceConnectionMode.resolve(
            serverAddress: voiceTokenServer,
            accessCode: VoiceAccessCodeStore.read(),
            publicAgentID: voiceAgentID)
    }

    /// Once per launch, when Home appears without the opening (ADR-225): Doddy stands, breathes
    /// four times and sits down on his box (ADR-323). The first time Home shows on a morning he
    /// waves instead (ADR-380). Waits a moment first, so an opening that is about to start wins.
    /// The opening's hand-over still lands on the usual sitting picture.
    private func breatheOnce() async {
        guard !HomeIdle.played, !reduceMotion, !hideCharacterArt else { return }
        try? await Task.sleep(for: .seconds(0.6))
        guard !Task.isCancelled, !HomeIdle.played, opening?.play == nil, opening?.ready == nil, ready == nil else { return }
        HomeIdle.played = true
        helloMotion = HomeIdle.wavesThisMorning(now: .now) ? .wave : .idle
        breathing = true
        // The wave rests on the open hand a moment longer before he sits.
        try? await Task.sleep(for: .seconds(helloMotion.duration + (helloMotion == .wave ? 0.8 : 0.2)))
        sitPlays = true
        seated = true
        breathing = false
        HomeIdle.sat = true
    }

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
                    Group {
                        if let voiceController, voiceController.isLive {
                            VoiceDoddyView(art: voiceScreenArt(for: voiceController), height: 190)
                                .frame(height: 210, alignment: .bottom)
                        } else if breathing {
                            // Idle (ADR-313): he stands and breathes, on the sitting pose's floor; or
                            // waves (ADR-380), whose strip stands on the same floor (564/600).
                            DoddyMotionView(motion: helloMotion, height: 170)
                                .padding(.bottom, 31)
                                .frame(height: 210, alignment: .bottom)
                        } else if seated, ready == nil {
                            // Then he sits down on his box (ADR-323) and stays there this launch.
                            // Same scale and floor as the breaths (both strips' boxes end at 564/600).
                            DoddyMotionView(motion: .sit, height: 166, playing: sitPlays)
                                .padding(.bottom, 31)
                                .frame(height: 210, alignment: .bottom)
                        } else {
                            UploadedCharacterView(assetName: ready != nil ? "UploadedDoddy_Listening" : "UploadedDoddy_Sitting", height: 210)
                        }
                    }
                        // The opening lands Doddy exactly here, so it needs to know where "here" is.
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { [opening] rect in
                            Task { @MainActor in
                                opening?.homeArtBox = ScreenBox(centerX: rect.midX, centerY: rect.midY, height: rect.height)
                            }
                        }
                        // While the opening plays, its Doddy stands in for this one; when it ends,
                        // this one is in the same place, so nothing moves.
                        .opacity(opening?.play == nil ? 1 : 0)
                        .frame(maxWidth: .infinity)
                        .id(ready != nil)
                        .transition(.opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: ready != nil)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: breathing)
                        .task { await breatheOnce() }
                        // An opening (a later return) lands on the usual sitting picture: off the box.
                        .onChange(of: opening?.play == nil) { _, nothingPlaying in
                            if !nothingPlaying { seated = false; HomeIdle.sat = false }
                        }
                        // Doddy's room behind Doddy only, edge to edge; no text over it (ADR-308).
                        .background {
                            SceneryBackdrop(place: .home, height: 270, focus: 0.2)
                                .padding(.horizontal, -24)
                        }

                    if let voiceController {
                        HomeConversationPanel(
                            controller: voiceController,
                            isStarting: voiceStarting,
                            openTranscript: { openVoiceTranscript(voiceController) },
                            toggleMute: { Task { await voiceController.toggleMute() } },
                            endConversation: stopHomeConversation,
                            hideEndedConversation: { self.voiceController = nil },
                            openSettings: openSystemSettings)
                    }

                    if let problem = store.environment.storageProblem {
                        ProblemView(message: problem, showsDoddy: true)
                    }

                    // "Continue what I was saving" (ADR-362): opens the capture screen with it.
                    if let draft = UnfinishedNoteStore.shared.book.newest {
                        UnfinishedNoteCard(note: draft, more: UnfinishedNoteStore.shared.book.notes.count - 1) { modal = .capture }
                    }

                    VStack(spacing: 12) {
                        if voiceController?.isLive != true && !voiceStarting {
                            Button(action: startHomeConversation) {
                                HStack { Text("Talk to Doddy"); Spacer(); Image(systemName: "waveform") }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!store.environment.capabilities.isAvailable(.voiceInput))
                            .accessibilityIdentifier("home.talk")
                        }

                        // Who runs the voice, and OpenAI's model (ADR-442), once there has been a first
                        // conversation; before that it is one more choice ahead of talking (ADR-443).
                        // Settings › Voice has it from the start.
                        if hadFirstConversation {
                            VoiceProviderPicker(idPrefix: "home")
                        }

                        if !hadFirstConversation && store.environment.capabilities.isAvailable(.voiceInput) {
                            Text("Try saying: \u{201C}Remember the gate code is 4821.\u{201D} I'll ask before I keep anything.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("home.firstHint")
                        }

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
                        Group {
                            if textSize.isAccessibilitySize {
                                VStack(spacing: 10) { saveAction; findAction; focusAction; breatheAction }
                            } else {
                                VStack(spacing: 10) {
                                    HStack(spacing: 10) { saveAction; findAction }
                                    HStack(spacing: 10) { focusAction; breatheAction }
                                }
                            }
                        }
                    }
                    Text("Only the things you choose to save.")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity)

                    // Today only points to Settings until something is connected; on the first
                    // visit that is one more thing to read before talking (ADR-326).
                    if hadFirstConversation || calendarOn || remindersOn {
                        TodayCard(openSettings: { selectedTab = .settings })
                    }

                    // Back Tap exists only on iPhone (ADR-337), and waits for the first conversation (ADR-326).
                    if router.setup.phase == .notStarted, DeviceSupport.hasBackTap, hadFirstConversation {
                        backTapCard
                    }
                    HeyDoddyCard()
                    HomeAboutYouCard()

                    HomeRecentMemories()

                    // The longer summary is in Settings › Privacy (ADR-326).
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Doddy is an AI, not a person.")
                            .accessibilityIdentifier("home.status")
                        Button("What leaves this iPhone") { showDataFlow = true }
                            .accessibilityIdentifier("home.dataFlow")
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(Theme.canvas)
            .toolbar(.hidden, for: .navigationBar, .tabBar)
            .navigationDestination(for: UUID.self) { MemoryOrListView(id: $0) }
            .sheet(item: $modal) { _ in CaptureView() }
            .sheet(isPresented: $showDataFlow) { DataFlowSheet() }
            .sheet(item: $tool) { tool in
                switch tool {
                case .focus: FocusView()
                case .breathe: BreathingView()
                }
            }
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

    private var ready: OpeningReady? { opening?.ready }

    private func startHomeConversation() {
        guard store.environment.capabilities.isAvailable(.voiceInput), voiceController?.isLive != true,
              !voiceStarting else { return }
        let controller = VoiceSessionController(store: store)
        voiceController = controller
        voiceStarting = true
        Task {
            defer { voiceStarting = false }
            await controller.start(voiceMode, profile: profiles.profile, byWakeWord: false)
        }
    }

    private func stopHomeConversation() {
        guard let voiceController else { return }
        voiceStarting = false
        Task { await voiceController.stop() }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var saveAction: some View {
        Button { modal = .capture } label: { HomeActionTile(title: "Save a detail", icon: "plus") }
            .buttonStyle(TactileCardButtonStyle()).disabled(!store.isStorageAvailable).accessibilityIdentifier("home.save")
    }

    /// Focus timer and breathing (ADR-241, ADR-242); both show on the Dynamic Island.
    private var focusAction: some View {
        Button { tool = .focus } label: {
            HomeActionTile(title: FocusController.shared.session.map { $0.isOver ? "Focus" : "Focus · on" } ?? "Focus",
                           icon: "timer")
        }
        .buttonStyle(TactileCardButtonStyle()).accessibilityIdentifier("home.focus")
    }

    private var breatheAction: some View {
        Button { tool = .breathe } label: { HomeActionTile(title: "Breathe", icon: "wind") }
            .buttonStyle(TactileCardButtonStyle()).accessibilityIdentifier("home.breathe")
    }

    private var findAction: some View {
        Button { selectedTab = .memories; showFind = true } label: { HomeActionTile(title: "Find something", icon: "magnifyingglass") }
            .buttonStyle(TactileCardButtonStyle()).accessibilityIdentifier("home.find")
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
        return NSLocalizedString("A little less to carry.", comment: "")
    }
}

