import DoddyCore
import SwiftUI

/// Doddy's Messages (owner, 22 Oct 2026, ADR-582; Figma "Wyspa i wiadomości", screens 15 to 18):
/// a chat inside the app, kept on this iPhone, where Doddy also sends files and infographics.
/// It replaces Home's Type button and the one-off Ask screen. Replies use the same gateway and
/// rules as Ask: consent first, saved notes shown under an answer's source, and the AI disclosure.
struct MessagesView: View {
    var openSettings: () -> Void = {}

    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PreferenceKey.assistantConsent) private var consent = false
    @AppStorage(PreferenceKey.assistantUseNotes) private var useNotes = true
    @AppStorage(PreferenceKey.gatewayAddress) private var gatewayAddress = ""
    @State private var chat = MessagesController.shared
    @State private var confirmingDelete = false
    @FocusState private var inputFocused: Bool

    private var policy: AssistantPolicy { AssistantPolicy(consentGranted: consent, includeNotes: useNotes) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                thread
                composer
            }
            .readableColumn()
            .background(Theme.canvas)
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { close() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Delete all messages", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                            .disabled(chat.messages.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
            .confirmationDialog("Delete all messages?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete all messages", role: .destructive) { chat.deleteAll() }
            } message: {
                Text("This deletes the messages and the files Doddy sent, from this iPhone only.")
            }
        }
        .foregroundStyle(Theme.ink)
        // Motion v2 (MV4, Q2): he comes up with this cover, on its composer, as he did for Ask.
        .onAppear {
            DoddyDirector.shared.askOpened()
            chat.markOpened()
        }
        .onChange(of: chat.messages.count) { _, _ in chat.markOpened() }
        .onChange(of: chat.isSending) { _, sending in
            DoddyDirector.shared.askSending(sending, failed: chat.error != nil)
        }
        .onDisappear {
            chat.cancel()
            DoddyDirector.shared.askClosing()
        }
    }

    private func close() {
        DoddyDirector.shared.askClosing()
        dismiss()
    }

    // MARK: Thread

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if chat.messages.isEmpty && chat.error == nil {
                        intro
                    }
                    ForEach(chat.messages) { message in
                        MessageRow(message: message).id(message.id)
                    }
                    if chat.isSending {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Doddy is thinking…")
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.top, 4)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("ask.thinking")
                    }
                    if let error = chat.error { errorCard(error) }
                    if let problem = chat.storageProblem {
                        ProblemView(message: problem)
                    }
                    Text("Doddy is an AI, not a person. Your message, the last few messages and any notes shown under an answer are sent to Doddy's server and on to OpenAI to write the reply. Messages are kept on this iPhone.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 8)
                        .accessibilityIdentifier("ask.disclosure")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .contentMargins(.bottom, DoddyDirector.shared.isActive ? CGFloat(MotionLayout.listBottomInset) : 0, for: .scrollContent)
            .defaultScrollAnchor(.bottom)
            .onChange(of: chat.messages.count) { _, _ in
                if let last = chat.messages.last { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Write to Doddy.")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Group {
                if useNotes {
                    Text("If your message is about something you saved, I'll look at the matching notes. Files and pictures I make for you arrive here.")
                } else {
                    Text("Your saved notes are not used. Turn them on in Settings if you want me to look at them. Files and pictures I make for you arrive here.")
                }
            }
            .foregroundStyle(Theme.secondaryText)
            if !consent {
                ProblemView(message: AssistantError.consentRequired.userMessage)
                Button("Open Settings") { close(); openSettings() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.bottom, 8)
    }

    private func errorCard(_ error: AssistantError) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProblemView(message: error.userMessage)
                .accessibilityIdentifier("ask.error")
            HStack {
                if needsSettings(error) {
                    Button("Open Settings") { close(); openSettings() }
                        .buttonStyle(SecondaryButtonStyle())
                } else if error.canRetryNow, chat.messages.last?.sender == .user, let last = chat.messages.last?.text {
                    Button("Try again") { chat.draft = last; send() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(!chat.canSend)
                        .accessibilityIdentifier("ask.retry")
                }
            }
        }
        .padding(.top, 4)
    }

    private func needsSettings(_ error: AssistantError) -> Bool {
        switch error {
        case .notConfigured, .consentRequired, .notAuthorized: true
        default: false
        }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Write to Doddy", text: $chat.draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.separator, lineWidth: 1))
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { send() }
                .disabled(chat.isSending)
                .accessibilityIdentifier("ask.input")
            if chat.isSending {
                Button("Stop") { chat.cancel() }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("ask.stop")
            } else {
                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .disabled(!chat.canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("ask.send")
                // His zone stays 24 pt from Send (brief rule 8).
                .motionMark("send")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.canvas)
        // Motion v2 (Q2): the composer he stands on, left of Send, riding with the keyboard.
        .motionSurface(.composer)
    }

    private func send() {
        guard let wiring = store.environment.assistant else { return }
        // Private notes (ADR-310) are never sent to the Ask Doddy gateway.
        let recall = ShareableRecallService(base: store.environment.recallService) { PrivateNotesStore.current().ids }
        let service = wiring.service(gatewayAddress: gatewayAddress, recall: recall)
        let locale = Locale.current.language.languageCode?.identifier ?? "en"
        chat.send(using: service, policy: policy, locale: locale)
    }
}

/// One message: a bubble, a file card or an infographic. The user's are ink, Doddy's are paper.
private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.sender == .user { Spacer(minLength: 48) }
            content
            if message.sender == .doddy { Spacer(minLength: 48) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch message.content {
        case .text(let text):
            Text(text)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundStyle(message.sender == .user ? Theme.canvas : Theme.ink)
                .background(message.sender == .user ? Theme.ink : Theme.quietSurface, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityLabel(Text("\(message.sender == .user ? "You" : "Doddy"): \(text)"))
                .accessibilityIdentifier(message.sender == .user ? "messages.user" : "messages.doddy")
        case .file(let file):
            FileCard(file: file)
        case .infographic(let chart):
            InfographicCard(chart: chart)
        }
    }

    private var text: String { message.text ?? "" }
}

/// A file Doddy sent: its name and size, and the share sheet to open or send it on. The file is
/// read from the thread's own folder; if it is gone the card says so instead of offering it.
private struct FileCard: View {
    let file: ChatFile

    private var url: URL {
        MessagesController.directory!.appendingPathComponent(file.relativePath)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.accentText)
                .frame(width: 44, height: 44)
                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.body.weight(.semibold)).lineLimit(2)
                Text(ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            if FileManager.default.fileExists(atPath: url.path) {
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share")
            } else {
                Text("File is no longer on this iPhone")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(12)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.separator, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("messages.file")
    }

    private var symbol: String {
        switch file.kind {
        case .presentation: "rectangle.on.rectangle"
        case .document: "doc.text"
        case .spreadsheet: "tablecells"
        case .pdf: "doc.richtext"
        case .image: "photo"
        case .other: "doc"
        }
    }
}

/// An infographic: a title, a headline figure and bars, from figures the sender supplied.
private struct InfographicCard: View {
    let chart: ChatInfographic

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(chart.title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            Text(chart.headline).font(.largeTitle.bold()).tracking(-1)
            ForEach(Array(chart.rows.enumerated()), id: \.offset) { index, row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.label)
                        Spacer()
                        Text(row.display).fontWeight(.semibold)
                    }
                    .font(.footnote)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.canvas)
                            Capsule()
                                .fill(index == 0 ? Theme.orangeCue : Theme.ink.opacity(0.75))
                                .frame(width: proxy.size.width * chart.barFractions[index])
                        }
                    }
                    .frame(height: 8)
                    .accessibilityHidden(true)
                }
            }
            if let footnote = chart.footnote {
                Text(footnote).font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(14)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.separator, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("messages.infographic")
    }
}
