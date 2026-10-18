import DoddyCore
import SwiftUI

/// One call (ADR-500..507): the card to approve, the call while it is on (transcript, "Przejmij",
/// "Zakończ"), then the answer card with cost and what the server deleted. Everything shown comes
/// from the server's card and reports, or from this iPhone's store. Not compiled or run on a
/// device yet.
struct CallCaseView: View {
    @State private var model: CallCaseModel
    let list: CallCasesModel
    /// Shows another case in place of this one (a changed brief makes a new case).
    let onOpen: (StoredCallCase) -> Void
    /// Leaves this screen (the card was withdrawn).
    let onClose: () -> Void

    @State private var confirmingCall = false
    @State private var rehearsing = false
    @State private var selfScript = false
    @State private var editor: EditorItem?
    /// Acted on once the sheet that chose it has closed: presenting while a sheet is still
    /// closing fails silently.
    @State private var rehearsalChoice: CallRehearsalView.Choice?
    @State private var preparedCase: StoredCallCase?

    init(model: CallCaseModel, list: CallCasesModel, onOpen: @escaping (StoredCallCase) -> Void, onClose: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.list = list
        self.onOpen = onOpen
        self.onClose = onClose
    }

    var body: some View {
        Group {
            if model.isLive {
                CallLiveSection(model: model)
            } else {
                form
            }
        }
        .background(Theme.canvas)
        .navigationTitle(model.record.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refresh() }
        .onDisappear { model.stopWatching() }
        .sheet(isPresented: $rehearsing, onDismiss: actOnRehearsalChoice) {
            if let preview = model.preview {
                NavigationStack {
                    CallRehearsalView(preview: preview) { choice in
                        rehearsalChoice = choice
                        rehearsing = false
                    }
                }
            }
        }
        .sheet(isPresented: $selfScript) {
            if let preview = model.preview {
                NavigationStack { SelfCallScriptView(preview: preview) }
            }
        }
        .sheet(item: $editor, onDismiss: {
            if let preparedCase {
                self.preparedCase = nil
                onOpen(preparedCase)
            }
        }) { item in
            NavigationStack {
                CallBriefEditorView(list: list, draft: item.draft, replacing: model.record.result == nil ? model.record : nil) { saved in
                    preparedCase = saved
                    editor = nil
                }
            }
        }
        .confirmationDialog(confirmTitle, isPresented: $confirmingCall, titleVisibility: .visible) {
            Button("Call now") { Task { await model.approve() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Doddy says the opening line on the card first, asks the question and ends the call. You can take over or end it from this screen or the Lock Screen.")
        }
    }

    /// "Doddy dzwoni" after a rehearsal goes through the same hours check as the card's button.
    private func actOnRehearsalChoice() {
        guard let choice = rehearsalChoice else { return }
        rehearsalChoice = nil
        switch choice {
        case .callMyself:
            selfScript = true
        case .doddyCalls:
            if let preview = model.preview, CallHours.fits(Date(), maxDurationSecs: preview.maxDurationSecs) {
                confirmingCall = true
            } else {
                model.message = NSLocalizedString("Doddy calls only between 8:00 and 20:00 Polish time, and the whole call must fit. Pick a time:", comment: "")
            }
        }
    }

    private var confirmTitle: String {
        String(format: NSLocalizedString("Doddy calls %@ now?", comment: ""), model.preview?.callee.name ?? model.record.title)
    }

    private var form: some View {
        Form {
            if model.phase == .scheduled {
                Section {
                    Label(model.scheduledFor.map { String(format: NSLocalizedString("Doddy will call at %@.", comment: ""), CallCaseText.time($0)) }
                          ?? NSLocalizedString("Doddy will call at the time you picked.", comment: ""), systemImage: "clock")
                    Button("Cancel the call", role: .destructive) { Task { await model.cancel() } }
                }
            }

            if let result = model.record.result {
                CallResultSections(record: model.record, result: result)
                if model.retryable && model.canApprove {
                    retrySection
                }
            } else if model.waitingForResult {
                Section {
                    HStack { ProgressView(); Text("The call ended. Doddy is preparing the answer card…") }
                }
            } else if model.phase == .ended, model.record.result == nil {
                Section {
                    Text("The call ended, but the answer card isn't here yet.")
                    Button("Check again") { model.collect() }
                }
            }

            if let preview = model.preview, model.record.result == nil, model.phase == nil || model.phase == .scheduled {
                CallApprovalSections(preview: preview)
                if model.canApprove { approveSection(preview) }
            }

            if !model.canApprove && model.record.result == nil && model.phase == nil && !model.isWorking {
                Section {
                    if model.record.state == "cancelled" {
                        Text("This card was cancelled.")
                    } else {
                        Text("This card can't be approved any more.")
                    }
                    newCardButton
                }
            }

            if model.record.result != nil && !(model.retryable && model.canApprove) {
                Section { newCardButton }
            }

            if let message = model.message {
                Section { Label(message, systemImage: "info.circle").accessibilityIdentifier("callCase.message") }
            }
        }
        .scrollContentBackground(.hidden)
        .disabled(model.isWorking)
        .overlay { if model.isWorking { ProgressView() } }
        .refreshable { await model.refresh() }
    }

    private func approveSection(_ preview: CallPreview) -> some View {
        Section {
            if CallHours.fits(Date(), maxDurationSecs: preview.maxDurationSecs) {
                Button {
                    confirmingCall = true
                } label: {
                    Label("Doddy calls", systemImage: "phone.arrow.up.right.fill").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("callCase.approve")
            } else {
                Text("Doddy calls only between 8:00 and 20:00 Polish time, and the whole call must fit. Pick a time:")
                ForEach(model.retryTimes(), id: \.self) { time in
                    Button(String(format: NSLocalizedString("Call at %@", comment: ""), CallCaseText.time(time))) {
                        Task { await model.approve(at: time) }
                    }
                }
            }
            Button {
                rehearsing = true
            } label: {
                Label("Rehearse first", systemImage: "theatermasks")
            }
            Button {
                selfScript = true
            } label: {
                Label("I'll call myself", systemImage: "phone")
            }
            Button("Change the brief") { editor = EditorItem(draft: model.record.brief) }
            Button("Withdraw the card", role: .destructive) {
                Task { if await list.withdraw(model.record) { onClose() } }
            }
        } footer: {
            Text(String(format: NSLocalizedString("Approving sends exactly this card. It can be approved until %@; after that, make a new one.", comment: ""),
                        model.approvableUntil.map(CallCaseText.time) ?? "–"))
        }
    }

    private var retrySection: some View {
        Section {
            ForEach(model.retryTimes(), id: \.self) { time in
                Button(String(format: NSLocalizedString("Call again at %@", comment: ""), CallCaseText.time(time))) {
                    Task { await model.approve(at: time) }
                }
            }
            if let preview = model.preview, CallHours.fits(Date(), maxDurationSecs: preview.maxDurationSecs) {
                Button("Call again now") { confirmingCall = true }
            }
            Button("I'll call myself") { selfScript = true }
        } header: {
            Text("Try again")
        } footer: {
            Text("A new try uses the same card, approved again for the time you pick. Only times when the whole call fits inside 8:00–20:00.")
        }
    }

    private var newCardButton: some View {
        Button("New card from this brief") { editor = EditorItem(draft: model.record.brief) }
    }
}

// MARK: - The card to approve

/// The pre-dial card, drawn from the server's preview: exactly what will be sent.
struct CallApprovalSections: View {
    let preview: CallPreview

    var body: some View {
        Section("Who") {
            Text(preview.callee.name).font(.headline)
            Text(preview.callee.phone).monospacedDigit()
            Text(sourceText).font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        Section("Goal") {
            Text(preview.goal)
        }
        Section {
            Text("„\(preview.openingLine)”").italic()
        } header: {
            Text("Doddy says first, word for word")
        } footer: {
            Text("Then Doddy listens, may ask one short follow-up question, thanks and ends the call.")
        }
        Section("Doddy may say") {
            if preview.facts.isEmpty {
                Text("Nothing beyond the question.").foregroundStyle(Theme.secondaryText)
            }
            ForEach(Array(preview.facts.enumerated()), id: \.offset) { _, fact in
                Label(fact.text, systemImage: "checkmark.circle")
            }
        }
        Section {
            ForEach(Array(preview.forbidden.enumerated()), id: \.offset) { _, rule in
                Label(rule, systemImage: "xmark.circle")
            }
            Text("„\(preview.callbackLine)”").italic()
        } header: {
            Text("Doddy must not")
        } footer: {
            Text("If they ask for anything outside the card, Doddy says the line above and ends politely.")
        }
        Section {
            LabeledContent("Longest call", value: String(format: NSLocalizedString("%lld min", comment: ""), preview.maxDurationSecs / 60))
            Text(recordingText).font(.footnote).foregroundStyle(Theme.secondaryText)
        }
    }

    private var sourceText: String {
        let label = preview.callee.sourceLabel ?? ""
        switch preview.callee.source {
        case .contacts: return String(format: NSLocalizedString("Number from Contacts: %@", comment: ""), label)
        case .note: return label.isEmpty ? NSLocalizedString("Number from a note", comment: "")
            : String(format: NSLocalizedString("Number from a note: %@", comment: ""), label)
        case .typed: return label.isEmpty ? NSLocalizedString("Number typed in", comment: "")
            : String(format: NSLocalizedString("Number typed in, from: %@", comment: ""), label)
        }
    }

    private var recordingText: String {
        let notice = preview.notice == "off"
            ? NSLocalizedString("Doddy doesn't announce a recording (the legal basis isn't confirmed yet).", comment: "")
            : NSLocalizedString("Doddy announces that the call is recorded or transcribed.", comment: "")
        return notice + " " + NSLocalizedString("No audio is recorded. A text transcript is made; after the call it is kept on this iPhone and the server's copies are deleted.", comment: "")
    }
}

// MARK: - While the call is on

struct CallLiveSection: View {
    let model: CallCaseModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(CallCaseText.phase(model.phase ?? .unknown)).font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
                if let answered = model.answeredAt {
                    Text(answered, style: .timer).font(.title3).monospacedDigit().foregroundStyle(Theme.secondaryText)
                }
                if let preview = model.preview {
                    Text(preview.callee.name).font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.vertical, 16)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if model.lines.isEmpty {
                            Group {
                                if model.phase == .ringing {
                                    Text("Ringing…")
                                } else {
                                    Text("The transcript appears here as they talk.")
                                }
                            }
                            .foregroundStyle(Theme.secondaryText)
                        }
                        ForEach(model.lines) { line in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.isDoddy ? "Doddy" : (model.preview?.callee.name ?? NSLocalizedString("They", comment: "")))
                                    .font(.caption.weight(.semibold)).foregroundStyle(line.isDoddy ? Theme.accentText : Theme.secondaryText)
                                Text(line.text).foregroundStyle(Theme.ink)
                            }
                            .id(line.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                }
                .onChange(of: model.lines.count) {
                    if let last = model.lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .accessibilityIdentifier("callCase.transcript")

            VStack(spacing: 10) {
                if let message = model.message {
                    Text(message).font(.footnote).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
                }
                if model.phase == .takenOver {
                    Text("You're on the call. Hang up on your phone to end it.").font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                Button {
                    Task { await model.takeOver() }
                } label: {
                    Label("Take over", systemImage: "phone.fill")
                        .font(.title2.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!model.canTakeOver || model.isWorking)
                .accessibilityIdentifier("callCase.takeOver")
                .accessibilityHint("Doddy rings your phone. Answer and press 1 to join the call.")

                Button(role: .destructive) {
                    Task { await model.end() }
                } label: {
                    Label("End", systemImage: "phone.down.fill").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(!model.canEnd || model.isWorking)
                .accessibilityIdentifier("callCase.end")
            }
            .padding(16)
        }
    }
}

// MARK: - After the call

struct CallResultSections: View {
    let record: StoredCallCase
    let result: CallResultCard

    var body: some View {
        Section {
            HStack {
                Text(CallCaseText.outcome(result.outcome)).font(.headline)
                Spacer()
                Text(CallCaseText.confidence(result.confidence)).font(.footnote)
                    .foregroundStyle(result.confidence == .high ? Theme.confirmed : result.confidence == .medium ? Theme.secondaryText : Theme.error)
            }
            if let quote = result.quote {
                VStack(alignment: .leading, spacing: 4) {
                    Text("„\(quote.text)”").font(.title3).foregroundStyle(Theme.ink)
                    Text("Quoted word for word from the transcript").font(.caption).foregroundStyle(Theme.secondaryText)
                }
                .accessibilityIdentifier("callResult.quote")
            }
            Text(result.summary)
            Group {
                if result.summaryBy == "doddy_model" {
                    Text("Summary written by Claude from the transcript.")
                } else {
                    Text("Summary made from the transcript by fixed rules.")
                }
            }
            .font(.caption).foregroundStyle(Theme.secondaryText)
            ForEach(result.confidenceReasons, id: \.self) { reason in
                Label(CallCaseText.confidenceReason(reason), systemImage: "info.circle").font(.footnote)
            }
            if result.callbackPromised {
                Label("Doddy said you'd call back about something outside the card.", systemImage: "arrow.uturn.left.circle")
            }
        } header: {
            Text("Answer")
        }

        if !result.warnings.isEmpty {
            Section("Check what Doddy said") {
                ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, warning in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(CallCaseText.warning(warning.kind)).foregroundStyle(Theme.error)
                        if result.transcript.indices.contains(warning.line) {
                            Text("„\(result.transcript[warning.line].text)”").font(.footnote).italic()
                        }
                    }
                }
            }
        }

        if !result.nextStep.text.isEmpty {
            Section("Next step") { Text(result.nextStep.text) }
        }

        if !result.transcript.isEmpty {
            Section {
                DisclosureGroup("Transcript") {
                    ForEach(Array(result.transcript.enumerated()), id: \.offset) { index, line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(speaker(line.speaker)).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                            Text(line.text)
                                .fontWeight(result.quote?.line == index ? .semibold : .regular)
                        }
                    }
                }
            } footer: {
                Text("Kept only on this iPhone.")
            }
        }

        if let cost = record.cost {
            Section {
                LabeledContent("This call", value: cost.amountText)
                if cost.pending { Text("Part of the cost isn't reported yet; it is checked again when you open this call.").font(.footnote) }
                if !cost.unknownParts.isEmpty {
                    Text(String(format: NSLocalizedString("Not known: %@. Never counted as zero.", comment: ""),
                                cost.unknownParts.map(CallCaseText.component).joined(separator: ", ")))
                        .font(.footnote)
                }
                DisclosureGroup("Details") {
                    ForEach(Array(cost.items.enumerated()), id: \.offset) { _, item in
                        LabeledContent(CallCaseText.component(item.component), value: amount(item))
                    }
                }
            } header: {
                Text("Cost")
            }
        }

        if !record.deletions.isEmpty {
            Section {
                ForEach(record.deletions) { receipt in
                    Label(CallCaseText.deletion(receipt), systemImage: receipt.isConfirmed ? "checkmark.circle" : "clock")
                        .font(.footnote)
                }
            } header: {
                Text("Deleted from the servers")
            } footer: {
                Text("Twilio keeps its call log (numbers, times, duration, price) under its own retention. No audio is recorded anywhere.")
            }
        }
    }

    private func speaker(_ speaker: String) -> String {
        switch speaker {
        case "doddy": "Doddy"
        case "user": NSLocalizedString("You", comment: "")
        default: record.preview?.callee.name ?? record.brief.calleeName
        }
    }

    private func amount(_ item: CaseCost.Item) -> String {
        switch item.status {
        case "pending": NSLocalizedString("pending", comment: "")
        case "unknown": NSLocalizedString("not known", comment: "")
        default: item.amountMicros.map { String(format: "%@%.4f %@", item.status == "estimated" ? "≈ " : "", Double($0) / 1_000_000, item.currency ?? "USD") } ?? "–"
        }
    }
}

// MARK: - "Dzwonię sam"

struct SelfCallScriptView: View {
    let preview: CallPreview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Text(preview.callee.name).font(.headline)
                if let number = SelfCallScript.dialString(from: preview), DeviceSupport.hasPhoneCalls, let url = URL(string: "tel:\(number)") {
                    Link(destination: url) {
                        Label(String(format: NSLocalizedString("Call %@", comment: ""), preview.callee.phone), systemImage: "phone.fill")
                    }
                } else {
                    Text(preview.callee.phone).monospacedDigit()
                }
            } footer: {
                Text("You call from your own phone. Doddy isn't on the line and nothing is transcribed.")
            }
            Section("What to say") {
                ForEach(Array(SelfCallScript.steps(from: preview).enumerated()), id: \.offset) { _, step in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.label).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                        Text(step.text).font(.title3)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("I'll call myself")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
