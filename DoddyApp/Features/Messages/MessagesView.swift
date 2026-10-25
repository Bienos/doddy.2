import DoddyCore
import SwiftUI
import UIKit

/// Messages (ADR-585): the typed conversation with Doddy, saved on this iPhone until the user deletes it.
/// Opt-in like before (Settings → Ask Doddy). Every answer says whether it comes from the user's saved
/// notes (with the notes shown) or is a general answer that is not from their notes. What each line may
/// claim is decided by `ThreadRules`; this view only draws it.
///
/// It is drawn like the iPhone's Messages (ADR-605): orange bubbles for you on the right, Doddy's on the
/// left in the app's quiet surface, a tail on the last bubble of a run, a typing bubble while the answer is on its way, a capsule
/// composer with a round send button. Two things differ on purpose: there is no "Delivered" or "Read"
/// (nothing here can know either, `ThreadRules.deliveryLine`), and Doddy says he is an AI.
struct MessagesView: View {
    let openSettings: () -> Void

    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PreferenceKey.assistantConsent) private var consent = false
    @AppStorage(PreferenceKey.assistantUseNotes) private var useNotes = true
    @State private var model: MessagesModel
    @State private var confirmingDelete = false
    /// The plan screen opened from a plan offer (ADR-626).
    @State private var planRequest: PlanAskRequest?
    @FocusState private var inputFocused: Bool

    /// - Parameter draft: text already in the box, for the person to read, change and send
    ///   themselves (the Apple Health week summary, ADR-622). Nothing is sent without their tap.
    init(repository: any MessageThreadRepository, draft: String = "", openSettings: @escaping () -> Void = {}) {
        self.openSettings = openSettings
        let model = MessagesModel(repository: repository)
        model.draft = draft
        _model = State(initialValue: model)
    }

    private var policy: AssistantPolicy { AssistantPolicy(consentGranted: consent, includeNotes: useNotes) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                thread
                // The composer reads the draft itself, so typing redraws it and not the whole thread.
                MessagesComposer(model: model, useNotes: $useNotes, focus: $inputFocused, send: send)
            }
            // A full-screen cover on iPad: one readable column (ADR-437).
            .readableColumn()
            .background(Theme.canvas)
            .navigationTitle("Doddy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The guide's "Doddy" wordmark in the header, as on Home, Notes and the other screens.
                ToolbarItem(placement: .principal) { DoddyWordmark() }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        model.cancel()
                        close()
                    }
                }
                if !model.messages.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Delete conversation", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                                .disabled(model.isSending)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("More")
                        .accessibilityIdentifier("messages.more")
                    }
                }
            }
            .confirmationDialog("Delete this conversation?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete conversation", role: .destructive) {
                    Task { await model.deleteConversation() }
                }
            } message: {
                Text("It is removed from this iPhone. Your saved notes are not affected.")
            }
            .sheet(item: $planRequest) { request in
                NavigationStack {
                    TrainingPlanView(prefill: request.ask)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { planRequest = nil }
                                    .accessibilityIdentifier("plan.close")
                            }
                        }
                }
            }
            .alert("Couldn't delete the conversation", isPresented: Binding(
                get: { model.deleteFailed },
                set: { if !$0 { model.clearDeleteFailure() } }
            )) {
                Button("OK") { model.clearDeleteFailure() }
            } message: {
                Text("Doddy couldn't confirm it was removed from this iPhone. Try again.")
            }
        }
        .foregroundStyle(Theme.ink)
        .task { await model.load() }
        // Motion v2 (MV4, Q2): he comes up with this cover, on its composer, and is back on
        // Home's stage as it goes.
        .onAppear { DoddyDirector.shared.askOpened() }
        // MV5: thinking while the reply hasn't come (from 600 ms), and only then.
        .onChange(of: model.isSending) { _, sending in
            DoddyDirector.shared.askSending(sending, failed: model.error != nil)
        }
        // The Face ID cover (ADR-310) is on the root view, and a full-screen cover sits above it. The saved
        // conversation must not stay readable over the lock, so this screen closes when the lock comes up.
        .onChange(of: AppLock.shared.isLocked) { _, locked in
            if locked {
                model.cancel()
                close()
            }
        }
        .onDisappear {
            model.cancel()
            DoddyDirector.shared.askClosing()
        }
    }

    /// Closes Messages; he is back on Home's stage under the cover as it goes down.
    private func close() {
        DoddyDirector.shared.askClosing()
        dismiss()
    }

    // MARK: Thread

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if model.messages.isEmpty && model.error == nil && model.storage != .loading {
                        intro
                    }
                    ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                        messageBlock(at: index, message)
                            .id(message.id)
                    }
                    if model.isSending {
                        TypingBubble()
                            .padding(.top, 8)
                    }
                    Group {
                        if !consent {
                            consentCard
                        }
                        if let error = model.error {
                            errorCard(error)
                        }
                        if model.storage == .notSaved {
                            Label("Doddy can't read or save this conversation on this iPhone right now. What you write here is gone when you close this screen.", systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(Theme.error)
                                .accessibilityIdentifier("messages.notSaved")
                        }
                        Text("Doddy is an AI, not a person. This conversation is saved on this iPhone until you delete it. Your question, the last few messages and any notes shown under an answer are sent to Doddy's server and on to Anthropic to write the reply.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("ask.disclosure")
                    }
                    .padding(.top, 14)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            // Opens at the newest message.
            .defaultScrollAnchor(.bottom)
            // Motion v2: Doddy stands on the composer's top edge; the conversation keeps 108 pt
            // above it, so the newest line can always scroll clear of him (brief rule 8).
            .contentMargins(.bottom, DoddyDirector.shared.isActive ? CGFloat(MotionLayout.listBottomInset) : 0, for: .scrollContent)
            .onChange(of: model.messages.count) { _, _ in
                if let last = model.messages.last { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask me anything.")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text(useNotes
                 ? "If your question is about something you saved, I'll look at the matching notes and show you which ones I used."
                 : "Your saved notes are not used. Turn them on in Settings if you want me to look at them.")
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(12)
    }

    /// Shown while Ask Doddy is off: nothing is sent or saved until the user turns it on.
    private var consentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProblemView(message: AssistantError.consentRequired.userMessage)
            Button("Open Settings") { close(); openSettings() }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: Rows

    /// One message with the time heading above it when the pause was long, and the run it belongs to:
    /// bubbles of one sender close together, the tail only on the last one.
    @ViewBuilder
    private func messageBlock(at index: Int, _ message: ThreadMessage) -> some View {
        let previous = index > 0 ? model.messages[index - 1] : nil
        let next = index + 1 < model.messages.count ? model.messages[index + 1] : nil
        let heading = ThreadRules.showsHeading(message, after: previous)
        let startsRun = heading || previous?.sender != message.sender
        let endsRun = next.map { ThreadRules.showsHeading($0, after: message) || $0.sender != message.sender } ?? true
        VStack(alignment: .leading, spacing: 2) {
            if heading {
                Text(DateText.full(message.createdAt))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            switch message.sender {
            case .user: userRow(message, tail: endsRun)
            case .doddy: doddyRow(message, tail: endsRun)
            }
        }
        .padding(.top, startsRun && !heading ? 8 : 0)
    }

    private func userRow(_ message: ThreadMessage, tail: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 0) {
                Spacer(minLength: 56)
                MessageBubble(text: message.text, fromUser: true, tail: tail)
                    .accessibilityLabel("You: \(message.text)")
            }
            // Only what is known: on its way, or no answer yet. Never "read".
            switch ThreadRules.deliveryLine(for: message) {
            case .sending:
                Text("Sending…")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.trailing, 6)
            case .notDelivered:
                Button {
                    retry(message.id)
                } label: {
                    Text("No answer yet. Tap to try again.")
                        .font(.caption)
                        .foregroundStyle(Theme.error)
                        .frame(minHeight: 44, alignment: .trailing)
                        .padding(.trailing, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isSending || model.error?.canRetryNow == false)
                .accessibilityIdentifier("messages.retry")
            case nil:
                EmptyView()
            }
        }
    }

    private func doddyRow(_ message: ThreadMessage, tail: Bool) -> some View {
        let notes = sources(of: message)
        return VStack(alignment: .leading, spacing: 6) {
            // A file Doddy made is a card with Open; it is not an answer, so it has no "from your notes" line.
            if let document = message.document {
                fileBubble(document)
            } else {
                HStack(spacing: 0) {
                    MessageBubble(text: message.text, fromUser: false, tail: tail)
                        .accessibilityLabel("Doddy: \(message.text)")
                        .accessibilityIdentifier("ask.answer")
                    Spacer(minLength: 56)
                }
            }

            // Where the answer came from, small and grey under the bubble, as a caption would be.
            if message.document == nil {
            Group {
                switch message.basis {
                case .savedNotes:
                    VStack(alignment: .leading, spacing: 6) {
                        Label("From your saved notes", systemImage: "note.text")
                            .font(.caption.bold())
                            .accessibilityIdentifier("ask.basis.notes")
                        ForEach(notes) { record in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.currentText).lineLimit(3)
                                Text("\(record.source.displayName) · \(DateText.full(record.capturedAt))")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityElement(children: .combine)
                        }
                        // A saved conversation outlives the notes it cited: say so rather than drop them quietly.
                        if store.hasLoaded && notes.count < message.noteIDs.count {
                            Text("Some of these notes have since been deleted.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                case .general, nil:
                    Label("Not from your notes. This is a general answer.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("ask.basis.general")
                }

                if message.notesSent > 0 {
                    Text(message.notesSent == 1 ? "1 saved note was sent with this question." : "\(message.notesSent) saved notes were sent with this question.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                if message.notesSearchFailed {
                    Label("Couldn't search your notes this time, so none were used.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.error)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 56)
            }

            if let proposal = model.proposals[message.id] {
                proposalCard(proposal, answerID: message.id)
            }
            if let planAsk = model.planAsks[message.id] {
                planCard(planAsk, answerID: message.id)
            }
        }
    }

    /// The training plan Doddy offered with an answer (ADR-626): the goal, and the days and minutes if they were said. Nothing
    /// is made and no question is asked until the person taps Open the plan; the safety questions are on that screen.
    private func planCard(_ ask: PlanAsk, answerID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Doddy can set up a training plan", systemImage: "figure.run")
                .font(.subheadline.bold())
            Text(PlanText.goal(ask.goal))
                .font(.headline)
            if let days = ask.daysPerWeek {
                Text(verbatim: String(format: NSLocalizedString("Days a week: %lld", comment: ""), days))
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
            }
            if let minutes = ask.minutesPerSession {
                Text(verbatim: String(format: NSLocalizedString("Minutes a session: %lld", comment: ""), minutes))
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
            }
            Text("You answer the safety questions yourself on the next screen. No plan is made before that.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 10) {
                Button("Open the plan") { planRequest = PlanAskRequest(ask: ask) }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("messages.openPlan")
                Button("Not now") { model.dismissPlanAsk(answerID) }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("messages.dismissPlan")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.trailing, 24)
        .accessibilityElement(children: .contain)
    }

    /// The file Doddy offered with an answer (ADR-606): the exact words that will be made, and nothing runs until
    /// the person taps Make. Not now removes the offer; nothing was made, so nothing is deleted.
    private func proposalCard(_ proposal: AssistantProposal, answerID: UUID) -> some View {
        let isMaking = model.making == answerID
        return VStack(alignment: .leading, spacing: 10) {
            Label("Doddy can make a file", systemImage: Self.icon(forKind: proposal.kind.rawValue))
                .font(.subheadline.bold())
            kindName(proposal.kind.rawValue)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Text(proposal.title)
                .font(.headline)
            Text(proposal.request)
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
            if let failure = model.makeFailure, model.making == nil {
                Label { failureText(failure) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .font(.footnote)
                    .foregroundStyle(Theme.error)
                    .accessibilityIdentifier("messages.makeFailed")
            }
            HStack(spacing: 10) {
                Button {
                    model.makeDocument(for: answerID, using: ServerThreadDocumentMaker())
                } label: {
                    if isMaking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Making it…")
                        }
                    } else {
                        Text("Make it")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.making != nil)
                .accessibilityIdentifier("messages.makeFile")
                Button("Not now") { model.dismissProposal(answerID) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isMaking)
                    .accessibilityIdentifier("messages.dismissFile")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.trailing, 24)
        .accessibilityElement(children: .contain)
    }

    /// The file bubble. Its link opens the file in Safari (Quick Look and Share); until the file is ready its page
    /// says so and checks again by itself, so the thread holds no status.
    private func fileBubble(_ document: ThreadDocument) -> some View {
        Button {
            UIApplication.shared.open(document.url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: Self.icon(forKind: document.kind))
                    .font(.title2)
                    .foregroundStyle(Theme.accentText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.name)
                        .font(.body.bold())
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        kindName(document.kind)
                        Text(verbatim: "·")
                        Text("Tap to open")
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 40)
        .accessibilityIdentifier("messages.file")
    }

    private static func icon(forKind kind: String) -> String {
        switch kind {
        case "deck": "rectangle.on.rectangle"
        case "spreadsheet": "tablecells"
        case "pdf": "doc.richtext"
        case "doc": "doc.text"
        default: "doc.plaintext"
        }
    }

    @ViewBuilder
    private func failureText(_ failure: ThreadDocumentError) -> some View {
        switch failure {
        case .notConfigured: Text("Making files needs Doddy's server, which isn't set up in this build.")
        case .offline: Text("Doddy's server couldn't be reached. Nothing was confirmed. Check your connection and try again.")
        case .failed: Text("The file wasn't made, or Doddy couldn't confirm it. Try again.")
        }
    }

    /// "Deck", "Document", … in the person's language (the same words as `ThreadDocument.label`).
    @ViewBuilder
    private func kindName(_ kind: String) -> some View {
        switch kind {
        case "deck": Text("Deck")
        case "doc": Text("Document")
        case "spreadsheet": Text("Spreadsheet")
        case "pdf": Text("PDF")
        default: Text("Text")
        }
    }

    /// The notes an answer cited, in the order it cited them, as they are now.
    private func sources(of message: ThreadMessage) -> [MemoryRecord] {
        message.noteIDs.compactMap { id in store.memories.first { $0.id == id } }
    }

    private func errorCard(_ error: AssistantError) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProblemView(message: error.userMessage)
                .accessibilityIdentifier("ask.error")
            HStack {
                if needsSettings(error) {
                    Button("Open Settings") { close(); openSettings() }
                        .buttonStyle(SecondaryButtonStyle())
                } else if let failed = lastNotAnswered, error.canRetryNow {
                    Button("Try again") { retry(failed.id) }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.isSending)
                        .accessibilityIdentifier("ask.retry")
                }
            }
            if lastNotAnswered != nil {
                Text("Your message is in the conversation. Tap it to send it again. Your saved notes are not affected.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("Your question is still in the box. Your saved notes are not affected.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// The newest message, when it got no answer.
    private var lastNotAnswered: ThreadMessage? {
        guard let last = model.messages.last, ThreadRules.canRetry(last) else { return nil }
        return last
    }

    /// Only the switch is the person's to change; a server that isn't set up, or doesn't accept this iPhone, is not.
    private func needsSettings(_ error: AssistantError) -> Bool {
        error == .consentRequired
    }

    // MARK: Sending

    private func send() {
        model.send(using: service(), policy: policy, locale: locale)
    }

    private func retry(_ id: UUID) {
        model.retry(id, using: service(), policy: policy, locale: locale)
    }

    private var locale: String { Locale.current.language.languageCode?.identifier ?? "en" }

    /// nil when this build has no messaging server address, or the storage is not open.
    private func service() -> AssistantService? {
        guard let wiring = store.environment.assistant else { return nil }
        // Private notes (ADR-310) are never sent with a question.
        let recall = ShareableRecallService(base: store.environment.recallService) { PrivateNotesStore.current().ids }
        return wiring.service(recall: recall)
    }
}

// MARK: - Composer

/// The box at the bottom: a plus button, a capsule with the text and a round send button inside it.
/// Plus holds the one real choice there is (use saved notes or not); photos, files and voice notes are not
/// offered because they are not built.
private struct MessagesComposer: View {
    @Bindable var model: MessagesModel
    @Binding var useNotes: Bool
    var focus: FocusState<Bool>.Binding
    let send: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Toggle("Use relevant saved notes", isOn: $useNotes)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 34, height: 34)
                    .background(Theme.quietSurface, in: Circle())
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More")
            .accessibilityIdentifier("messages.plus")

            HStack(alignment: .bottom, spacing: 6) {
                TextField("Ask a question", text: $model.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused(focus)
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .disabled(model.isSending)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("ask.input")
                trailingButton
                    .padding(.bottom, 3)
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1)
            )
            .padding(.bottom, 5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.canvas)
        // Motion v2 (Q2): the composer is "the composer" he stands on, left of Send, and rides
        // with the keyboard.
        .motionSurface(.composer)
    }

    @ViewBuilder
    private var trailingButton: some View {
        if model.isSending {
            Button { model.cancel() } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.canvas)
                    .frame(width: 30, height: 30)
                    .background(Theme.ink, in: Circle())
                    .contentShape(Circle().inset(by: -6))
            }
            .accessibilityLabel("Stop")
            .accessibilityIdentifier("ask.stop")
        } else {
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(model.canSend ? BubbleInk.onOrange : Theme.secondaryText)
                    .frame(width: 30, height: 30)
                    .background(model.canSend ? Theme.orangeCue : Theme.separator, in: Circle())
                    .contentShape(Circle().inset(by: -6))
            }
            .disabled(!model.canSend)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("ask.send")
            // His zone stays 24 pt from Send (brief rule 8).
            .motionMark("send")
        }
    }
}

// MARK: - Bubbles

/// Text on Doddy's orange is always the dark ink, in light and dark appearance: cream on orange does not
/// read (the brand guide passes ink on orange, not white). Orange itself is the app's `Theme.orangeCue`.
private enum BubbleInk {
    static let onOrange = Color(red: 8 / 255, green: 8 / 255, blue: 8 / 255)
}

/// One bubble: Doddy's orange with dark ink for the user, the quiet surface for Doddy, with a tail when it ends a run.
/// Web links in the text can be tapped; they open in the browser only when the user taps one.
private struct MessageBubble: View {
    let text: String
    let fromUser: Bool
    let tail: Bool

    var body: some View {
        Text(Self.linked(text))
            .font(.body)
            .foregroundStyle(fromUser ? BubbleInk.onOrange : Theme.ink)
            .tint(fromUser ? BubbleInk.onOrange : Theme.accentText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(BubbleBackground(fromUser: fromUser, tail: tail))
            // The tail sticks out 5 pt; every bubble of a run keeps that room so they line up.
            .padding(fromUser ? .trailing : .leading, 6)
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
            }
    }

    /// The text with http and https addresses made tappable.
    private static func linked(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        guard text.contains("."),
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return out }
        let whole = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: whole) {
            guard let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let range = Range(match.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: out),
                  let upper = AttributedString.Index(range.upperBound, within: out) else { continue }
            out[lower..<upper].link = url
        }
        return out
    }
}

private struct BubbleBackground: View {
    let fromUser: Bool
    let tail: Bool

    var body: some View {
        let colour = fromUser ? Theme.orangeCue : Theme.quietSurface
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(colour)
            // Filled apart from the body: two outlines filled as one path would cancel where they overlap.
            if tail {
                BubbleTail(fromUser: fromUser).fill(colour)
            }
        }
    }
}

/// The small curl at the bottom corner of the last bubble of a run: a wedge from the bottom edge out to a
/// point 5 pt past the side, with a hollow flank, tucked into the rounded corner of the body.
private struct BubbleTail: Shape {
    let fromUser: Bool

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        // Measured from the bubble's own left edge for the user (tail on the right), mirrored for Doddy.
        func x(_ v: CGFloat) -> CGFloat { fromUser ? rect.minX + v : rect.minX + w - v }
        var path = Path()
        path.move(to: CGPoint(x: x(w - 14), y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: x(w + 5), y: rect.maxY), control: CGPoint(x: x(w - 2), y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: x(w), y: rect.maxY - 14), control: CGPoint(x: x(w - 1), y: rect.maxY - 3))
        path.closeSubpath()
        return path
    }
}

/// Three dots in a grey bubble while the answer is on its way. Still under Reduce Motion.
private struct TypingBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            dots
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(BubbleBackground(fromUser: false, tail: true))
                .padding(.leading, 6)
            Spacer(minLength: 56)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Doddy is thinking…")
        .accessibilityIdentifier("ask.thinking")
    }

    @ViewBuilder
    private var dots: some View {
        if reduceMotion {
            HStack(spacing: 5) { ForEach(0..<3, id: \.self) { _ in dot(opacity: 0.6) } }
        } else {
            TimelineView(.periodic(from: .now, by: 0.4)) { context in
                let active = Int(context.date.timeIntervalSinceReferenceDate / 0.4) % 3
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in dot(opacity: i == active ? 1 : 0.4) }
                }
                .animation(.easeInOut(duration: 0.3), value: active)
            }
        }
    }

    private func dot(opacity: Double) -> some View {
        Circle().fill(Theme.secondaryText).opacity(opacity).frame(width: 8, height: 8)
    }
}
