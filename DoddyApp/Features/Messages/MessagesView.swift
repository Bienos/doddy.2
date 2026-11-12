import DoddyCore
import Combine
import QuickLook
import SwiftUI
import UIKit

/// Messages (ADR-585): the typed conversation with Doddy, saved on this iPhone until the user deletes it.
/// On unless the person turns it off (Settings → Ask Doddy; decision 2026-11-09-messages-on-by-default). Every answer says whether it comes from the user's saved
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
    @AppStorage(PreferenceKey.assistantConsent) private var consent = PreferenceKey.assistantConsentDefault
    @AppStorage(PreferenceKey.assistantUseNotes) private var useNotes = true
    @State private var model: MessagesModel
    @State private var confirmingDelete = false
    @State private var showingPrivacy = false
    /// The plan screen opened from a plan offer (ADR-626).
    @State private var planRequest: PlanAskRequest?
    @FocusState private var inputFocused: Bool
    /// Files Doddy made elsewhere (a voice conversation, a task), offered under the thread. Read from his server each time.
    @State private var files = MadeDocumentsModel()
    @State private var preview: URL?
    /// A finished task opened from its card.
    @State private var openedTask: OpenedTask?
    /// Calls Doddy made (ADR-730), read from this iPhone's own copy of them. Shown under the thread; never part of it.
    @Environment(\.appEnvironment) private var environment
    @State private var calls: [StoredCallCase] = []
    /// A finished call opened from its card: its page in Settings, where the recap is.
    @State private var openedCall: OpenedCall?

    /// - Parameter draft: text already in the box, for the person to read, change and send
    ///   themselves (the Apple Health week summary, ADR-622). Nothing is sent without their tap.
    /// - Parameters:
    ///   - photo: a photo chosen on Home's + menu, shown above the box until Send or until removed.
    ///   - file: a file chosen on Home's + menu, the same way.
    init(repository: any MessageThreadRepository, draft: String = "", photo: AssistantImage? = nil, file: AssistantFile? = nil,
         openSettings: @escaping () -> Void = {}) {
        self.openSettings = openSettings
        // Messages on the web (owner, 28 Oct 2026: always on): the thread is copied to Doddy's server after every change.
        let model = MessagesModel(repository: repository, sync: ServerThreadSync(), actionScope: { DeviceMessageActions.accountScope })
        model.draft = draft
        model.photo = photo
        if let file { model.file = file }
        _model = State(initialValue: model)
    }

    private var policy: AssistantPolicy { AssistantPolicy(consentGranted: consent, includeNotes: useNotes, localActionsEnabled: DeviceMessageActions.accountScope != nil) }

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
                            Button("Privacy", systemImage: "hand.raised") { showingPrivacy = true }
                                .accessibilityIdentifier("messages.privacy")
                            Button("Delete conversation", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                                .disabled(model.isSending || model.runningLocalAction != nil)
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
                Text("It is removed from this iPhone and from its copy on Doddy's server for Doddy Web. Your saved notes are not affected.")
            }
            .alert("Privacy", isPresented: $showingPrivacy) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This conversation is saved on this iPhone until you delete it. Your question, a photo or file you add to it, the last few messages and any notes shown under an answer are sent to Doddy's server and on to Anthropic to write the reply. A photo or file is not kept on this iPhone or the server; only a file's name stays in this conversation. A copy of this conversation, without photos or files, is kept encrypted on Doddy's server so you can read it in Doddy Web.")
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
            .alert("Couldn't delete the copy on the web", isPresented: Binding(
                get: { model.webDeleteFailed },
                set: { if !$0 { model.clearWebDeleteFailure() } }
            )) {
                Button("Try again") { Task { await model.deleteWebCopy() } }
                Button("Later", role: .cancel) { model.clearWebDeleteFailure() }
            } message: {
                Text("The conversation is gone from this iPhone, but Doddy's server didn't confirm its copy for Doddy Web is deleted. It may still show on the web until it is.")
            }
        }
        .foregroundStyle(Theme.ink)
        .task { await model.load() }
        // Something Doddy finished while this screen is open (ThreadInbox): shown once, already saved.
        .onReceive(NotificationCenter.default.publisher(for: ThreadInbox.delivered)) { note in
            if let message = note.object as? ThreadMessage { model.receive(message) }
        }
        // Only once Ask Doddy is on: opening Messages with it off makes no call to Doddy's server.
        // The files list belongs to the person (their own session, as the Files sheet reads it), so it doesn't wait for
        // Ask Doddy. It keeps looking while Messages is open: a file takes a minute or two to make.
        .task { await keepFilesFresh() }
        // A new message may be a file just started: read the list now so its dot shows at once, not after the slow poll.
        .onChange(of: model.messages.count) { _, _ in
            Task { await files.refresh(clearingDownloads: false) }
        }
        .quickLookPreview($preview)
        .task { await ErrandsModel.shared.load() }
        // A failed read shows no cards here; the calls themselves are in Settings › Phone calls.
        .task { calls = (try? await environment.callCaseRepository.list()) ?? [] }
        .sheet(item: $openedTask) { opened in
            NavigationStack { ErrandDetailView(id: opened.id) }
        }
        .sheet(item: $openedCall) { opened in
            NavigationStack {
                CallCasesView(openCase: opened.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { openedCall = nil } }
                    }
            }
        }
        // Motion v2 (MV4, Q2): he comes up with this cover, on its composer, and is back on
        // Home's stage as it goes.
        .onAppear {
            DoddyDirector.shared.askOpened()
            // A result that arrives now shows here, with no notice over it (ResultNotice).
            ThreadInbox.isOnScreen = true
        }
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
            ThreadInbox.isOnScreen = false
        }
        .onChange(of: DeviceMessageActions.accountScope) { _, _ in model.cancel() }
        .onChange(of: consent) { _, enabled in if !enabled { model.cancel() } }
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
                    // One timeline (owner, 11 Nov 2026): a file Doddy made without a bubble takes its place by the
                    // time it was made, instead of a section under the newest message that looked pinned there.
                    ForEach(timeline) { item in
                        switch item {
                        case .message(let index, let message):
                            messageBlock(at: index, message)
                                .id(message.id)
                        case .localFile(let file):
                            localFileCard(file)
                        case .serverFile(let document):
                            serverFileCard(document)
                        }
                    }
                    taskResults
                    callResults
                    if let problem = files.downloadProblem ?? LocalMadeFilesStore.shared.problem {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.error)
                            .padding(.top, 8)
                            .accessibilityIdentifier("messages.attachmentProblem")
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
                        // Said once, where a new conversation starts, and always in the menu's Privacy; a running thread
                        // isn't ended by a paragraph of small print.
                        if model.messages.isEmpty {
                            Text("This conversation is saved on this iPhone until you delete it. Your question, a photo or file you add to it, the last few messages and any notes shown under an answer are sent to Doddy's server and on to Anthropic to write the reply. A photo or file is not kept on this iPhone or the server; only a file's name stays in this conversation. A copy of this conversation, without photos or files, is kept encrypted on Doddy's server so you can read it in Doddy Web.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .accessibilityIdentifier("ask.disclosure")
                        }
                    }
                    .padding(.top, 14)
                    // The end of the thread: whatever comes in at the bottom scrolls into view (see `endSignature`).
                    Color.clear
                        .frame(height: 1)
                        .id(Self.threadEnd)
                        .accessibilityHidden(true)
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
            // Anything new at the bottom scrolls into view, not only a new message (owner, 12 Nov 2026: "dodaje kartę,
            // która się nie pojawia, muszę sobie scrollować"): a file Doddy made, a task he finished, a call's answer,
            // the typing bubble, a problem. Only when something was added: a delete never moves the conversation.
            .onChange(of: endSignature) { old, new in
                guard ThreadEnd.grew(from: old, to: new) else { return }
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(Self.threadEnd, anchor: .bottom) }
            }
        }
    }

    private static let threadEnd = "messages.threadEnd"

    /// What is at the end of the thread, counted cheaply (no sorting): when any of it grows, the thread scrolls down.
    private var endSignature: ThreadEnd {
        let ready: Int
        if case .ready(let list) = files.load { ready = list.documents.count } else { ready = 0 }
        return ThreadEnd(
            messages: model.messages.count,
            files: ready + LocalMadeFilesStore.shared.files.count,
            finishedTasks: ErrandsModel.shared.errands.filter { $0.state.isFinished }.count,
            calls: calls.count,
            sending: model.isSending,
            problem: model.error != nil || files.downloadProblem != nil)
    }

    /// Tasks Doddy finished in the background this week (ADR-570), read from this iPhone's own copy of them. A tap
    /// opens the task's result; nothing is added to the saved thread and nothing is sent.
    @ViewBuilder
    private var taskResults: some View {
        let shown = ThreadTaskResults.shown(ErrandsModel.shared.errands, now: Date(), thread: model.messages)
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tasks Doddy finished")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                ForEach(shown) { errand in
                    Button { openedTask = OpenedTask(id: errand.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: errand.state == .done ? "checkmark.circle" : "exclamationmark.circle")
                                .font(.title3)
                                .foregroundStyle(errand.state == .done ? Theme.accentText : Theme.error)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: errand.title)
                                    .font(.body.bold())
                                    .multilineTextAlignment(.leading)
                                if errand.state == .done { Text("See what Doddy found.") } else { Text("Couldn't finish. See why.") }
                            }
                            .font(.footnote)
                            .foregroundStyle(Theme.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("messages.taskResult")
                }
            }
            .padding(.top, 14)
            .padding(.trailing, 40)
        }
    }

    /// Calls Doddy made for the person this week (ADR-730): "Doddy called Anna", and a tap opens that call's page in
    /// Settings, where the recap is (and, for the owner's account only, the words). Read from this iPhone's own copy;
    /// nothing is added to the saved thread, so nothing about a call is copied to Doddy Web or sent to the model.
    @ViewBuilder
    private var callResults: some View {
        let shown = ThreadCallResults.shown(calls, now: Date())
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Calls Doddy made")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                ForEach(shown) { record in
                    Button { openedCall = OpenedCall(id: record.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "phone.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.accentText)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: String(format: NSLocalizedString("Doddy called %@.", comment: "Messages: a call Doddy made; the name of the person he called"), record.brief.calleeName))
                                    .font(.body.bold())
                                    .multilineTextAlignment(.leading)
                                Text("See the recap.")
                            }
                            .font(.footnote)
                            .foregroundStyle(Theme.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("messages.callResult")
                }
            }
            .padding(.top, 14)
            .padding(.trailing, 40)
        }
    }

    /// The server's ready files that are not already bubbles above (the person's own list, read with their session).
    private var madeDocuments: [MadeDocument] {
        guard case .ready(let list) = files.load else { return [] }
        return ThreadAttachments.shown(documents: list.documents, thread: model.messages, now: Date())
    }

    /// Files Doddy is making now: shown at once, so "On it" by voice has something to point at.
    private var makingDocuments: [MadeDocument] {
        guard case .ready(let list) = files.load else { return [] }
        return ThreadAttachments.inProgress(documents: list.documents, thread: model.messages, now: Date())
    }

    /// Reads the files list when Messages opens, then every few seconds while one is being made and slowly otherwise,
    /// until the screen closes. Quiet: it never deletes a file that is open in Quick Look.
    private func keepFilesFresh() async {
        await files.refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(files.isMaking(now: Date()) ? 6 : 30))
            guard !Task.isCancelled else { return }
            await files.refresh(clearingDownloads: false)
        }
    }

    /// Files Doddy made on this iPhone in a voice conversation and kept for a week (the deck from `make_presentation`).
    /// On the iPhone only: they need neither Ask Doddy nor the server.
    private var localFiles: [LocalMadeFile] {
        LocalMadeFiles.shown(LocalMadeFilesStore.shared.files, now: Date())
    }

    /// The thread with the files Doddy made that have no bubble of their own, each at the time it was made.
    private var timeline: [ThreadTimeline.Item] {
        ThreadTimeline.items(messages: model.messages, local: localFiles, server: madeDocuments + makingDocuments)
    }

    /// A file made on this iPhone in a voice conversation (kept a week). A tap opens it in Quick Look, whose Share
    /// button saves or sends it; long-press to delete it.
    private func localFileCard(_ file: LocalMadeFile) -> some View {
        Button {
            preview = LocalMadeFilesStore.shared.url(for: file)
        } label: {
            LocalMadeFileRow(file: file)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) {
                LocalMadeFilesStore.shared.remove(file.id)
            }
        }
        .padding(.top, 8)
        .padding(.trailing, 40)
        .accessibilityIdentifier("messages.localFile")
    }

    /// A file on Doddy's server with no bubble in this thread: tappable once ready, "being made" until then.
    private func serverFileCard(_ document: MadeDocument) -> some View {
        Button {
            Task { preview = await files.download(document) }
        } label: {
            MadeDocumentRow(document: document, downloading: files.downloading == document.id)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(files.downloading != nil || document.status != .ready)
        .padding(.top, 8)
        .padding(.trailing, 40)
        .accessibilityIdentifier(document.status == .ready ? "messages.attachment" : "messages.attachmentMaking")
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
            if message.hasPhoto {
                // The photo itself was not kept (on this iPhone or the server); the thread only says one was sent.
                Label("Photo", systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.trailing, 6)
                    .accessibilityIdentifier("messages.photoSent")
            }
            if let name = message.attachedFileName {
                // The file itself was not kept (on this iPhone or the server); the thread keeps only its name.
                Label { Text(verbatim: name) } icon: { Image(systemName: "doc") }
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.trailing, 6)
                    .accessibilityIdentifier("messages.fileSent")
            }
            HStack(spacing: 0) {
                Spacer(minLength: 56)
                MessageBubble(text: message.text, fromUser: true, tail: tail)
                    .accessibilityLabel(String(format: NSLocalizedString("You: %@", comment: ""), message.text))
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
            case .notDeliveredPhoto:
                Text("No answer. The photo wasn't kept, so add it again to ask.")
                    .font(.caption)
                    .foregroundStyle(Theme.error)
                    .padding(.trailing, 6)
                    .accessibilityIdentifier("messages.photoNotDelivered")
            case .notDeliveredFile:
                Text("No answer. The file wasn't kept, so attach it again to ask.")
                    .font(.caption)
                    .foregroundStyle(Theme.error)
                    .padding(.trailing, 6)
                    .accessibilityIdentifier("messages.fileNotDelivered")
            case nil:
                EmptyView()
            }
        }
    }

    private func doddyRow(_ message: ThreadMessage, tail: Bool) -> some View {
        let notes = sources(of: message)
        return VStack(alignment: .leading, spacing: 6) {
            // A file Doddy made is a card with Open and Share; it is not an answer, so it has no "from your notes"
            // line. A file Doddy delivered from a voice conversation has a line of his above it (ThreadDelivery).
            if let document = message.document {
                // What the server says now, not the words the bubble was saved with (11 Nov 2026): "ready" once it
                // lists the file ready, and a failure said plainly instead of a card that looks ready to open.
                let state = fileState(document)
                if let caption = state.caption(for: message, polish: Self.polish) {
                    HStack(spacing: 0) {
                        MessageBubble(text: caption, fromUser: false, tail: false)
                            .accessibilityLabel(Text(verbatim: "Doddy: \(caption)"))
                        Spacer(minLength: 56)
                    }
                }
                let making = state == .making
                if making {
                    WorkingDot()
                        .padding(.leading, 18)
                        .padding(.bottom, 2)
                }
                fileBubble(document, making: making, failed: state == .failed)
                if !making && state != .failed {
                    MadeFileShareButton(link: document.url)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .padding(.leading, 14)
                }
            } else {
                HStack(spacing: 0) {
                    MessageBubble(text: message.text, fromUser: false, tail: tail)
                        .accessibilityLabel(Text(verbatim: "Doddy: \(message.text)"))
                        .accessibilityIdentifier("ask.answer")
                    Spacer(minLength: 56)
                }
            }

            // A finished task Doddy delivered (ThreadDelivery: the message has the task's id): its whole result opens here.
            if message.document == nil, let task = ErrandsModel.shared.errand(message.id) {
                Button {
                    openedTask = OpenedTask(id: task.id)
                } label: {
                    Label(task.state == .done ? "See everything Doddy found" : "See why", systemImage: "chevron.right.circle")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .padding(.leading, 14)
                .accessibilityIdentifier("messages.deliveredTask")
            }

            // Where the answer came from, small and grey under the bubble, as a caption would be.
            if message.document == nil && !message.isLocalAction && ErrandsModel.shared.errand(message.id) == nil {
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
                                Text(verbatim: "\(record.source.displayName) · \(DateText.full(record.capturedAt))")
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
                case .general:
                    Label("Not from your notes. This is a general answer.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("ask.basis.general")
                case nil: EmptyView()
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
            if let action = model.localActions[message.id] {
                LocalMessageActionCard(action: action, busy: model.runningLocalAction != nil,
                    confirm: { Task { await model.confirmLocalAction(message.id, using: DeviceMessageActions(store: store, polish: Locale.current.language.languageCode?.identifier == "pl")) } },
                    dismiss: { model.dismissLocalAction(message.id) })
            }
            if model.runningLocalAction == message.id { ProgressView().accessibilityLabel("Working") }
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
    private func fileBubble(_ document: ThreadDocument, making: Bool, failed: Bool = false) -> some View {
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
                        if failed {
                            Text(verbatim: "·")
                            Text("Not made")
                        } else if !making {
                            Text(verbatim: "·")
                            Text("Tap to open")
                        }
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
        // Not tappable while it is being made, or when it failed: the link would only say so.
        .disabled(making || failed)
        .opacity(failed ? 0.6 : 1)
        .padding(.trailing, 40)
        .accessibilityIdentifier("messages.file")
    }

    /// True while the server's files list (read every few seconds while Messages is open) says this file is still being
    /// made. Unknown, not yet read, or no longer in the list all read as "not making": the card opens as before.
    private func fileState(_ document: ThreadDocument) -> ThreadFileState {
        guard case .ready(let list) = files.load else { return .unknown }
        return ThreadFileState.of(document, in: list.documents)
    }

    /// The app is shown in Polish (the bubble's words are chosen in DoddyCore, like the delivered ones).
    private static var polish: Bool {
        (Bundle.main.preferredLocalizations.first ?? "en").lowercased().hasPrefix("pl")
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
        case .needsDetails: Text("Add a bit more detail, such as who it is for or what it is for, and try again. Nothing was made.")
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

/// A finished task opened from Messages, for `.sheet(item:)`.
private struct OpenedTask: Identifiable {
    let id: UUID
}

/// A finished call opened from Messages, for `.sheet(item:)` (the call case's id).
private struct OpenedCall: Identifiable {
    let id: UUID
}

/// The box at the bottom: a plus button, a capsule with the text and a round send button inside it.
/// Plus holds "Attach a file" and the one setting there is (use saved notes or not); voice notes are not
/// offered because they are not built.
private struct MessagesComposer: View {
    @Bindable var model: MessagesModel
    @Binding var useNotes: Bool
    var focus: FocusState<Bool>.Binding
    let send: () -> Void
    @State private var dictation = MessageDictation()
    /// What was in the box when the mic was tapped; the words heard are added after it.
    @State private var dictationBase = ""
    /// iOS's file picker for "Attach a file".
    @State private var choosingFile = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            if let file = model.file {
                MessageFileChip(file: file) { model.file = nil }
            }
            if let photo = model.photo {
                MessagePhotoChip(photo: photo) { model.photo = nil }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button { choosingFile = true } label: { Label("Attach a file", systemImage: "paperclip") }
                        .disabled(model.isSending)
                        .accessibilityIdentifier("messages.attachFile")
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

                MessagePhotoButton(photo: $model.photo, isDisabled: model.isSending)

                HStack(alignment: .bottom, spacing: 6) {
                    TextField("Ask a question", text: $model.draft, axis: .vertical)
                        .lineLimit(1...5)
                        .focused(focus)
                        .submitLabel(.send)
                        .onSubmit { send() }
                        .disabled(model.isSending)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("ask.input")
                    micButton
                        .padding(.bottom, 3)
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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.canvas)
        // Motion v2 (Q2): the composer is "the composer" he stands on, left of Send, and rides
        // with the keyboard.
        .motionSurface(.composer)
        .attachFileImporter(isPresented: $choosingFile) { model.file = $0 }
        .onChange(of: model.isSending) { _, sending in if sending { dictation.stop() } }
        // Dictation listens only while this screen is in front (ADR-676): the app may run in the
        // background for a conversation, and the microphone must not stay on for a box nobody sees.
        .onChange(of: scenePhase) { _, phase in if phase != .active { dictation.stop() } }
        .onDisappear { dictation.stop() }
    }

    /// Dictation: tap to talk, tap again to stop. The words land in the box to check; Send is still the person's tap.
    @ViewBuilder
    private var micButton: some View {
        if !model.isSending {
            VStack(alignment: .trailing, spacing: 2) {
                Button(action: toggleDictation) {
                    Image(systemName: dictation.isListening ? "stop.circle.fill" : "mic")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(dictation.isListening ? Theme.orangeCue : Theme.secondaryText)
                        .frame(width: 30, height: 30)
                        .contentShape(Circle().inset(by: -6))
                }
                .accessibilityLabel(dictation.isListening ? Text("Stop dictating") : Text("Dictate"))
                .accessibilityIdentifier("messages.mic")
                if case .failed(let reason) = dictation.state {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture { dictation.clearFailure() }
                        .accessibilityIdentifier("messages.mic.error")
                }
            }
        }
    }

    private func toggleDictation() {
        if dictation.isListening {
            dictation.stop()
            return
        }
        dictationBase = model.draft
        // Whether the microphone is free is asked of the audio session's owner when it starts (ADR-695).
        Task {
            await dictation.start { spoken in
                model.draft = DictationRules.merged(base: dictationBase, spoken: spoken)
            }
        }
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
    static var onOrange: Color { Theme.inkOnOrange }
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
                // This iPhone only, and gone from the clipboard after two minutes, as a note's copy is (ADR-724).
                Button("Copy", systemImage: "doc.on.doc") { NoteClipboard.copy(text) }
            }
    }

    /// The text with http and https addresses made tappable.
    private static func linked(_ text: String) -> AttributedString {
        LinkedText.attributed(text)
    }
}

/// The counts at the end of the conversation (`MessagesView.endSignature`).
private struct ThreadEnd: Equatable {
    var messages: Int
    var files: Int
    var finishedTasks: Int
    var calls: Int
    var sending: Bool
    var problem: Bool

    /// Something was added at the bottom: a count went up, the typing bubble or a problem appeared.
    static func grew(from old: ThreadEnd, to new: ThreadEnd) -> Bool {
        new.messages > old.messages || new.files > old.files || new.finishedTasks > old.finishedTasks || new.calls > old.calls
            || (new.sending && !old.sending) || (new.problem && !old.problem)
    }
}

/// Bubble text with its web addresses made tappable, worked out once per text (12 Nov 2026): every redraw of the
/// conversation used to build a new link detector and scan every visible bubble again.
@MainActor
private enum LinkedText {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static var cache: [String: AttributedString] = [:]
    /// About a screenful of bubbles and the history around it; the cache starts again when it is full.
    private static let limit = 400

    static func attributed(_ text: String) -> AttributedString {
        if let held = cache[text] { return held }
        let out = scan(text)
        if cache.count >= limit { cache.removeAll(keepingCapacity: true) }
        cache[text] = out
        return out
    }

    private static func scan(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        guard text.contains("."), let detector else { return out }
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
        .accessibilityLabel("Working on it…")
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

/// One quiet dot above a file Doddy is still making: it breathes (opacity only) and stops when Reduce Motion is on.
private struct WorkingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(Theme.secondaryText)
            .frame(width: 8, height: 8)
            .opacity(reduceMotion ? 0.7 : (dim ? 0.25 : 1))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dim)
            .onAppear { dim = true }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Working on it…")
            .accessibilityIdentifier("messages.fileWorking")
    }
}

/// One file Doddy made on this iPhone, as a card under the thread.
struct LocalMadeFileRow: View {
    let file: LocalMadeFile

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(Theme.accentText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: file.title)
                    .lineLimit(2)
                Text(String(format: NSLocalizedString("%@ · kept on this iPhone for a week", comment: "Messages: a file Doddy made on this iPhone; the first value is its kind, for example Deck"), file.label))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch file.kind {
        case "deck": "rectangle.on.rectangle"
        case "doc": "doc.text"
        case "spreadsheet": "tablecells"
        case "pdf": "doc.richtext"
        default: "doc.plaintext"
        }
    }
}
