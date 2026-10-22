import DoddyCore
import SwiftUI

/// Messages (ADR-585): the typed conversation with Doddy, in bubbles, saved on this iPhone until the user
/// deletes it. Opt-in like before (Settings → Ask Doddy). Every answer says whether it comes from the user's
/// saved notes (with the notes shown) or is a general answer that is not from their notes. What each line
/// may claim is decided by `ThreadRules`; this view only draws it.
struct MessagesView: View {
    let openSettings: () -> Void

    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PreferenceKey.assistantConsent) private var consent = false
    @AppStorage(PreferenceKey.assistantUseNotes) private var useNotes = true
    @AppStorage(PreferenceKey.gatewayAddress) private var gatewayAddress = ""
    @State private var model: MessagesModel
    @State private var confirmingDelete = false
    @FocusState private var inputFocused: Bool

    init(repository: any MessageThreadRepository, openSettings: @escaping () -> Void = {}) {
        self.openSettings = openSettings
        _model = State(initialValue: MessagesModel(repository: repository))
    }

    private var policy: AssistantPolicy { AssistantPolicy(consentGranted: consent, includeNotes: useNotes) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                thread
                Divider()
                composer
            }
            // A full-screen cover on iPad: one readable column (ADR-437).
            .readableColumn()
            .background(Theme.canvas)
            .navigationTitle("Doddy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                VStack(alignment: .leading, spacing: 12) {
                    if model.messages.isEmpty && model.error == nil && model.storage != .loading {
                        intro
                    }
                    ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                        VStack(alignment: .leading, spacing: 12) {
                            if ThreadRules.showsHeading(message, after: index > 0 ? model.messages[index - 1] : nil) {
                                Text(DateText.full(message.createdAt))
                                    .font(.footnote)
                                    .foregroundStyle(Theme.secondaryText)
                                    .frame(maxWidth: .infinity)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            row(message)
                        }
                        .id(message.id)
                    }
                    if model.isSending {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Doddy is thinking…")
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("ask.thinking")
                    }
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
                    Text("Doddy is an AI, not a person. This conversation is saved on this iPhone until you delete it. Your question, the last few messages and any notes shown under an answer are sent to Doddy's server and on to OpenAI to write the reply.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("ask.disclosure")
                }
                .padding(24)
            }
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

    @ViewBuilder
    private func row(_ message: ThreadMessage) -> some View {
        switch message.sender {
        case .user: userRow(message)
        case .doddy: doddyRow(message)
        }
    }

    private func userRow(_ message: ThreadMessage) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .padding(12)
                    .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("You: \(message.text)")
            }
            // Only what is known: on its way, or no answer yet. Never "read".
            switch ThreadRules.deliveryLine(for: message) {
            case .sending:
                Text("Sending…")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            case .notDelivered:
                Button {
                    retry(message.id)
                } label: {
                    Text("No answer yet. Tap to try again.")
                        .font(.footnote)
                        .foregroundStyle(Theme.error)
                        .frame(minHeight: 44, alignment: .trailing)
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

    private func doddyRow(_ message: ThreadMessage) -> some View {
        let notes = sources(of: message)
        return VStack(alignment: .leading, spacing: 10) {
            Text(message.text)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.separator, lineWidth: 1))
                .accessibilityLabel("Doddy: \(message.text)")
                .accessibilityIdentifier("ask.answer")

            switch message.basis {
            case .savedNotes:
                VStack(alignment: .leading, spacing: 6) {
                    Label("From your saved notes", systemImage: "note.text")
                        .font(.footnote.bold())
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
                        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
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
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("ask.basis.general")
            }

            if message.notesSent > 0 {
                Text(message.notesSent == 1 ? "1 saved note was sent with this question." : "\(message.notesSent) saved notes were sent with this question.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            if message.notesSearchFailed {
                Label("Couldn't search your notes this time, so none were used.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.error)
            }
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

    private func needsSettings(_ error: AssistantError) -> Bool {
        switch error {
        case .notConfigured, .consentRequired, .notAuthorized: true
        default: false
        }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Ask a question", text: $model.draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { send() }
                .disabled(model.isSending)
                .accessibilityIdentifier("ask.input")
            if model.isSending {
                Button("Stop") { model.cancel() }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("ask.stop")
            } else {
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .disabled(!model.canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("ask.send")
                // His zone stays 24 pt from Send (brief rule 8).
                .motionMark("send")
            }
        }
        .padding(16)
        .background(Theme.canvas)
        // Motion v2 (Q2): the composer is "the composer" he stands on, left of Send, and rides
        // with the keyboard.
        .motionSurface(.composer)
    }

    // MARK: Sending

    private func send() {
        model.send(using: service(), policy: policy, locale: locale)
    }

    private func retry(_ id: UUID) {
        model.retry(id, using: service(), policy: policy, locale: locale)
    }

    private var locale: String { Locale.current.language.languageCode?.identifier ?? "en" }

    /// nil when Ask Doddy isn't set up.
    private func service() -> AssistantService? {
        guard let wiring = store.environment.assistant else { return nil }
        // Private notes (ADR-310) are never sent to the Ask Doddy gateway.
        let recall = ShareableRecallService(base: store.environment.recallService) { PrivateNotesStore.current().ids }
        return wiring.service(gatewayAddress: gatewayAddress, recall: recall)
    }
}
