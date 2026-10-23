import DoddyCore
import SwiftUI
import UIKit

/// Messages (ADR-585): the typed conversation with Doddy, saved on this iPhone until the user deletes it.
/// It looks like iMessage (owner, 23 Oct 2026): blue bubbles on the right for the user, grey on the left
/// for Doddy, tails on the last bubble of a run, Doddy's name and face at the top, three dots while he
/// writes, and a tapback on his messages with a long press or a double tap. It works at once: there is
/// no switch to turn on first, and the line at the bottom of the thread says where a question goes. Every
/// answer says whether it comes from the user's saved notes (with the notes shown) or is a general answer.
/// What each line may claim is decided by `ThreadRules`; this view only draws it.
struct MessagesView: View {
    let openSettings: () -> Void

    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PreferenceKey.assistantUseNotes) private var useNotes = true
    @State private var model: MessagesModel
    @State private var confirmingDelete = false
    /// The Doddy message whose tapback bar is open.
    @State private var reactingTo: UUID?
    @State private var threadWidth: CGFloat = 390
    @FocusState private var inputFocused: Bool

    init(repository: any MessageThreadRepository, openSettings: @escaping () -> Void = {}) {
        self.openSettings = openSettings
        _model = State(initialValue: MessagesModel(repository: repository))
    }

    /// Messages needs no switch (owner, 23 Oct 2026): the question goes as soon as it is sent.
    private var policy: AssistantPolicy { AssistantPolicy(consentGranted: true, includeNotes: useNotes) }

    /// iMessage keeps a bubble to about three quarters of the screen.
    private var bubbleMax: CGFloat { max(200, threadWidth * 0.75) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                thread
                composer
            }
            // A full-screen cover on iPad: one readable column (ADR-437).
            .readableColumn()
            .background(BubbleColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        model.cancel()
                        close()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .principal) {
                    contactHeader
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

    /// iMessage's contact at the top: his face in a circle and his name under it.
    private var contactHeader: some View {
        VStack(spacing: 2) {
            DoddyAvatar(size: 36)
            HStack(spacing: 2) {
                Text(verbatim: "Doddy")
                    .font(.caption2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Doddy")
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Thread

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.messages.isEmpty && model.error == nil && model.storage != .loading {
                        intro
                    }
                    let messages = model.messages
                    let delivered = ThreadRules.deliveredMarker(in: messages)
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let previous = index > 0 ? messages[index - 1] : nil
                        let next = index + 1 < messages.count ? messages[index + 1] : nil
                        let heading = ThreadRules.showsHeading(message, after: previous)
                        VStack(alignment: .leading, spacing: 0) {
                            if heading {
                                dateHeading(message.createdAt)
                            }
                            row(message, endsGroup: ThreadRules.endsGroup(message, before: next), delivered: delivered == message.id)
                        }
                        // Bubbles of one sender sit close together; a new sender starts a little lower.
                        .padding(.top, heading || previous == nil ? 0 : (previous?.sender == message.sender ? 2 : 10))
                        .opacity(reactingTo == nil || reactingTo == message.id ? 1 : 0.25)
                        .blur(radius: reactingTo == nil || reactingTo == message.id ? 0 : 2)
                        .zIndex(reactingTo == message.id ? 1 : 0)
                        .id(message.id)
                    }
                    if model.isSending {
                        TypingBubble()
                            .padding(.top, 10)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Doddy is writing")
                            .accessibilityIdentifier("ask.thinking")
                            .id("typing")
                    }
                    VStack(alignment: .leading, spacing: 12) {
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
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("ask.disclosure")
                    }
                    .padding(.top, 20)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                // A tap anywhere else closes the tapback bar, as in iMessage.
                .onTapGesture { if reactingTo != nil { withAnimation(.snappy(duration: 0.2)) { reactingTo = nil } } }
            }
            .scrollDismissesKeyboard(.interactively)
            // Opens at the newest message.
            .defaultScrollAnchor(.bottom)
            // Motion v2: Doddy stands on the composer's top edge; the conversation keeps 108 pt
            // above it, so the newest line can always scroll clear of him (brief rule 8).
            .contentMargins(.bottom, DoddyDirector.shared.isActive ? CGFloat(MotionLayout.listBottomInset) : 0, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { threadWidth = $0 }
            .onChange(of: model.messages.count) { _, _ in
                if let last = model.messages.last { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onChange(of: model.isSending) { _, sending in
                if sending { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("typing", anchor: .bottom) } }
            }
        }
    }

    private var intro: some View {
        VStack(spacing: 8) {
            DoddyAvatar(size: 64)
            Text("Ask me anything.")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(useNotes
                 ? "If your question is about something you saved, I'll look at the matching notes and show you which ones I used."
                 : "Your saved notes are not used. Turn them on in Settings if you want me to look at them.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
    }

    /// iMessage's centred line above a new stretch: the day in bold, then the time.
    private func dateHeading(_ date: Date) -> some View {
        (Text(Self.day(date)).fontWeight(.semibold) + Text(verbatim: " ") + Text(date, format: .dateTime.hour().minute()))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }

    private static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return NSLocalizedString("Today", comment: "") }
        if calendar.isDateInYesterday(date) { return NSLocalizedString("Yesterday", comment: "") }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ message: ThreadMessage, endsGroup: Bool, delivered: Bool) -> some View {
        switch message.sender {
        case .user: userRow(message, endsGroup: endsGroup, delivered: delivered)
        case .doddy: doddyRow(message, endsGroup: endsGroup)
        }
    }

    private func userRow(_ message: ThreadMessage, endsGroup: Bool, delivered: Bool) -> some View {
        let line = ThreadRules.deliveryLine(for: message)
        return VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .center, spacing: 6) {
                Spacer(minLength: 0)
                bubble(message.text, fromUser: true, tail: endsGroup || line != nil)
                    .accessibilityLabel("You: \(message.text)")
                if line == .notDelivered {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                }
            }
            // Only what is known: on its way, answered, or no answer yet. Never "Read".
            switch line {
            case .sending:
                Text("Sending…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
            case .notDelivered:
                Button {
                    retry(message.id)
                } label: {
                    Text("Not Delivered. Tap to try again.")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .frame(minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 30)
                .disabled(model.isSending || model.error?.canRetryNow == false)
                .accessibilityIdentifier("messages.retry")
            case nil:
                if delivered {
                    Text("Delivered")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func doddyRow(_ message: ThreadMessage, endsGroup: Bool) -> some View {
        let notes = sources(of: message)
        let open = reactingTo == message.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                bubble(message.text, fromUser: false, tail: endsGroup)
                    // His tapback sits on the bubble's top corner, in the user's blue.
                    .overlay(alignment: .topTrailing) {
                        if let reaction = message.reaction {
                            TapbackBadge(reaction: reaction)
                                .offset(x: 14, y: -16)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    // The tapback bar opens above the bubble.
                    .overlay(alignment: .topLeading) {
                        if open {
                            TapbackBar(current: message.reaction) { reaction in
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.snappy(duration: 0.25)) {
                                    model.react(reaction, to: message.id)
                                    reactingTo = nil
                                }
                            }
                            .offset(y: -58)
                            .transition(.scale(scale: 0.6, anchor: .bottomLeading).combined(with: .opacity))
                        }
                    }
                    .onTapGesture(count: 2) { openTapbacks(for: message) }
                    .onLongPressGesture(minimumDuration: 0.35) { openTapbacks(for: message) }
                    .accessibilityLabel(accessibilityText(message))
                    .accessibilityIdentifier("ask.answer")
                    .accessibilityActions {
                        ForEach(ThreadMessage.Reaction.allCases, id: \.self) { reaction in
                            Button(TapbackBar.name(reaction)) { model.react(reaction, to: message.id) }
                        }
                    }
                Spacer(minLength: 0)
            }
            .padding(.top, message.reaction == nil ? 0 : 12)

            if open {
                Button {
                    UIPasteboard.general.string = message.text
                    withAnimation(.snappy(duration: 0.2)) { reactingTo = nil }
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 4)
                .transition(.opacity)
            }

            // Where the answer comes from, small and quiet under the bubble.
            Group {
                switch message.basis {
                case .savedNotes:
                    VStack(alignment: .leading, spacing: 4) {
                        Label("From your saved notes", systemImage: "note.text")
                            .font(.caption2.weight(.semibold))
                            .accessibilityIdentifier("ask.basis.notes")
                        ForEach(notes) { record in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.currentText).lineLimit(3)
                                    .font(.footnote)
                                Text("\(record.source.displayName) · \(DateText.full(record.capturedAt))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .frame(maxWidth: bubbleMax, alignment: .leading)
                            .background(BubbleColors.received.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityElement(children: .combine)
                        }
                        // A saved conversation outlives the notes it cited: say so rather than drop them quietly.
                        if store.hasLoaded && notes.count < message.noteIDs.count {
                            Text("Some of these notes have since been deleted.")
                                .font(.caption2)
                        }
                    }
                case .general, nil:
                    if endsGroup {
                        Label("Not from your notes. This is a general answer.", systemImage: "info.circle")
                            .font(.caption2)
                            .accessibilityIdentifier("ask.basis.general")
                    }
                }
                if message.notesSent > 0 {
                    Text(message.notesSent == 1 ? "1 saved note was sent with this question." : "\(message.notesSent) saved notes were sent with this question.")
                        .font(.caption2)
                }
                if message.notesSearchFailed {
                    Label("Couldn't search your notes this time, so none were used.", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(Theme.error)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bubble(_ text: String, fromUser: Bool, tail: Bool) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(fromUser ? Color.white : Color.primary)
            .padding(.vertical, 7)
            .padding(.leading, fromUser ? 12 : 16)
            .padding(.trailing, fromUser ? 16 : 12)
            .background(
                MessageBubbleShape(fromUser: fromUser, tail: tail)
                    .fill(fromUser ? BubbleColors.sent : BubbleColors.received)
            )
            .frame(maxWidth: bubbleMax, alignment: fromUser ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func openTapbacks(for message: ThreadMessage) {
        guard ThreadRules.canReact(to: message) else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        inputFocused = false
        withAnimation(.snappy(duration: 0.25)) { reactingTo = message.id }
    }

    private func accessibilityText(_ message: ThreadMessage) -> String {
        guard let reaction = message.reaction else { return "Doddy: \(message.text)" }
        return String(format: NSLocalizedString("Doddy: %@. You reacted: %@", comment: ""), message.text, TapbackBar.name(reaction))
    }

    /// The notes an answer cited, in the order it cited them, as they are now.
    private func sources(of message: ThreadMessage) -> [MemoryRecord] {
        message.noteIDs.compactMap { id in store.memories.first { $0.id == id } }
    }

    private func errorCard(_ error: AssistantError) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProblemView(message: error.userMessage)
                .accessibilityIdentifier("ask.error")
            if let failed = lastNotAnswered, error.canRetryNow {
                Button("Try again") { retry(failed.id) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.isSending)
                    .accessibilityIdentifier("ask.retry")
            }
            if lastNotAnswered != nil {
                Text("Your message is in the conversation. Tap it to send it again. Your saved notes are not affected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Your question is still in the box. Your saved notes are not affected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The newest message, when it got no answer.
    private var lastNotAnswered: ThreadMessage? {
        guard let last = model.messages.last, ThreadRules.canRetry(last) else { return nil }
        return last
    }

    // MARK: Composer

    /// iMessage's bar: a round + on the left (whether notes are used, and Settings), then the rounded box with the send arrow inside it.
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Toggle("Use my saved notes", isOn: $useNotes)
                Button("Settings", systemImage: "gear") { close(); openSettings() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(BubbleColors.received, in: Circle())
            }
            .accessibilityLabel("More options")
            .accessibilityIdentifier("messages.plus")
            HStack(alignment: .bottom, spacing: 4) {
                TextField("Message", text: $model.draft, axis: .vertical)
                    .lineLimit(1...6)
                    .font(.body)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .disabled(model.isSending)
                    .padding(.leading, 12)
                    .padding(.vertical, 7)
                    .accessibilityIdentifier("ask.input")
                if model.isSending {
                    Button { model.cancel() } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(BubbleColors.sent)
                    }
                    .accessibilityLabel("Stop")
                    .accessibilityIdentifier("ask.stop")
                    .padding(.trailing, 3).padding(.bottom, 3)
                } else {
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, model.canSend ? BubbleColors.sent : Color(.systemGray3))
                    }
                    .disabled(!model.canSend)
                    .accessibilityLabel("Send")
                    .accessibilityIdentifier("ask.send")
                    // His zone stays 24 pt from Send (brief rule 8).
                    .motionMark("send")
                    .padding(.trailing, 3).padding(.bottom, 3)
                }
            }
            .frame(minHeight: 36)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(.systemGray4), lineWidth: 1))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(BubbleColors.background)
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

    /// nil when this build has no messaging server address, or the storage is not open.
    private func service() -> AssistantService? {
        guard let wiring = store.environment.assistant else { return nil }
        // Private notes (ADR-310) are never sent with a question.
        let recall = ShareableRecallService(base: store.environment.recallService) { PrivateNotesStore.current().ids }
        return wiring.service(recall: recall)
    }
}

// MARK: - iMessage pieces

/// iMessage's colours: the system blue for what the user sends, the light or dark grey for what
/// comes in, on the plain system background.
private enum BubbleColors {
    static let sent = Color(uiColor: .systemBlue)
    static let received = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.149, green: 0.149, blue: 0.161, alpha: 1)
            : UIColor(red: 0.914, green: 0.914, blue: 0.922, alpha: 1)
    })
    static let background = Color(uiColor: .systemBackground)
}

/// A message bubble: a rounded box, with iMessage's tail at the bottom corner on the sender's side
/// when it is the last of a run. Without a tail it keeps the same inset so a run lines up.
struct MessageBubbleShape: Shape {
    let fromUser: Bool
    let tail: Bool

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let r = min(18, h / 2)
        let k = r * 0.4475
        var path = Path()
        if tail {
            // Drawn for the right-hand side, then mirrored for Doddy's.
            path.move(to: CGPoint(x: w - r, y: h))
            path.addLine(to: CGPoint(x: r, y: h))
            path.addCurve(to: CGPoint(x: 0, y: h - r), control1: CGPoint(x: k, y: h), control2: CGPoint(x: 0, y: h - k))
            path.addLine(to: CGPoint(x: 0, y: r))
            path.addCurve(to: CGPoint(x: r, y: 0), control1: CGPoint(x: 0, y: k), control2: CGPoint(x: k, y: 0))
            path.addLine(to: CGPoint(x: w - r - 4, y: 0))
            path.addCurve(to: CGPoint(x: w - 4, y: r), control1: CGPoint(x: w - 4 - k, y: 0), control2: CGPoint(x: w - 4, y: k))
            path.addLine(to: CGPoint(x: w - 4, y: max(r, h - 11)))
            path.addCurve(to: CGPoint(x: w, y: h), control1: CGPoint(x: w - 4, y: h - 1), control2: CGPoint(x: w, y: h))
            path.addCurve(to: CGPoint(x: w - 11, y: h - 4), control1: CGPoint(x: w - 4, y: h + 0.4), control2: CGPoint(x: w - 8, y: h - 1))
            path.addCurve(to: CGPoint(x: w - r, y: h), control1: CGPoint(x: w - 14, y: h), control2: CGPoint(x: w - r + 2, y: h))
            path.closeSubpath()
        } else {
            path.addRoundedRect(in: CGRect(x: 0, y: 0, width: w - 4, height: h), cornerSize: CGSize(width: r, height: r), style: .continuous)
        }
        guard !fromUser else { return path.offsetBy(dx: rect.minX, dy: rect.minY) }
        return path
            .applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -w, y: 0))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Three grey dots in a bubble while Doddy writes his answer, as in iMessage. Still under Reduce Motion.
private struct TypingBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    let wave = reduceMotion ? 0.5 : (sin(t * 6 - Double(i) * 0.9) + 1) / 2
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .opacity(0.35 + 0.5 * wave)
                        .scaleEffect(0.85 + 0.15 * wave)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.leading, 4)
            .background(MessageBubbleShape(fromUser: false, tail: true).fill(BubbleColors.received))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The bar of six tapbacks that opens above one of Doddy's messages.
private struct TapbackBar: View {
    let current: ThreadMessage.Reaction?
    let choose: (ThreadMessage.Reaction) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ThreadMessage.Reaction.allCases, id: \.self) { reaction in
                Button { choose(reaction) } label: {
                    TapbackGlyph(reaction: reaction, size: 18)
                        .foregroundStyle(current == reaction ? Color.white : Color.secondary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(current == reaction ? BubbleColors.sent : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.name(reaction))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(BubbleColors.received, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .fixedSize()
    }

    static func name(_ reaction: ThreadMessage.Reaction) -> String {
        switch reaction {
        case .heart: NSLocalizedString("Love", comment: "")
        case .thumbsUp: NSLocalizedString("Like", comment: "")
        case .thumbsDown: NSLocalizedString("Dislike", comment: "")
        case .haha: NSLocalizedString("Laugh", comment: "")
        case .emphasis: NSLocalizedString("Emphasize", comment: "")
        case .question: NSLocalizedString("Question", comment: "")
        }
    }
}

/// A tapback kept on one of Doddy's messages: the user's blue circle on the bubble's corner.
private struct TapbackBadge: View {
    let reaction: ThreadMessage.Reaction

    var body: some View {
        TapbackGlyph(reaction: reaction, size: 13)
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(BubbleColors.sent))
            .overlay(Circle().strokeBorder(BubbleColors.background, lineWidth: 2))
            .accessibilityHidden(true)
    }
}

private struct TapbackGlyph: View {
    let reaction: ThreadMessage.Reaction
    let size: CGFloat

    var body: some View {
        switch reaction {
        case .heart: Image(systemName: "heart.fill").font(.system(size: size, weight: .semibold))
        case .thumbsUp: Image(systemName: "hand.thumbsup.fill").font(.system(size: size, weight: .semibold))
        case .thumbsDown: Image(systemName: "hand.thumbsdown.fill").font(.system(size: size, weight: .semibold))
        case .haha:
            Text(verbatim: "HA\nHA")
                .font(.system(size: size * 0.55, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .lineSpacing(-2)
        case .emphasis: Image(systemName: "exclamationmark.2").font(.system(size: size, weight: .heavy))
        case .question: Image(systemName: "questionmark").font(.system(size: size, weight: .heavy))
        }
    }
}

/// His face in a circle, cut from the pack's listening pose (`WholeDoddy_listening`), as on the island.
private struct DoddyAvatar: View {
    let size: CGFloat

    var body: some View {
        Image(decorative: "WholeDoddy_listening")
            .resizable()
            .frame(width: size * 1.7, height: size * 2.55)
            .frame(width: size, height: size, alignment: .top)
            .background(Color(uiColor: .systemGray5))
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}
