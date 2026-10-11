import DoddyCore
import SwiftUI

/// Typed questions to Doddy's AI. Opt-in (Settings → Ask Doddy). Every answer says whether it comes from
/// the user's saved notes (with the notes shown) or is a general answer that is not from their notes.
struct AskView: View {
    var openSettings: () -> Void = {}

    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PreferenceKey.assistantConsent) private var consent = false
    @AppStorage(PreferenceKey.assistantUseNotes) private var useNotes = true
    @AppStorage(PreferenceKey.gatewayAddress) private var gatewayAddress = ""
    @State private var controller = AskController()
    @FocusState private var inputFocused: Bool

    private var policy: AssistantPolicy { AssistantPolicy(consentGranted: consent, includeNotes: useNotes) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcript
                Divider()
                composer
            }
            .background(Theme.canvas)
            .navigationTitle("Ask Doddy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        controller.cancel()
                        dismiss()
                    }
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .onDisappear { controller.cancel() }
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if controller.messages.isEmpty && controller.error == nil {
                        intro
                    }
                    ForEach(controller.messages) { message in
                        row(message).id(message.id)
                    }
                    if controller.isSending {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Doddy is thinking…")
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("ask.thinking")
                    }
                    if let error = controller.error {
                        errorCard(error)
                    }
                    Text("Doddy is an AI, not a person. Your question, the last few messages and any notes shown under an answer are sent to Doddy's server and on to OpenAI to write the reply. Nothing is saved unless you save it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("ask.disclosure")
                }
                .padding(24)
            }
            .onChange(of: controller.messages.count) { _, _ in
                if let last = controller.messages.last { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(last.id, anchor: .bottom) } }
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
            if !consent {
                ProblemView(message: AssistantError.consentRequired.userMessage)
                Button("Open Settings") { dismiss(); openSettings() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func row(_ message: AskController.Message) -> some View {
        switch message.kind {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .padding(12)
                    .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("You: \(message.text)")
            }
        case .assistant(let answer):
            assistantRow(answer)
        }
    }

    private func assistantRow(_ answer: AssistantAnswer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(answer.answer.text)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.separator, lineWidth: 1))
                .accessibilityLabel("Doddy: \(answer.answer.text)")
                .accessibilityIdentifier("ask.answer")

            switch answer.answer.basis {
            case .savedNotes:
                VStack(alignment: .leading, spacing: 6) {
                    Label("From your saved notes", systemImage: "note.text")
                        .font(.footnote.bold())
                        .accessibilityIdentifier("ask.basis.notes")
                    ForEach(answer.answer.sources) { record in
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
                }
            case .general:
                Label("Not from your notes. This is a general answer.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("ask.basis.general")
            }

            if !answer.notesSent.isEmpty {
                Text(answer.notesSent.count == 1 ? "1 saved note was sent with this question." : "\(answer.notesSent.count) saved notes were sent with this question.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            if answer.notesSearchFailed {
                Label("Couldn't search your notes this time, so none were used.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.error)
            }
        }
    }

    private func errorCard(_ error: AssistantError) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProblemView(message: error.userMessage)
                .accessibilityIdentifier("ask.error")
            HStack {
                if needsSettings(error) {
                    Button("Open Settings") { dismiss(); openSettings() }
                        .buttonStyle(SecondaryButtonStyle())
                } else if error.canRetryNow {
                    Button("Try again") { send() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(!controller.canSend)
                        .accessibilityIdentifier("ask.retry")
                }
            }
            Text("Your question is still in the box. Your saved notes are not affected.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
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
            TextField("Ask a question", text: $controller.draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { send() }
                .disabled(controller.isSending)
                .accessibilityIdentifier("ask.input")
            if controller.isSending {
                Button("Stop") { controller.cancel() }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("ask.stop")
            } else {
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .disabled(!controller.canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("ask.send")
            }
        }
        .padding(16)
        .background(Theme.canvas)
    }

    private func send() {
        guard let wiring = store.environment.assistant else { return }
        // Private notes (ADR-308) are never sent to the Ask Doddy gateway.
        let recall = ShareableRecallService(base: store.environment.recallService) { PrivateNotesStore.current().ids }
        let service = wiring.service(gatewayAddress: gatewayAddress, recall: recall)
        let locale = Locale.current.language.languageCode?.identifier ?? "en"
        controller.send(using: service, policy: policy, locale: locale)
    }
}
