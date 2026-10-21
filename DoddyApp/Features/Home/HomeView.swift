import DoddyCore
import SwiftUI

/// Home (ADR-545): a calm screen after the owner's "I'm here" mockup. Doddy sits cross-legged in
/// the middle and is the Talk button; under him an orange dot, "I'm here." and "Tap Doddy to talk";
/// at the bottom Type (Ask Doddy), Memories (a sheet) and + (Save a detail). Everything else Home
/// used to list lives in the ••• menu. Cards appear only while something needs the user (a due
/// reminder, a storage problem, an unfinished note, a one-time offer they can dismiss).
struct HomeView: View {
    @Binding var selectedTab: AppTab
    @Binding var showFind: Bool
    @Binding var path: [UUID]

    @Environment(MemoryStore.self) private var store
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Right after the opening (ADR-225) Doddy is ready to talk: the listening pose is up and the
    /// bar slides in. Absent in previews and tests.
    @Environment(OpeningModel.self) private var opening: OpeningModel?
    @State private var modal: MemoryModal?
    /// The first visit of a morning waves before he sits (ADR-380).
    @State private var waving = false
    /// A tap on Doddy: he hops and perks up (listening pose) as the conversation opens.
    @State private var perking = false
    @State private var tapHops = 0
    @State private var showMemories = false
    @State private var showAsk = false
    @State private var tool: HomeTool?
    /// Translate (ADR-215): the start sheet, and what the user chose on it.
    @State private var showTranslator = false
    @State private var translatorChoice: TranslatorSetup?
    @State private var showDataFlow = false
    @State private var showCapabilities = false
    @State private var showToday = false
    /// Tasks handed to Doddy (ADR-566): the list and each result card.
    @State private var showErrands = false
    @State private var showVoicePicker = false
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false
    /// First visit (ADR-326): until a conversation has really connected, Home keeps to talking and
    /// holds back the voice picker (ADR-443) and the Back Tap and Today offers.
    @AppStorage(PreferenceKey.hadFirstConversation) private var hadFirstConversation = false
    /// For when the "Open Doddy faster" card comes back after "Later" (ADR-559).
    @AppStorage(PreferenceKey.connectedConversations) private var connectedConversations = 0
    @AppStorage(VoiceConnection.calendar.preferenceKey) private var calendarOn = false
    @AppStorage(VoiceConnection.reminders.preferenceKey) private var remindersOn = false
    @AppStorage(PreferenceKey.memoriesShowsLists) private var memoriesShowsLists = false
    private var router: ShortcutRouter { .shared }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        header
                        notices
                        Spacer(minLength: 24)
                        character
                        status
                            .opacity(showMemories ? 0 : 1)
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 24)
                    // Centred when it fits; scrolls when cards or large text make it taller.
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                // Motion v2 (ADR-560): his eyes follow a finger anywhere on Home. Simultaneous, so
                // taps and scrolling work as before; a finger on him is his touch area's.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged {
                            DoddyDirector.shared.fingerElsewhere(x: Double($0.location.x), y: Double($0.location.y))
                        }
                        .onEnded { _ in DoddyDirector.shared.fingerElsewhereLifted() }
                )
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
                    .opacity(showMemories ? 0 : 1)
                    .modifier(SlideIn(shown: buttonsShown, delay: 0))
            }
            .background(Theme.canvas.ignoresSafeArea())
            .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.2), value: showMemories)
            .toolbar(.hidden, for: .navigationBar, .tabBar)
            .navigationDestination(for: UUID.self) { MemoryOrListView(id: $0) }
            .sheet(item: $modal) { _ in CaptureView() }
            .sheet(isPresented: $showDataFlow) { DataFlowSheet() }
            .sheet(isPresented: $showErrands) { ErrandsView() }
            .sheet(isPresented: $showCapabilities) { CapabilitiesSheet() }
            .sheet(isPresented: $showMemories) {
                HomeMemoriesSheet(
                    openNotes: { leaveForMemories(lists: false) },
                    openLists: { leaveForMemories(lists: true) },
                    openFind: { showMemories = false; selectedTab = .memories; showFind = true },
                    openSettings: { showMemories = false; selectedTab = .settings },
                    askAbout: { id in
                        // The conversation opens once the sheet has gone.
                        showMemories = false
                        Task {
                            try? await Task.sleep(for: .seconds(0.45))
                            router.askAboutNote(id)
                        }
                    })
            }
            .sheet(isPresented: $showToday) {
                HomeTodaySheet(openSettings: { showToday = false; selectedTab = .settings })
            }
            .sheet(isPresented: $showVoicePicker) { HomeVoiceSheet() }
            .sheet(item: $tool) { tool in
                switch tool {
                case .focus: FocusView()
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
        // Motion v2: each sheet and cover from Home hides him in the frame it starts. Ask isn't
        // one of them (MV4: its cover carries him up on its composer), and the Memories sheet
        // isn't either: the calm Home lifts him above it (ADR-545), and he rides with the box.
        .coversDoddy(modal != nil || showDataFlow || showCapabilities || tool != nil || showTranslator || showToday || showVoicePicker)
        // A note pushed over Home covers him where he stands.
        .onChange(of: path.count, initial: true) { _, depth in
            DoddyDirector.shared.pageChanged(on: .home, open: depth > 0, detail: false)
        }
    }

    // MARK: Top

    private var header: some View {
        ZStack {
            DoddyWordmark()
            HStack {
                Spacer()
                moreMenu
            }
        }
        .frame(minHeight: 44)
        .padding(.top, 8)
    }

    /// What used to be listed down Home (ADR-545): the tools, the voice picker, the other tabs and
    /// the privacy page. The AI disclosure heads it.
    private var moreMenu: some View {
        Menu {
            Section {
                Button { showTranslator = true } label: { Label("Translate", systemImage: "character.bubble") }
                    .disabled(!canTalk)
                    .accessibilityHint("Doddy translates between you and someone who speaks another language.")
                    .accessibilityIdentifier("home.translate")
                Button { selectedTab = .memories; showFind = true } label: { Label("Find something", systemImage: "magnifyingglass") }
                    .accessibilityIdentifier("home.find")
                // Tasks handed to Doddy's background worker (ADR-566).
                Button { showErrands = true } label: { Label("Tasks", systemImage: "checklist") }
                    .accessibilityIdentifier("home.tasks")
                Button { tool = .focus } label: {
                    if FocusController.shared.session.map({ !$0.isOver }) ?? false {
                        Label("Focus · on", systemImage: "timer")
                    } else {
                        Label("Focus", systemImage: "timer")
                    }
                }
                .accessibilityIdentifier("home.focus")
                // Today only points to Settings until something is connected (ADR-326).
                if hadFirstConversation || calendarOn || remindersOn {
                    Button { showToday = true } label: { Label("Today", systemImage: "calendar") }
                        .accessibilityIdentifier("home.today")
                }
                // Who runs the voice (ADR-442), once there has been a first conversation (ADR-443).
                if hadFirstConversation {
                    Button { showVoicePicker = true } label: { Label("Voice", systemImage: "waveform") }
                        .accessibilityIdentifier("home.voice")
                }
            } header: {
                Text("Doddy is an AI, not a person.")
            }
            Section {
                Button { selectedTab = .memories } label: { Label("Memories", systemImage: "book.closed") }
                    .accessibilityIdentifier("home.menu.memories")
                Button { selectedTab = .settings } label: { Label("Settings", systemImage: "slider.horizontal.3") }
                    .accessibilityIdentifier("home.menu.settings")
                // What is built and what isn't, from the capability catalog (T35/T42, ADR-195, ADR-548).
                Button { showCapabilities = true } label: { Label("What I can do", systemImage: "sparkles") }
                    .accessibilityIdentifier("home.capabilities")
                Button { showDataFlow = true } label: { Label("What leaves this iPhone", systemImage: "lock.shield") }
                    .accessibilityIdentifier("home.dataFlow")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .foregroundStyle(Theme.ink)
        .accessibilityLabel("More")
        .accessibilityIdentifier("home.more")
    }

    /// Only what needs the user now. Each card hides itself when there is nothing to show.
    private var notices: some View {
        VStack(spacing: 12) {
            DueRemindersView()
            if let problem = store.environment.storageProblem {
                ProblemView(message: problem, showsDoddy: true, onDoddysScreen: true)
            }
            // "Continue what I was saving" (ADR-362): opens the capture screen with it.
            if let draft = UnfinishedNoteStore.shared.book.newest {
                UnfinishedNoteCard(note: draft, more: UnfinishedNoteStore.shared.book.notes.count - 1) { modal = .capture }
            }
            // A task Doddy finished in the background since the user last looked (ADR-566).
            if let finished = ErrandsModel.shared.newestUnseen {
                errandFinishedCard(finished)
            }
            if profiles.shouldOfferIntroduction {
                getToKnowCard
            }
            // Back Tap exists only on iPhone (ADR-337), and waits for the first conversation (ADR-326).
            // After "Later" it comes back once, three conversations on; never once a way is in use (ADR-559).
            if router.setup.cardDue(connectedConversations: connectedConversations), DeviceSupport.hasBackTap, hadFirstConversation {
                backTapCard
            }
        }
        .padding(.top, 12)
    }

    // MARK: Doddy

    /// Doddy is the Talk button. The opening (ADR-225) lands him here, so this reports where "here" is.
    private var character: some View {
        Button(action: talk) {
            Group {
                if ready != nil {
                    // The opening's hand-over lands on this picture, in this place.
                    UploadedCharacterView(assetName: "UploadedDoddy_Listening", height: 210)
                } else if DoddyDirector.shared.isActive {
                    // Motion v2: this picture becomes the persistent Doddy, drawn on the stage
                    // overlaid below (the same 210 pt box, so nothing else on Home moves). A tap
                    // anywhere in the box still talks; a touch on him leans him and a tap on him
                    // talks (MV5).
                    Color.clear
                } else if waving {
                    // The first visit of a morning waves (ADR-380), then he sits.
                    DoddyMotionView(motion: .wave, height: 190)
                } else {
                    AliveDoddy(pose: perking ? .listening : .crosslegged, height: 190, hopTrigger: tapHops)
                }
            }
            .frame(height: 210, alignment: .bottom)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(DoddyPressStyle())
        .disabled(!canTalk)
        .accessibilityLabel("Talk to Doddy")
        .accessibilityIdentifier("home.talk")
        // Motion v2: his stage is the picture's floor, 31 pt above the box's bottom. It is laid over
        // the button, not inside it: a button is one accessibility element and would swallow the
        // stage's frame (hosted run 39454393739 read the whole 210 pt box as "the stage"). No visible
        // line, because the calm Home's mockup has none.
        .overlay(alignment: .bottom) {
            if DoddyDirector.shared.isActive && ready == nil {
                StageLine(visible: false).padding(.bottom, 31)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { [opening] rect in
            Task { @MainActor in
                opening?.homeArtBox = ScreenBox(centerX: rect.midX, centerY: rect.midY, height: rect.height)
            }
        }
        // While the opening plays, its Doddy stands in for this one; when it ends, this one is in
        // the same place, so nothing moves.
        .opacity(opening?.play == nil ? 1 : 0)
        // With Memories open he moves up above the sheet.
        .offset(y: showMemories ? -120 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: ready != nil)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: waving)
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.3), value: perking)
        .task { await waveOnce() }
    }

    private var status: some View {
        VStack(spacing: 12) {
            ReadyDot()
                .padding(.top, 14)
            Text(greeting)
                .font(.largeTitle.weight(.bold)).tracking(-1)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home.greeting")
            Group {
                if canTalk {
                    Text("Tap Doddy to talk")
                } else {
                    Text("Talking isn't available right now. You can type instead.")
                }
            }
            .font(.title3)
            .foregroundStyle(Theme.secondaryText)
            .multilineTextAlignment(.center)
            if !hadFirstConversation && canTalk {
                Text("Try saying: \u{201C}Remember the gate code is 4821.\u{201D} I'll ask before I keep anything.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .accessibilityIdentifier("home.firstHint")
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Bottom

    private var bottomBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                Button { showAsk = true } label: {
                    Label("Type", systemImage: "keyboard")
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DoddyPressStyle())
                .disabled(!store.environment.capabilities.isAvailable(.textAssistant))
                .accessibilityIdentifier("home.ask")
                Rectangle().fill(Theme.separator).frame(width: 1, height: 24)
                Button { showMemories = true } label: {
                    Label("Memories", systemImage: "book.closed")
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DoddyPressStyle())
                .accessibilityIdentifier("home.memories")
            }
            .font(.body.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(minHeight: 56)
            .background(Theme.quietSurface, in: Capsule())
            Button { modal = .capture } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.canvas)
                    .frame(width: 56, height: 56)
                    .background(Theme.ink, in: Circle())
            }
            .buttonStyle(DoddyPressStyle())
            .disabled(!store.isStorageAvailable)
            .accessibilityLabel("Save a detail")
            .accessibilityIdentifier("home.save")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private var canTalk: Bool { store.environment.capabilities.isAvailable(.voiceInput) }

    /// He hops and perks up, then the conversation opens. At once under Reduce Motion or with his
    /// pictures hidden.
    private func talk() {
        guard canTalk else { return }
        guard !reduceMotion, !hideCharacterArt, ready == nil else {
            router.isVoicePresented = true
            return
        }
        tapHops &+= 1
        perking = true
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            router.isVoicePresented = true
            try? await Task.sleep(for: .seconds(0.8))
            perking = false
        }
    }

    private func leaveForMemories(lists: Bool) {
        showMemories = false
        memoriesShowsLists = lists
        selectedTab = .memories
    }

    /// Once per launch, when Home appears without the opening: the first time on a morning he waves
    /// (ADR-380), then sits. Waits a moment first, so an opening that is about to start wins.
    private func waveOnce() async {
        // Motion v2: the one persistent Doddy has his own daily welcome (ADR-555).
        guard !HomeIdle.played, !reduceMotion, !hideCharacterArt, !DoddyDirector.shared.isActive else { return }
        try? await Task.sleep(for: .seconds(0.6))
        guard !Task.isCancelled, !HomeIdle.played, opening?.play == nil, ready == nil else { return }
        HomeIdle.played = true
        guard HomeIdle.wavesThisMorning(now: .now) else { return }
        waving = true
        // The wave rests on the open hand a moment before he sits.
        try? await Task.sleep(for: .seconds(DoddyMotion.wave.duration + 0.8))
        waving = false
    }

    private var ready: OpeningReady? { opening?.ready }

    /// Hidden under the opening until its hand-over, then they slide in as Doddy jumps into
    /// place. Never hidden under Reduce Motion.
    private var buttonsShown: Bool {
        guard let opening, let play = opening.play else { return true }
        return play.reducedMotion || opening.handingOver
    }

    /// Uses only the approved name; without one, "I'm here."
    private var greeting: String {
        if let name = profiles.profile.value(.name) { return "Hi, \(name)." }
        return NSLocalizedString("I'm here.", comment: "")
    }

    /// "Done: Rzym, 7 dni": opens Tasks. Its words come from this iPhone's store, never from the push.
    private func errandFinishedCard(_ errand: StoredErrand) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { showErrands = true } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Label(errand.state == .done
                          ? String(format: NSLocalizedString("Done: %@", comment: ""), errand.title)
                          : String(format: NSLocalizedString("Couldn't finish: %@", comment: ""), errand.title),
                          systemImage: errand.state == .done ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                    Group {
                        if errand.state == .done { Text("See what Doddy found.") } else { Text("See why.") }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.errandFinished")

            Button { ErrandsModel.shared.markSeen(errand.id) } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not now")
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: One-time offers (unchanged from the old Home)

    /// A small, dismissible invitation. It never blocks Home or starts voice, and the answer
    /// flow opens only after the user taps it.
    private var getToKnowCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                Task { await profiles.reopenIntroduction() }
            } label: {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Let's get to know each other", systemImage: "bubble.left.and.bubble.right")
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                    Text("Two quick questions. Skip either one. Change your answers anytime.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                    if let problem = profiles.progressSaveProblem {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(Theme.error)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose what Doddy calls you and how he should respond. You can skip or edit later.")
            .accessibilityIdentifier("home.getToKnow")

            Button {
                Task { await profiles.finishIntroduction(saved: false) }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not now")
            .accessibilityIdentifier("home.getToKnow.dismiss")
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    /// Offered once; "Later" hides it (Settings can reopen the guide). Never shown as done
    /// unless the user reported a successful tap test.
    private var backTapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Open Doddy faster")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Double-tap the back of your iPhone, press a button or just ask Siri. Pick a way; it takes about a minute.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 12) {
                Button("Show me the ways") { router.isSetupPresented = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("home.backTap.setup")
                Button("Later") { router.setup.send(.deferSetup) }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("home.backTap.later")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Doddy, alive

/// Doddy at rest on Home (ADR-545): one of the owner's pack poses, never redrawn. He breathes (a
/// slow rise anchored at his feet), sways a little, and every so often gives a small hop; a tap
/// hops him too. Still under Reduce Motion, with his pictures hidden, or with the app in the
/// background. The pictures are single drawings, so he doesn't blink or move his face.
private struct AliveDoddy: View {
    let pose: IslandPose
    let height: CGFloat
    let hopTrigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false
    @State private var idleHops = 0
    @State private var start = Date()

    private var still: Bool { reduceMotion || hideCharacterArt || scenePhase != .active }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { context in
            let t = still ? 0 : context.date.timeIntervalSince(start)
            // 0…1, one breath every 3.6 s; and a slow sway, −1…1 every 9 s.
            let breath = (1 - cos(t * 2 * .pi / 3.6)) / 2
            let sway = sin(t * 2 * .pi / 9)
            WholeDoddyView(pose: pose, height: height)
                .id(pose)
                .transition(.opacity)
                .scaleEffect(x: 1 - breath * 0.008, y: 1 + breath * 0.022, anchor: .bottom)
                .rotationEffect(.degrees(sway * 1.4), anchor: .bottom)
        }
        .keyframeAnimator(initialValue: Hop(), trigger: hopTrigger &+ idleHops) { content, hop in
            content
                .scaleEffect(x: hop.stretchX, y: hop.stretchY, anchor: .bottom)
                .offset(y: hop.lift)
        } keyframes: { _ in
            KeyframeTrack(\.lift) {
                CubicKeyframe(0, duration: 0.1)
                CubicKeyframe(-16, duration: 0.18)
                SpringKeyframe(0, duration: 0.42, spring: .bouncy)
            }
            KeyframeTrack(\.stretchY) {
                CubicKeyframe(0.93, duration: 0.1)
                CubicKeyframe(1.05, duration: 0.18)
                SpringKeyframe(1, duration: 0.42, spring: .bouncy)
            }
            KeyframeTrack(\.stretchX) {
                CubicKeyframe(1.06, duration: 0.1)
                CubicKeyframe(0.97, duration: 0.18)
                SpringKeyframe(1, duration: 0.42, spring: .bouncy)
            }
        }
        .task(id: still) {
            guard !still else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 8...13)))
                guard !Task.isCancelled else { return }
                idleHops &+= 1
            }
        }
    }
}

private struct Hop {
    var lift: CGFloat = 0
    var stretchX: CGFloat = 1
    var stretchY: CGFloat = 1
}

/// The orange dot under Doddy: a slow pulse that says he's there. Still under Reduce Motion.
private struct ReadyDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(Theme.orangeCue)
            .frame(width: 12, height: 12)
            .phaseAnimator(reduceMotion ? [false] : [false, true]) { dot, up in
                dot.scaleEffect(up ? 1.3 : 1).opacity(up ? 0.65 : 1)
            } animation: { _ in .easeInOut(duration: 1.2) }
            .accessibilityHidden(true)
    }
}

/// Buttons on the new Home shrink a touch while pressed.
private struct DoddyPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Sheets from Home

/// Memories from Home (ADR-545): what Doddy knows about you, and the ways into your notes and
/// lists. Notes, lists and search open the Memories tab, where the real screens are.
private struct HomeMemoriesSheet: View {
    let openNotes: () -> Void
    let openLists: () -> Void
    let openFind: () -> Void
    let openSettings: () -> Void
    let askAbout: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(MemoryStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Memories")
                            .font(.largeTitle.weight(.bold)).tracking(-0.8)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("home.memories.close")
                    }
                    Button(action: openFind) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").accessibilityHidden(true)
                            Text("Search your memories").foregroundStyle(Theme.secondaryText)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.memories.search")
                    VStack(spacing: 0) {
                        NavigationLink { HomeAboutYouView() } label: { row(Text("About you"), icon: "person") }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home.memories.about")
                        Divider()
                        Button(action: openNotes) { row(Text("Saved details"), icon: "text.book.closed") }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home.memories.notes")
                        Divider()
                        Button(action: openLists) { row(Text("Lists"), icon: "checklist") }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home.memories.lists")
                    }
                    Button("Manage what Doddy remembers", action: openSettings)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("home.memories.manage")
                    recent
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .background(Theme.canvas)
            .toolbar(.hidden, for: .navigationBar)
        }
        .foregroundStyle(Theme.ink)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(Theme.canvas)
    }

    /// The three newest notes (they used to be on Home), each with "Ask me about it" (ADR-403),
    /// never on a private one.
    @ViewBuilder
    private var recent: some View {
        if !store.memories.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recently saved")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                let privateNotes = PrivateNotesStore.current()
                let canTalk = store.environment.capabilities.isAvailable(.voiceInput)
                ForEach(store.memories.prefix(3)) { record in
                    HStack(spacing: 8) {
                        NavigationLink { MemoryOrListView(id: record.id) } label: {
                            MemoryRow(record: record)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        if canTalk && NoteQuestion.canAsk(about: record, privateNotes: privateNotes) {
                            Button { askAbout(record.id) } label: {
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
            .padding(.top, 8)
        } else if store.hasLoaded {
            Text("Nothing saved yet. You choose what stays.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 8)
        }
    }

    private func row(_ title: Text, icon: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .accessibilityHidden(true)
            title.font(.body.weight(.medium))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }
}

/// What the user approved in the introduction, shown back plainly (it used to sit on Home).
/// Nothing is invented when the profile is empty.
private struct HomeAboutYouView: View {
    @Environment(ProfileStore.self) private var profiles
    @AppStorage(PreferenceKey.shareProfileWithVoice) private var shareProfileWithVoice = false

    var body: some View {
        let profile = profiles.profile
        let shown = [ProfileKey.context, .help, .style].filter { profile.value($0) != nil }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if shown.isEmpty {
                    Text("You haven't told me about yourself yet. You can, any time, in Settings.")
                        .foregroundStyle(Theme.secondaryText)
                } else {
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
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.canvas)
        .navigationTitle("About you")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Today (it used to be a card on Home), from the ••• menu.
private struct HomeTodaySheet: View {
    let openSettings: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                TodayCard(openSettings: openSettings)
                    .padding(24)
            }
            .background(Theme.canvas)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Who runs the voice, and OpenAI's model (ADR-442), from the ••• menu. Settings › Voice has the
/// same picker.
private struct HomeVoiceSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VoiceProviderPicker(idPrefix: "home")
                Spacer()
            }
            .padding(24)
            .background(Theme.canvas)
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// The bar's entrance after the opening: up from just below, with a little bounce. Instant
/// (never hidden) under Reduce Motion, where `shown` stays true.
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
    case focus
    var id: String { rawValue }
}

/// Whether Home's once-a-launch greeting has played (ADR-313, ADR-380).
@MainActor
enum HomeIdle {
    static var played = false

    /// The day Home last waved (ADR-380), on this iPhone only. Not a note.
    static let waveDayKey = "home.lastWaveDay"

    /// True the first time it is asked on a morning; it then records the day (`MorningWave`).
    static func wavesThisMorning(now: Date, defaults: UserDefaults = .standard) -> Bool {
        guard let day = MorningWave.dayToRecord(now: now, lastWaveDay: defaults.string(forKey: waveDayKey)) else { return false }
        defaults.set(day, forKey: waveDayKey)
        return true
    }
}

/// The newest unfinished note on Home (ADR-362): Continue opens it on the capture screen; Discard
/// removes it after asking. It is a draft, not a note.
private struct UnfinishedNoteCard: View {
    let note: UnfinishedNote
    let more: Int
    let onContinue: () -> Void
    @State private var confirmDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Unfinished note", systemImage: "doc.badge.clock").font(.headline)
            Text(verbatim: note.preview())
                .lineLimit(2)
            Text(String(format: NSLocalizedString("Not saved yet · last changed %@", comment: ""),
                        note.updatedAt.formatted(date: .abbreviated, time: .shortened)))
                .font(.caption).foregroundStyle(Theme.secondaryText)
            if more > 0 {
                Text(String(format: NSLocalizedString("%lld more unfinished notes; each opens when you start a new note.", comment: ""), more))
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            HStack(spacing: 12) {
                Button(action: onContinue) {
                    HStack { Text("Continue"); Spacer(); Image(systemName: "square.and.pencil") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("home.unfinishedNote.continue")
                Button("Discard") { confirmDiscard = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("home.unfinishedNote")
        .confirmationDialog("Discard this unfinished note?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { UnfinishedNoteStore.shared.remove(id: note.id) }
            Button("Keep it", role: .cancel) {}
        } message: { Text("It was never saved, so it can't be brought back.") }
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
