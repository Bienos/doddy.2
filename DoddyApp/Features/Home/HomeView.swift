import DoddyCore
import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @Binding var showFind: Bool
    @Binding var path: [UUID]

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
    @AppStorage(PreferenceKey.shareProfileWithVoice) private var shareProfileWithVoice = false
    /// First visit (ADR-326): until a conversation has really connected, Home keeps to Talk to
    /// Doddy and holds back the voice picker (ADR-443) and the Back Tap and Today cards.
    @AppStorage(PreferenceKey.hadFirstConversation) private var hadFirstConversation = false
    @AppStorage(VoiceConnection.calendar.preferenceKey) private var calendarOn = false
    @AppStorage(VoiceConnection.reminders.preferenceKey) private var remindersOn = false
    @State private var showDataFlow = false
    private var router: ShortcutRouter { .shared }

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
                        if breathing {
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

                    if let problem = store.environment.storageProblem {
                        ProblemView(message: problem, showsDoddy: true)
                    }

                    VStack(spacing: 12) {
                        Button { router.isVoicePresented = true } label: {
                            HStack { Text("Talk to Doddy"); Spacer(); Image(systemName: "waveform") }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!store.environment.capabilities.isAvailable(.voiceInput))
                        .accessibilityIdentifier("home.talk")
                        .modifier(SlideIn(shown: buttonsShown, delay: 0))

                        // Who runs the voice, and OpenAI's model (ADR-442), once there has been a first
                        // conversation; before that it is one more choice ahead of talking (ADR-443).
                        // Settings › Voice has it from the start.
                        if hadFirstConversation {
                            VoiceProviderPicker(idPrefix: "home")
                                .modifier(SlideIn(shown: buttonsShown, delay: 0))
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
                        .modifier(SlideIn(shown: buttonsShown, delay: 0.07))

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
                        .modifier(SlideIn(shown: buttonsShown, delay: 0.14))
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
                    aboutYou

                    recent

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

    /// Hidden under the opening until its hand-over, then they slide in as Doddy jumps into
    /// place. Never hidden under Reduce Motion.
    private var buttonsShown: Bool {
        guard let opening, let play = opening.play else { return true }
        return play.reducedMotion || opening.handingOver
    }

    private var saveAction: some View {
        Button { modal = .capture } label: { HomeActionTile(title: "Save a detail", icon: "plus") }
            .buttonStyle(.plain).disabled(!store.isStorageAvailable).accessibilityIdentifier("home.save")
    }

    /// Focus timer and breathing (ADR-241, ADR-242); both show on the Dynamic Island.
    private var focusAction: some View {
        Button { tool = .focus } label: {
            HomeActionTile(title: FocusController.shared.session.map { $0.isOver ? "Focus" : "Focus · on" } ?? "Focus",
                           icon: "timer")
        }
        .buttonStyle(.plain).accessibilityIdentifier("home.focus")
    }

    private var breatheAction: some View {
        Button { tool = .breathe } label: { HomeActionTile(title: "Breathe", icon: "wind") }
            .buttonStyle(.plain).accessibilityIdentifier("home.breathe")
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
        return NSLocalizedString("A little less to carry.", comment: "")
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
                // "Ask me about it" (ADR-403): a conversation about that note; never on a private one.
                let privateNotes = PrivateNotesStore.current()
                let canTalk = store.environment.capabilities.isAvailable(.voiceInput)
                ForEach(store.memories.prefix(3)) { record in
                    HStack(spacing: 8) {
                        NavigationLink(value: record.id) {
                            MemoryRow(record: record)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        if canTalk && NoteQuestion.canAsk(about: record, privateNotes: privateNotes) {
                            Button { router.askAboutNote(record.id) } label: {
                                Image(systemName: "waveform.circle")
                                    .font(.title2)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accentText)
                            .accessibilityLabel("Ask me about it")
                            .accessibilityIdentifier("home.recent.ask")
                        }
                    }
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

/// A button's entrance after the opening: up from just below, with a little bounce, each a
/// beat after the one before. Instant (never hidden) under Reduce Motion, where `shown` stays true.
private struct SlideIn: ViewModifier {
    let shown: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 28)
            .animation(.spring(duration: 0.5, bounce: 0.3).delay(delay), value: shown)
    }
}

private enum HomeTool: String, Identifiable {
    case focus, breathe
    var id: String { rawValue }
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

/// Whether Home's idle breaths have played in this launch (ADR-313).
@MainActor
enum HomeIdle {
    static var played = false
    /// He sat down on his box this launch (ADR-323): later visits show him seated, without replaying.
    static var sat = false

    /// The day Home last waved (ADR-380), on this iPhone only. Not a note.
    static let waveDayKey = "home.lastWaveDay"

    /// True the first time it is asked on a morning; it then records the day (`MorningWave`).
    static func wavesThisMorning(now: Date, defaults: UserDefaults = .standard) -> Bool {
        guard let day = MorningWave.dayToRecord(now: now, lastWaveDay: defaults.string(forKey: waveDayKey)) else { return false }
        defaults.set(day, forKey: waveDayKey)
        return true
    }
}

/// Settings › Privacy › What leaves this iPhone, opened from Home's footer (ADR-326).
private struct DataFlowSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DataFlowView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// "Hey Doddy" with one tap (ADR-328): offered once, after a few conversations that really
/// connected, and only when one tap is enough (`HeyDoddyOffer`). Turn on and Not now both end the
/// offer for good. After Turn on it shows the listener's own state, never a "Listening" it isn't.
private struct HeyDoddyCard: View {
    @AppStorage(PreferenceKey.connectedConversations) private var conversations = 0
    @AppStorage(PreferenceKey.heyDoddyOn) private var heyDoddyOn = false
    @AppStorage(PreferenceKey.heyDoddyOfferDone) private var offerDone = false
    @State private var listener = WakeWordListener.shared
    /// Read once: the Keychain isn't read again on every redraw of Home.
    @State private var oneTapReady = WakeOneTapSetup.isReady
    @State private var isTurningOn = false
    @State private var showsResult = false

    var body: some View {
        if showsResult {
            result
        } else if HeyDoddyOffer.shouldOffer(conversations: conversations, heyDoddyOn: heyDoddyOn,
                                            dismissed: offerDone, oneTapReady: oneTapReady) {
            offer
        }
    }

    private var offer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Talk without tapping")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Say \u{201C}Hey Doddy\u{201D} and I'll answer. I listen for it on this iPhone, with iOS's orange microphone dot showing, until you stop me. It uses some battery.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 12) {
                Button {
                    isTurningOn = true
                    offerDone = true
                    Task {
                        await listener.turnOn()
                        isTurningOn = false
                        showsResult = true
                    }
                } label: {
                    if isTurningOn { Text("Turning on…") } else { Text("Turn on") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isTurningOn)
                .accessibilityIdentifier("home.heyDoddy.turnOn")
                Button("Not now") { offerDone = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isTurningOn)
                    .accessibilityIdentifier("home.heyDoddy.notNow")
            }
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hey Doddy")
                .font(.headline)
            Text(listener.keyProblem ?? listener.state.summary)
                .font(.subheadline)
                .foregroundStyle(listener.keyProblem == nil ? Theme.secondaryText : Theme.error)
                .accessibilityIdentifier("home.heyDoddy.status")
            Text("Change it in Settings \u{203A} Hey Doddy.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
    }
}

