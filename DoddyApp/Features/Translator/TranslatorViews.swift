import DoddyCore
import SwiftUI

// Translator mode screens (ADR-215), after the "Doddy Translator" canvas: start (1), face to face
// (4, 5, 6, 7, 8), listen only (6b) and the end (9). Their half shows their language's own lines;
// the owner's half uses the owner's language for the translated text and English for the app.

/// Face to face or listen only, shown in place of the transcript while translator mode is on.
struct TranslatorScreen: View {
    let controller: VoiceSessionController
    let session: TranslatorSession

    var body: some View {
        switch session.setup.kind {
        case .faceToFace: faceToFace
        case .listen: listenOnly
        }
    }

    // MARK: Face to face

    private var faceToFace: some View {
        VStack(spacing: 0) {
            theirHalf
                .rotationEffect(.degrees(180))
                .frame(maxHeight: .infinity)
            middleBar
            ownerHalf
                .frame(maxHeight: .infinity)
        }
    }

    private var theirHalf: some View {
        let other = session.setup.other
        return VStack(alignment: .leading, spacing: 10) {
            Text(other?.aiLabel ?? "AI translation · may contain mistakes")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            if session.careful != nil, let other {
                Text(other.careful)
                    .font(.footnote.weight(.semibold))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
            }
            ScrollView {
                if let turn = session.latest(.toOther) {
                    Text(turn.text)
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("translator.theirLine")
                }
            }
            facts(session.latest(.toOther)?.facts ?? [])
            if controller.holdToTalk, let other {
                holdButton(other.holdToTalk, side: .toOther)
            }
        }
        .padding(20)
        // Arabic, Persian, Urdu and Hebrew read from the right: their lines start there (12 Nov 2026).
        .environment(\.layoutDirection, other?.isRightToLeft == true ? .rightToLeft : .leftToRight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Their half, facing them")
    }

    private var middleBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(listeningColor)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(statusText)
                .font(.footnote)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(session.setup.codesText)
                .font(.footnote.weight(.semibold))
            Button("End") { Task { await controller.endTranslating() } }
                .buttonStyle(SecondaryButtonStyle(tint: Theme.error))
                .fixedSize()
                .accessibilityIdentifier("translator.end")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.quietSurface)
    }

    private var ownerHalf: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let careful = session.careful {
                Label(careful.banner, systemImage: "exclamationmark.shield")
                    .font(.footnote)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("translator.careful")
            }
            if session.setup.other == nil {
                Text("Let them say something first, so Doddy can hear their language.")
                    .font(.headline)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let aside = session.latestAside {
                        asideCard(aside)
                    } else if let turn = session.latest(.toOwner) {
                        Text(turn.text)
                            .font(.title2.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("translator.ownerLine")
                        if let original = turn.original {
                            DisclosureGroup("Show what they said") {
                                Text(original)
                                    .font(.callout)
                                    .foregroundStyle(Theme.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.footnote)
                        }
                    }
                    if let said = session.latest(.toOther) {
                        Text(verbatim: String(format: NSLocalizedString("Doddy said to them: %@", comment: ""), said.text))
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            facts(session.latest(.toOwner)?.facts ?? [])
            HStack(spacing: 8) {
                Button { Task { await controller.sayTranslationAgain() } } label: {
                    Label("Say it again", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
                Button { Task { await controller.toggleMute() } } label: {
                    Label(controller.isMuted && !controller.holdToTalk ? "Resume" : "Pause",
                          systemImage: controller.isMuted && !controller.holdToTalk ? "play" : "pause")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(controller.holdToTalk)
            }
            Toggle("Noisy place: hold to talk", isOn: Binding(
                get: { controller.holdToTalk },
                set: { on in Task { await controller.setHoldToTalk(on) } }))
                .font(.footnote)
                .accessibilityHint("Only the side whose button is held is heard and translated.")
            if controller.holdToTalk {
                holdButton(session.setup.owner.holdToTalk, side: .toOwner)
            }
        }
        .padding(20)
    }

    private func asideCard(_ aside: TranslatorTurn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Only for you · not translated")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            if let original = aside.original {
                Text(original).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            Text(aside.text).font(.body)
            if session.setup.other != nil {
                Button("Say it to them") { Task { await controller.sayAsideToThem() } }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityHint("Doddy says his suggestion to them, in their language.")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("translator.aside")
    }

    private func holdButton(_ title: String, side: TranslatorDirection) -> some View {
        let held = controller.heldSide == side
        return Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(held ? Theme.confirmed.opacity(0.25) : Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.ink, lineWidth: held ? 2 : 1))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if controller.heldSide != side { Task { await controller.beginHold(side) } } }
                .onEnded { _ in Task { await controller.endHold() } })
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(held ? "Held" : "")
    }

    // MARK: Listen only

    private var listenOnly: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Listening for you").font(.headline)
                    Text(session.setup.pairText).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Button("End") { Task { await controller.endTranslating() } }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.error))
                    .fixedSize()
                    .accessibilityIdentifier("translator.end")
            }
            Label("Doddy doesn't speak to anyone here. Use it for a guide, a talk or an announcement, not someone's private conversation.", systemImage: "ear")
                .font(.footnote)
                .padding(10)
                .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
            if let careful = session.careful {
                Label(careful.banner, systemImage: "exclamationmark.shield").font(.footnote)
            }
            Toggle("Read aloud", isOn: Binding(get: { controller.readsAloud }, set: { controller.setReadAloud($0) }))
                .accessibilityIdentifier("translator.readAloud")
            Text(controller.readsAloud
                 ? "Doddy says each translation to you. Earphones keep it to you."
                 : "Silent: read the lines below. Doddy's voice is off on this iPhone only.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
            if let problem = controller.readAloudProblem {
                Label(problem, systemImage: "speaker.slash").font(.footnote).foregroundStyle(Theme.error)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(session.turns) { turn in
                            VStack(alignment: .leading, spacing: 4) {
                                if turn.route == .aside {
                                    Text("Only for you").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                                }
                                Text(turn.text).font(.body.weight(.semibold))
                                if let original = turn.original {
                                    Text(original).font(.footnote).foregroundStyle(Theme.secondaryText)
                                }
                                facts(turn.facts)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.separator))
                            .id(turn.id)
                        }
                    }
                }
                .onChange(of: session.turns.count) { _, _ in
                    if let last = session.turns.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            Button { Task { await controller.toggleMute() } } label: {
                Label(controller.isMuted ? "Resume" : "Pause", systemImage: controller.isMuted ? "play" : "pause")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(20)
    }

    // MARK: Parts

    @ViewBuilder
    private func facts(_ facts: [String]) -> some View {
        if !facts.isEmpty {
            HStack(spacing: 6) {
                ForEach(facts, id: \.self) { fact in
                    Text(fact)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(format: NSLocalizedString("Exact: %@", comment: ""), facts.joined(separator: ", ")))
        }
    }

    private var statusText: String {
        // Every word goes through the catalog: a plain String in Text(_:) is shown as written, in English.
        if controller.holdToTalk {
            return controller.heldSide == nil ? NSLocalizedString("Hold a button to talk", comment: "") : NSLocalizedString("Listening", comment: "")
        }
        switch controller.phase {
        case .speaking: return NSLocalizedString("Doddy is speaking", comment: "")
        case .thinking: return NSLocalizedString("Translating", comment: "")
        case .listening: return controller.isMuted ? NSLocalizedString("Paused", comment: "") : NSLocalizedString("Listening", comment: "")
        default: return NSLocalizedString("Connecting", comment: "")
        }
    }

    private var listeningColor: Color {
        controller.phase == .listening && !controller.isMuted ? Theme.confirmed : Theme.secondaryText
    }
}

/// The end screen (9): what happened, nothing kept, and Copy or Save for five minutes only.
struct TranslatorEndCard: View {
    let controller: VoiceSessionController
    let summary: TranslatorSummary
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Translation ended").font(.title3.bold())
            Text(summary.headline).font(.subheadline).foregroundStyle(Theme.secondaryText)
            Text("Nothing from this conversation is kept on this iPhone, and Doddy won't bring it up later. No notes were saved and nothing was added anywhere. ElevenLabs ran the translation and may keep its own recording, as in Settings › Privacy.")
                .font(.footnote)
            Text(verbatim: String(format: NSLocalizedString("Want something from it? Only on your tap, until %@. After that the text is gone.", comment: ""), summary.expiresAt.formatted(date: .omitted, time: .shortened)))
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Button {
                copied = controller.copyTranslatorText()
            } label: {
                HStack { Text(copied ? "Copied" : "Copy the text"); Spacer(); Image(systemName: copied ? "checkmark" : "doc.on.doc") }
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("translator.copy")
            if copied {
                // Review H10: copied with .localOnly and an expiry, so say where and until when.
                Text(verbatim: String(format: NSLocalizedString("Copied on this iPhone only, not to your other devices. The clipboard lets it go at %@.", comment: ""), summary.expiresAt.formatted(date: .omitted, time: .shortened)))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            if !summary.facts.isEmpty {
                switch controller.translatorFactsSaved {
                case .success(let text)?:
                    Label(String(format: NSLocalizedString("Saved as a note: “%@”", comment: ""), text), systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.confirmed)
                case .failure(let error)?:
                    ProblemView(message: message(error))
                    saveButton
                case nil:
                    saveButton
                }
            }
            Button("Done") { controller.dismissTranslatorSummary() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("translator.done")
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var saveButton: some View {
        Button {
            Task { await controller.saveTranslatorFacts() }
        } label: {
            HStack { Text("Save the facts as a note"); Spacer(); Image(systemName: "square.and.arrow.down") }
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityHint(String(format: NSLocalizedString("Saves only: %@.", comment: ""), summary.facts.joined(separator: ", ")))
        .accessibilityIdentifier("translator.saveFacts")
    }

    private func message(_ error: TranslatorSaveError) -> String {
        switch error {
        case .nothingToSave: NSLocalizedString("Nothing exact was said, so there's nothing to save.", comment: "")
        case .failed(let reason): "Nothing was saved. \(reason)"
        }
    }
}

/// Home › Translate (1), redone 9 Nov 2026 (owner: "zrób to menu łatwiejsze w obsłudze i w kolorze Doddy",
/// decision 2026-11-09-translator-translates-at-once): two big cards for the way, two language buttons with a
/// swap between them, one-tap chips for the most asked languages, and one orange Start. Then the
/// conversation opens in translator mode with no notes, conversations or profile sent to the agent.
struct TranslatorStartView: View {
    @Environment(\.dismiss) private var dismiss
    /// Set when the user taps Start; Home opens the conversation after this sheet has closed.
    @Binding var chosen: TranslatorSetup?
    @State private var kind = TranslatorKind.faceToFace
    @State private var owner: TranslatorLanguage
    @State private var other: TranslatorLanguage?
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false

    /// The two languages picked last time (ADR-574), so a second go is one tap.
    private static let lastOwnerKey = "translator.lastOwner"
    private static let lastOtherKey = "translator.lastOther"
    /// One tap for the languages asked for most; every other one is in the list behind the button.
    private static let quickCodes = ["en", "de", "es", "fr", "it", "uk", "pl"]

    init(chosen: Binding<TranslatorSetup?>) {
        _chosen = chosen
        let pair = TranslatorLanguages.startingPair(
            lastOwner: UserDefaults.standard.string(forKey: Self.lastOwnerKey),
            lastOther: UserDefaults.standard.string(forKey: Self.lastOtherKey),
            ownerDefault: VoiceSessionController.ownerLanguage)
        _owner = State(initialValue: pair.owner)
        _other = State(initialValue: pair.other)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    HStack(spacing: 12) {
                        wayCard(.faceToFace, symbol: "person.2.fill", title: Text("Face to face"), detail: Text("Both ways"))
                        wayCard(.listen, symbol: "ear.fill", title: Text("Listen only"), detail: Text("Into your language"))
                    }
                    languages
                    quickChips
                    Button {
                        start()
                    } label: {
                        Label("Start translating", systemImage: "character.bubble.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.inkOnOrange)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .background(Theme.orangeCue.opacity(owner == other ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .disabled(owner == other)
                    .accessibilityIdentifier("translator.start")
                    notes
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle("Translate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func start() {
        chosen = TranslatorSetup(kind: kind, owner: owner, other: other)
        UserDefaults.standard.set(owner.code, forKey: Self.lastOwnerKey)
        UserDefaults.standard.set(other?.code ?? TranslatorLanguages.detectCode, forKey: Self.lastOtherKey)
        dismiss()
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if !hideCharacterArt {
                Image(decorative: "WholeDoddy_wave")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 86)
                    .doddyArtMarker("doddy.translator.start")
            }
            Text("Pick the languages and start. Doddy stays quiet until someone speaks, then translates straight away.")
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func wayCard(_ way: TranslatorKind, symbol: String, title: Text, detail: Text) -> some View {
        let selected = kind == way
        return Button {
            withAnimation(.snappy) { kind = way }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                title.font(.headline)
                detail.font(.footnote)
                    .opacity(0.8)
            }
            .foregroundStyle(selected ? Theme.inkOnOrange : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(14)
            .background(selected ? Theme.orangeCue : Theme.quietSurface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(selected ? Color.clear : Theme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("translator.way.\(way.rawValue)")
    }

    /// You ⇄ them, each a button that opens the full list.
    private var languages: some View {
        HStack(spacing: 8) {
            languageMenu(title: Text("You speak"), name: owner.nativeName, id: "translator.owner") {
                Picker("You speak", selection: $owner) {
                    ForEach(TranslatorLanguages.all) { Text($0.label).tag($0) }
                }
            }
            Button {
                guard let current = other else { return }
                withAnimation(.snappy) {
                    other = owner
                    owner = current
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.headline)
                    .foregroundStyle(Theme.inkOnOrange)
                    .frame(width: 44, height: 44)
                    .background(Theme.orangeCue, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(other == nil)
            .opacity(other == nil ? 0.4 : 1)
            .accessibilityLabel(Text("Swap languages"))
            .accessibilityIdentifier("translator.swap")
            languageMenu(title: kind == .faceToFace ? Text("They speak") : Text("They're speaking"),
                         name: other?.nativeName ?? NSLocalizedString("Detect when they talk", comment: ""),
                         id: "translator.other") {
                Picker("They speak", selection: $other) {
                    Text("Detect when they talk").tag(TranslatorLanguage?.none)
                    ForEach(TranslatorLanguages.all.filter { $0 != owner }) { Text($0.label).tag(TranslatorLanguage?.some($0)) }
                }
            }
        }
    }

    private func languageMenu<Content: View>(title: Text, name: String, id: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                title.font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                HStack(spacing: 4) {
                    Text(verbatim: name).font(.headline).foregroundStyle(Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Theme.accentText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.separator, lineWidth: 1))
        }
        .accessibilityIdentifier(id)
    }

    /// The other person's language in one tap.
    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.quickCodes.compactMap(TranslatorLanguages.named).filter { $0 != owner }) { language in
                    let selected = other == language
                    Button {
                        withAnimation(.snappy) { other = language }
                    } label: {
                        Text(verbatim: language.nativeName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? Theme.inkOnOrange : Theme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(selected ? Theme.orangeCue : Theme.quietSurface, in: Capsule())
                            .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.separator, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            if kind == .faceToFace {
                Text("Put the phone between you. Their half of the screen faces them and shows, in their language, that this is an AI translation.")
            } else {
                Text("For a guide, a talk or an announcement. Doddy translates into your language and never speaks to the people around you. Not for someone's private conversation.")
            }
            Text("Both voices go to ElevenLabs to be translated. Your notes, conversations and profile aren't sent. Nothing is kept on this iPhone unless you tap Copy or Save at the end. Not for emergencies: call your local emergency number.")
        }
        .font(.footnote)
        .foregroundStyle(Theme.secondaryText)
    }
}
