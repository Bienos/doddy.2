import DoddyCore
import SwiftUI

// Translator mode screens (ADR-215), after the "Doddy Translator" canvas: start (1), face to face
// (4, 5, 6, 7, 8), listen only (6b) and the end (9). Their half shows their language's own lines;
// the owner's half uses the owner's language for the translated text and English for the app.

/// Face to face or listen only, shown in place of the transcript while translator mode is on.
struct TranslatorScreen: View {
    let controller: VoiceSessionController
    let session: TranslatorSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        Text("Doddy said to them: \(said.text)")
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
            .accessibilityValue(held ? NSLocalizedString("Held", comment: "") : "")
            // VoiceOver can't hold: a double-tap starts it and another ends it.
            .accessibilityHint("Double-tap to start, double-tap again to stop")
            .accessibilityAction {
                Task { if controller.heldSide == side { await controller.endHold() } else { await controller.beginHold(side) } }
            }
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
                    if let last = session.turns.last { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(last.id, anchor: .bottom) } }
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
            .accessibilityLabel("Exact: \(facts.joined(separator: ", "))")
        }
    }

    private var statusText: String {
        if controller.holdToTalk { return controller.heldSide == nil ? "Hold a button to talk" : "Listening" }
        switch controller.phase {
        case .speaking: return NSLocalizedString("Doddy is speaking", comment: "")
        case .thinking: return NSLocalizedString("Translating", comment: "")
        case .listening: return controller.isMuted ? "Paused" : "Listening"
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
            Text("Nothing from this conversation is kept on this iPhone, and Doddy won't bring it up later. No notes were saved and nothing was added anywhere. ElevenLabs ran the translation and keeps its own recording, as in Settings › Privacy.")
                .font(.footnote)
            Text("Want something from it? Only on your tap, until \(summary.expiresAt.formatted(date: .omitted, time: .shortened)). After that the text is gone.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Button {
                copied = controller.copyTranslatorText()
            } label: {
                HStack { Text(copied ? "Copied" : "Copy the text"); Spacer(); Image(systemName: copied ? "checkmark" : "doc.on.doc") }
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("translator.copy")
            if !summary.facts.isEmpty {
                switch controller.translatorFactsSaved {
                case .success(let text)?:
                    Label("Saved as a note: “\(text)”", systemImage: "checkmark.circle")
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
        .accessibilityHint("Saves only: \(summary.facts.joined(separator: ", ")).")
        .accessibilityIdentifier("translator.saveFacts")
    }

    private func message(_ error: TranslatorSaveError) -> String {
        switch error {
        case .nothingToSave: NSLocalizedString("Nothing exact was said, so there's nothing to save.", comment: "")
        case .failed(let reason): "Nothing was saved. \(reason)"
        }
    }
}

/// Languages and the way of translating, on the start screen and on the "Start translating?" card.
struct TranslatorChoices: View {
    @Binding var kind: TranslatorKind
    @Binding var owner: TranslatorLanguage
    /// Nil: detect when they talk.
    @Binding var other: TranslatorLanguage?

    var body: some View {
        Picker("Way", selection: $kind) {
            Text("Face to face").tag(TranslatorKind.faceToFace)
            Text("Listen only").tag(TranslatorKind.listen)
        }
        .pickerStyle(.segmented)
        Picker("You speak", selection: $owner) {
            ForEach(TranslatorLanguages.all) { language in
                Text(language.label).tag(language)
            }
        }
        Picker(kind == .faceToFace ? "They speak" : "They're speaking", selection: $other) {
            Text("Detect when they talk").tag(TranslatorLanguage?.none)
            ForEach(TranslatorLanguages.all.filter { $0 != owner }) { language in
                Text(language.label).tag(TranslatorLanguage?.some(language))
            }
        }
    }
}

/// Home › Translate (1): pick the languages, then the conversation opens in translator mode with
/// no notes, conversations or profile sent to the agent.
struct TranslatorStartView: View {
    @Environment(\.dismiss) private var dismiss
    /// Set when the user taps Start; Home opens the conversation after this sheet has closed.
    @Binding var chosen: TranslatorSetup?
    @State private var kind = TranslatorKind.faceToFace
    @State private var owner = VoiceSessionController.ownerLanguage
    @State private var other: TranslatorLanguage?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TranslatorChoices(kind: $kind, owner: $owner, other: $other)
                }
                Section {
                    if kind == .faceToFace {
                        Text("Put the phone on the table between you. Their half of the screen faces them, and Doddy first tells them, in their language, that he's an AI translator.")
                    } else {
                        Text("For a guide, a talk or an announcement. Doddy translates into your language and never speaks to the people around you. Not for someone's private conversation.")
                    }
                    Text("Both voices go to ElevenLabs to be translated. Your notes, conversations and profile aren't sent. Nothing is kept on this iPhone unless you tap Copy or Save at the end. Not for emergencies: call 112.")
                        .foregroundStyle(Theme.secondaryText)
                }
                .font(.footnote)
                // Typed text, on the iPhone, without internet (ADR-346).
                Section {
                    NavigationLink {
                        TextTranslateScreen()
                    } label: {
                        Label("Translate text without internet", systemImage: "character.book.closed")
                    }
                    .accessibilityIdentifier("translator.text")
                }
                Section {
                    Button("Start translating") {
                        chosen = TranslatorSetup(kind: kind, owner: owner, other: other)
                        dismiss()
                    }
                    .disabled(owner == other)
                    .accessibilityIdentifier("translator.start")
                }
            }
            .navigationTitle("Talk in their language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

/// "Change languages" on the "Start translating?" card.
struct TranslatorChangeSheet: View {
    let controller: VoiceSessionController
    @Environment(\.dismiss) private var dismiss
    @State private var kind: TranslatorKind
    @State private var owner: TranslatorLanguage
    @State private var other: TranslatorLanguage?

    init(controller: VoiceSessionController, setup: TranslatorSetup) {
        self.controller = controller
        _kind = State(initialValue: setup.kind)
        _owner = State(initialValue: setup.owner)
        _other = State(initialValue: setup.other)
    }

    var body: some View {
        NavigationStack {
            Form {
                TranslatorChoices(kind: $kind, owner: $owner, other: $other)
            }
            .navigationTitle("Change languages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use these") {
                        controller.changeTranslatorProposal(owner: owner, other: other, kind: kind)
                        dismiss()
                    }
                    .disabled(owner == other)
                }
            }
        }
    }
}
