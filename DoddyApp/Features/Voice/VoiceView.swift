import DoddyCore
import SwiftUI
import UIKit

/// Voice conversation. It starts in the foreground and keeps running if the user leaves the app
/// (shown in the Dynamic Island / on the Lock Screen with Mute and End); it ends when the user
/// taps End or Close, from the island, or when the connection drops.
struct VoiceView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PreferenceKey.voiceAgentID) private var agentID = VoiceConfig.developmentAgentID
    @AppStorage(PreferenceKey.voiceTokenServer) private var tokenServer = ""
    @AppStorage(ConnectionPause.preferenceKey) private var pauseAllConnections = false
    @State private var controller: VoiceSessionController?
    @State private var connections = ConnectionController()
    @State private var openConnection: VoiceConnection?
    /// The time picker on a note-reminder card is open (closed again for each new card).
    @State private var editingNoteReminderTime = false
    /// "Change languages" on the "Start translating?" card.
    @State private var changingTranslator = false
    /// The plan step whose "Change" sheet is open (ADR-205).
    @State private var editingPlanStep: PlanStep?

    /// Read when a conversation starts, so a changed setting or access code applies next time.
    private var mode: VoiceConnectionMode {
        VoiceConnectionMode.resolve(
            serverAddress: tokenServer, accessCode: VoiceAccessCodeStore.read(), publicAgentID: agentID)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let controller {
                    session(controller)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
            .navigationTitle("Talk to Doddy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        Task {
                            await controller?.stop()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let controller {
                        Button {
                            controller.isPrivate.toggle()
                        } label: {
                            Label("Private", systemImage: controller.isPrivate ? "eye.slash.fill" : "eye.slash")
                        }
                        .accessibilityValue(controller.isPrivate ? "On" : "Off")
                        .accessibilityHint(controller.privacyLocked
                            ? "This conversation was used for translating, so it stays private."
                            : "When on, this conversation isn't kept on your iPhone.")
                        .disabled(controller.privacyLocked)
                        .accessibilityIdentifier("voice.private")
                    }
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .task {
            let controller = self.controller ?? VoiceSessionController(store: store)
            self.controller = controller
            await controller.start(
                mode, profile: profiles.profile, translator: ShortcutRouter.shared.takeTranslatorPreset(),
                checkIn: ShortcutRouter.shared.takeCheckInBriefing())
        }
        .onDisappear {
            Task { await controller?.stop() }
        }
        .sheet(item: $openConnection, onDismiss: {
            Task { await connections.refresh() }
            controller?.refreshConnectionNeeded()
        }) { connection in
            ConnectionSheet(connection: connection, controller: connections)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func session(_ controller: VoiceSessionController) -> some View {
        if let translator = controller.translator {
            TranslatorScreen(controller: controller, session: translator)
        } else {
            conversation(controller)
        }
    }

    private func conversation(_ controller: VoiceSessionController) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center, spacing: 16) {
                            CandidateCharacterView(assetName: "Doddy_listening", size: 96)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(statusTitle(controller.phase))
                                    .font(.title2.bold())
                                    .accessibilityIdentifier("voice.status")
                                if controller.isMuted && controller.isLive {
                                    Text("Your microphone is muted.")
                                        .font(.footnote)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)

                        if controller.audioPausedByOtherApp && controller.isLive {
                            Label("Another app has Doddy's audio. He can't hear you until it lets go.", systemImage: "pause.circle")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                                .accessibilityIdentifier("voice.audioPaused")
                        }
                        if let note = controller.audioNote {
                            Text(note)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("voice.audioNote")
                        }

                        if controller.isPrivate {
                            Label {
                                Text("Private conversation. It won't be kept on this iPhone or brought up in your next conversation. ElevenLabs still runs it and keeps its own recording, as in Settings › Privacy. Notes are only saved if you tap Save.")
                                    .font(.footnote)
                            } icon: {
                                Image(systemName: "eye.slash.fill")
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityIdentifier("voice.privateBanner")
                        }

                        problem(controller)

                        if let summary = controller.translatorSummary {
                            TranslatorEndCard(controller: controller, summary: summary)
                                .id("translatorSummary")
                        }

                        ForEach(controller.lines) { line in
                            transcriptLine(line)
                                .id(line.id)
                        }

                        if let pending = controller.pendingAction {
                            actionCard(pending, controller: controller)
                                .id("pendingAction")
                        }

                        if let status = controller.reminderStatus {
                            reminderStatusCard(status, controller: controller)
                                .id("reminderStatus")
                        }

                        if let receipt = controller.listReceipt {
                            listReceiptCard(receipt, controller: controller)
                                .id("listReceipt")
                        }

                        if let receipt = controller.changeReceipt {
                            changeReceiptCard(receipt, controller: controller)
                                .id("changeReceipt")
                        }

                        if let status = controller.noteReminderStatus {
                            noteReminderStatusCard(status, controller: controller)
                                .id("noteReminderStatus")
                        }

                        if let status = controller.planStatus {
                            planStatusCard(status, controller: controller)
                                .id("planStatus")
                        }

                        if pauseAllConnections {
                            pausedCard
                                .id("connectionsPaused")
                        }

                        if let needed = controller.connectionNeeded {
                            connectionCard(needed)
                                .id("connectionNeeded")
                        }

                        if let card = controller.contactCard {
                            contactCard(card, controller: controller)
                                .id("contactCard")
                        }

                        Text("While you talk, your voice, this conversation, your saved notes, your list names (and a list's items when Doddy reads or changes it), your last few conversations and any calendar entries, contact names or drafts Doddy uses are sent to ElevenLabs to run Doddy. Weather and Wikipedia lookups run from ElevenLabs\u{2019} servers. Nothing is saved, added, started, sent or opened unless you tap for it. If you leave the app, Doddy keeps listening (you'll see him in the Dynamic Island) until you tap End. If iOS stops Doddy in the background, the island says so instead of pretending he still hears you.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.top, 8)
                    }
                    .padding(24)
                }
                .onChange(of: controller.lines.count) { _, _ in
                    if let last = controller.lines.last { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onChange(of: controller.pendingAction) { _, pending in
                    editingNoteReminderTime = false
                    if pending != nil { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("pendingAction", anchor: .bottom) } }
                }
                .onChange(of: controller.listReceipt) { _, receipt in
                    if receipt != nil { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("listReceipt", anchor: .bottom) } }
                }
                .onChange(of: controller.noteReminderStatus) { _, status in
                    if status != nil { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("noteReminderStatus", anchor: .bottom) } }
                }
                .onChange(of: controller.contactCard) { _, card in
                    if card != nil { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("contactCard", anchor: .bottom) } }
                }
                .onChange(of: controller.reminderStatus) { _, status in
                    if status != nil { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("reminderStatus", anchor: .bottom) } }
                }
                .onChange(of: controller.planStatus == nil) { _, isNil in
                    if !isNil { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("planStatus", anchor: .bottom) } }
                }
            }
            controls(controller)
        }
    }

    @ViewBuilder
    private func problem(_ controller: VoiceSessionController) -> some View {
        switch controller.phase {
        case .microphoneDenied:
            VStack(alignment: .leading, spacing: 12) {
                ProblemView(message: "Microphone access is off, so Doddy can't hear you. You can turn it on in Settings, or keep using text in the app.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        case .failed(let message):
            ProblemView(message: message)
        default:
            EmptyView()
        }
    }

    private func transcriptLine(_ line: VoiceSessionController.Line) -> some View {
        HStack {
            if line.fromUser { Spacer(minLength: 40) }
            Text(line.text)
                .padding(12)
                .background(line.fromUser ? Theme.quietSurface : Theme.canvas, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.separator, lineWidth: line.fromUser ? 0 : 1))
                .accessibilityLabel(line.fromUser ? "You: \(line.text)" : "Doddy: \(line.text)")
            if !line.fromUser { Spacer(minLength: 40) }
        }
    }

    /// Card for anything that changes data or opens another app. Nothing happens until the user taps.
    private func actionCard(_ pending: VoiceSessionController.PendingAction, controller: VoiceSessionController) -> some View {
        let labels = actionLabels(pending, controller: controller)
        return VStack(alignment: .leading, spacing: 12) {
            actionContent(pending, controller: controller)
            Button {
                Task { await controller.confirmPendingAction() }
            } label: {
                HStack { Text(labels.confirm); Spacer(); Image(systemName: "checkmark") }
            }
            .buttonStyle(PrimaryButtonStyle())
            // A plan with every step unticked has nothing to confirm; "Not now" declines it.
            .disabled(isEmptyPlan(pending, controller: controller))
            .accessibilityIdentifier("voice.confirm")
            Button {
                Task { await controller.declinePendingAction() }
            } label: {
                Text(labels.decline)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        // One sheet for the whole card, not one per step (ADR-205).
        .sheet(item: $editingPlanStep) { step in
            PlanStepEditor(step: step) { changed in
                controller.replacePlanStep(changed)
            }
        }
    }

    @ViewBuilder
    private func actionContent(_ pending: VoiceSessionController.PendingAction, controller: VoiceSessionController) -> some View {
        switch pending {
        case .memory(_, let text):
            Text("Save this note?")
                .font(.headline)
            Text("“\(text)”")
                .font(.body)
            // File it now, or later from the note's own screen (ADR-202).
            Picker("Type", selection: Binding(
                get: { controller.pendingMemoryCategory },
                set: { controller.pendingMemoryCategory = $0 })
            ) {
                ForEach(MemoryCategory.noteCategories, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(minHeight: 44)
            .accessibilityIdentifier("voice.memoryType")
        case .event(_, let draft):
            Text("Add this event?")
                .font(.headline)
            Text(draft.title)
                .font(.body)
            Text(eventWhen(draft))
                .foregroundStyle(Theme.secondaryText)
            if let location = draft.location {
                Text(location)
                    .foregroundStyle(Theme.secondaryText)
            }
        case .reminder(_, let draft):
            Text("Add this reminder?")
                .font(.headline)
            Text(draft.title)
                .font(.body)
            if draft.due != nil {
                // Day, time and time zone exactly as they will be written (M4).
                Text(ReminderText.due(draft.due))
                    .foregroundStyle(Theme.secondaryText)
            }
            Text("Doddy checks your open reminders on this iPhone first, so it isn't added twice.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        case .timer(_, let draft):
            Text("Start this timer?")
                .font(.headline)
            Text(Duration.seconds(Double(draft.seconds)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)))
                .font(.body)
            if let label = draft.label {
                Text(label)
                    .foregroundStyle(Theme.secondaryText)
            }
        case .map(_, let place):
            Text("Open this in Maps?")
                .font(.headline)
            Text(place)
                .font(.body)
        case .shortcut(_, let name):
            Text("Run this Shortcut?")
                .font(.headline)
            Text(name)
                .font(.body)
            Text("The Shortcuts app opens for a moment.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        case .message(_, let draft, let address):
            Text(draft.channel == .text ? "Open this text in Messages?" : "Open this email in Mail?")
                .font(.headline)
            Text("To \(draft.recipientName) · \(address)")
                .foregroundStyle(Theme.secondaryText)
            Text("“\(draft.body)”")
                .font(.body)
            Text("You check it and send it there yourself. Doddy never sends it.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        case .changeEvent(_, let plan):
            Text("Change this event?")
                .font(.headline)
            changeRow(after: false, title: plan.before.title, when: eventWhen(plan.before))
            changeRow(after: true, title: plan.after.title, when: eventWhen(plan.after))
            Text("If it repeats, only this time changes. Nothing is deleted.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        case .changeReminder(_, let reminder, let draft):
            Group {
                if draft.markDone { Text("Mark this reminder done?") } else { Text("Change this reminder?") }
            }
            .font(.headline)
            Text(reminder.title)
                .font(.body)
            Text("In \(reminder.listTitle)")
                .foregroundStyle(Theme.secondaryText)
            if !draft.markDone {
                changeRow(after: false, title: nil, when: ReminderText.due(reminder.due))
                changeRow(after: true, title: nil, when: ReminderText.due(draft.newDue))
            }
        case .deleteEvent(_, let event):
            Text("Delete this event?")
                .font(.headline)
            Text(event.title)
                .font(.body)
            Text(eventWhen(event))
                .foregroundStyle(Theme.secondaryText)
            Text("If it repeats, only this time is deleted. This can't be undone from Doddy.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        case .deleteReminder(_, let reminder):
            Text("Delete this reminder?")
                .font(.headline)
            Text(reminder.title)
                .font(.body)
            Text("In \(reminder.listTitle) · \(ReminderText.due(reminder.due))")
                .foregroundStyle(Theme.secondaryText)
            Text("This can't be undone from Doddy.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        case .translator(_, let setup):
            translatorProposal(setup, controller: controller)
        case .createList(_, let name, let items):
            Text("Start a new list?")
                .font(.headline)
            TextField("Name", text: Binding(get: { name }, set: { controller.changeNewListName($0) }))
                .textFieldStyle(.roundedBorder)
                .font(.headline)
                .accessibilityLabel("List name")
                .accessibilityIdentifier("voice.newList.name")
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Label(item, systemImage: "square")
            }
            Text("Fix the name if Doddy misheard. Nothing is made until you tap Create list.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        case .noteReminder(_, _, let noteText, let savedAt, let target):
            noteReminderContent(noteText: noteText, savedAt: savedAt, target: target, controller: controller)
        case .cloud(_, _, let preview, _, let mode):
            if mode == .mock {
                Label("Demo — nothing real will be created", systemImage: "theatermasks")
                    .font(.footnote)
            }
            Text(preview.title)
                .font(.headline)
            ForEach(Array(preview.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.body)
            }
        case .plan(_, let steps, let blocked):
            planContent(steps: steps, blocked: blocked, controller: controller)
        }
    }

    /// Plan card (ADR-204): every change with its full details and its own tick box. Blocked steps
    /// say why and can't be ticked. Nothing runs until the button below is tapped.
    @ViewBuilder
    private func planContent(steps: [PlanStep], blocked: [Int: PlanBlock], controller: VoiceSessionController) -> some View {
        Text("Here's what I'd do")
            .font(.headline)
        PlanStepList(
            steps: steps, blocked: blocked, ticked: controller.planTicked, idPrefix: "voice.plan",
            cloud: controller.planCloud, onToggle: { controller.togglePlanStep($0) }, onChange: { editingPlanStep = $0 })
        Text("Untick anything you don't want, or tap Change to fix a step. The rest run in this order, and each one gets its own result.")
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
    }

    /// After a plan's button: each step with its result, from the same entries as "What Doddy did".
    private func planStatusCard(_ status: VoiceSessionController.PlanStatus, controller: VoiceSessionController) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if status.isRunning { ProgressView() }
                Text(status.isRunning ? "Working through the plan…" : "What happened")
                    .font(.headline)
            }
            ForEach(status.steps) { step in
                let request = step.activity(calendar: .current)
                let result = status.results[step.number]
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(step.number). \(request?.title ?? step.toolName) · \(request?.app.title ?? "")")
                        .font(.body)
                    if let detail = request?.detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Text(result?.outcome.text ?? "Waiting")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(result.map { $0.outcome == .notDone || $0.outcome == .notSure } == true ? Theme.error : Theme.ink)
                    if let note = result?.note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if !status.isRunning {
                Button("OK") {
                    controller.dismissPlanStatus()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice.planReceipt")
    }

    private func isEmptyPlan(_ pending: VoiceSessionController.PendingAction, controller: VoiceSessionController) -> Bool {
        if case .plan = pending { return controller.planTicked.isEmpty }
        return false
    }

    private func actionLabels(_ pending: VoiceSessionController.PendingAction, controller: VoiceSessionController) -> (confirm: String, decline: String) {
        switch pending {
        case .memory: (NSLocalizedString("Save", comment: ""), NSLocalizedString("Don't save", comment: ""))
        case .event, .reminder: (NSLocalizedString("Add", comment: ""), NSLocalizedString("Don't add", comment: ""))
        case .timer: (NSLocalizedString("Start", comment: ""), NSLocalizedString("Don't start", comment: ""))
        case .map: (NSLocalizedString("Open in Maps", comment: ""), NSLocalizedString("Don't open", comment: ""))
        case .shortcut: (NSLocalizedString("Run", comment: ""), NSLocalizedString("Don't run", comment: ""))
        case .message(_, let draft, _): (draft.channel == .text ? NSLocalizedString("Open in Messages", comment: "") : NSLocalizedString("Open in Mail", comment: ""), NSLocalizedString("Don't open", comment: ""))
        case .cloud(_, _, let preview, _, _): (preview.confirmLabel, NSLocalizedString("Don't do this", comment: ""))
        case .noteReminder: (NSLocalizedString("Set reminder", comment: ""), NSLocalizedString("Don't set", comment: ""))
        case .translator: (NSLocalizedString("Start", comment: ""), NSLocalizedString("Not now", comment: ""))
        case .createList: (NSLocalizedString("Create list", comment: ""), NSLocalizedString("Not now", comment: ""))
        case .changeEvent: (NSLocalizedString("Change", comment: ""), NSLocalizedString("Don't change", comment: ""))
        case .deleteEvent, .deleteReminder: (NSLocalizedString("Delete", comment: ""), NSLocalizedString("Don't delete", comment: ""))
        case .changeReminder(_, _, let draft): (draft.markDone ? NSLocalizedString("Mark done", comment: "") : NSLocalizedString("Change", comment: ""), NSLocalizedString("Don't change", comment: ""))
        case .plan(_, let steps, _): (PlanProposal.confirmTitle(steps.filter { controller.planTicked.contains($0.number) }), NSLocalizedString("Not now", comment: ""))
        }
    }

    /// Note reminder card (ADR-198): the note exactly as saved and when, then the time with its
    /// zone (changeable), or arrive/leave and the Apple Maps results to pick from. Doddy's own
    /// reminder, not Apple Reminders.
    @ViewBuilder
    private func noteReminderContent(
        noteText: String, savedAt: Date?, target: VoiceSessionController.NoteReminderCardTarget, controller: VoiceSessionController
    ) -> some View {
        let isList = controller.isListReminder
        Group {
            if isList { Text("Remind you about this list?") } else { Text("Remind you about this note?") }
        }
        .font(.headline)
        VStack(alignment: .leading, spacing: 4) {
            Text(noteText)
                .font(.body)
            if isList {
                Text("Your list in Doddy. The notification doesn't name it or its items.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else if let savedAt {
                Text("Your note, saved \(savedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.separator))
        .accessibilityElement(children: .combine)
        switch target {
        case .time(let date, let zone, let repeats):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    if let repeats {
                        // The card shows where the repeat really starts (iOS can't start it later).
                        let first = ReminderSchedule.firstOccurrence(
                            repeats, picked: date, timeZoneID: zone, now: .now, lead: NoteReminderLimits.minimumLead) ?? date
                        Text(ReminderFormat.repeatPhrase(repeats, anchor: date, timeZoneID: zone))
                            .font(.headline)
                        Text("\(ReminderFormat.zoneName(zone)) · first on \(ReminderFormat.dateTime(first, timeZoneID: zone)) · until you stop it")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        Text(ReminderFormat.full(date, timeZoneID: zone))
                            .font(.headline)
                    }
                    Text("A notification from Doddy on this iPhone, not Apple Reminders.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            } icon: {
                Image(systemName: repeats == nil ? "bell" : "repeat")
            }
            if editingNoteReminderTime {
                DatePicker(
                    "Remind me at",
                    selection: Binding(get: { date }, set: { controller.changeNoteReminderTime($0) }),
                    in: Date.now.addingTimeInterval(NoteReminderLimits.minimumLead)...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
            } else {
                Button("Change time") { editingNoteReminderTime = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("voice.noteReminder.changeTime")
            }
        case .place(let results, let onArrival):
            Picker("When", selection: Binding(get: { onArrival }, set: { controller.setNoteReminderOnArrival($0) })) {
                Text("When I arrive").tag(true)
                Text("When I leave").tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("voice.noteReminder.when")
            Text("Apple Maps found these. Pick one:")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                let selected = index == controller.selectedPlaceIndex
                Button { controller.selectPlace(index) } label: {
                    HStack(alignment: .top) {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle").accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name).font(.subheadline.bold())
                            if !result.address.isEmpty {
                                Text(result.address).font(.footnote).foregroundStyle(Theme.secondaryText)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Text("Within \(ReminderPlace.defaultRadius) m, each time until you mark it Done; change the distance on the note. Uses notifications and your location while you use Doddy. iOS watches the place; Doddy doesn't follow where you go.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    /// Receipt after Set reminder on a note-reminder card: the same receipt the note screen shows,
    /// built from what the store verified. Stays after the conversation ends.
    private func noteReminderStatusCard(_ status: VoiceSessionController.NoteReminderStatus, controller: VoiceSessionController) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch status {
            case .setting(let confirmed):
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Setting the reminder…")
                        .font(.headline)
                }
                Text(confirmed.noteText)
                    .font(.body)
                    .lineLimit(2)
            case .done(let confirmed, let receipt):
                NoteReminderReceiptView(receipt: receipt) {
                    Task { await controller.retryNoteReminder() }
                }
                Text("For \u{201C}\(confirmed.noteText)\u{201D}")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                if controller.isLive {
                    Button("OK") { controller.dismissNoteReminderStatus() }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    // Opening the note closes this screen, so it is offered once the conversation ended.
                    Button("Open the note") {
                        store.noteReminders?.pendingOpenMemoryID = confirmed.memoryID
                        controller.dismissNoteReminderStatus()
                        dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("voice.noteReminder.openNote")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice.noteReminderReceipt")
    }

    /// Receipt after Add on a reminder card: what Reminders holds now, read back from the iPhone,
    /// or why nothing was added. Text comes from DoddyCore (`ReminderOutcome.screen`).
    private func reminderStatusCard(_ status: VoiceSessionController.ReminderStatus, controller: VoiceSessionController) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch status {
            case .adding(let draft):
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Adding to Reminders…")
                        .font(.headline)
                }
                Text("“\(draft.title)”")
                    .font(.body)
            case .done(let draft, let outcome):
                let receipt = outcome.screen(for: draft)
                Label(receipt.headline, systemImage: receipt.isProblem ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.headline)
                    .foregroundStyle(receipt.isProblem ? Theme.error : Theme.ink)
                ForEach(Array(receipt.lines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(index == 0 ? .body : .subheadline)
                        .foregroundStyle(index == 0 ? Theme.ink : Theme.secondaryText)
                }
                Button("OK") {
                    controller.dismissReminderStatus()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice.reminderReceipt")
    }

    /// Shown when the agent asked for something that is switched off. One tap opens the same
    /// Connections sheet as Settings, so the terms are visible before anything turns on.
    /// Settings → Pause all is on. One tap brings back the connections that were on before.
    private var pausedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Connections are paused", systemImage: "pause.circle")
                .font(.headline)
            Text("Doddy is using only your notes: no calendar, reminders, contacts, other apps or online accounts.")
                .foregroundStyle(Theme.secondaryText)
            Button {
                pauseAllConnections = false
            } label: {
                Label("Turn connections back on", systemImage: "play.circle")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("voice.resumeConnections")
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    private func connectionCard(_ connection: VoiceConnection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(connection.title) is off", systemImage: ConnectionInfo.of(connection).symbol)
                .font(.headline)
            Text("Turn it on to let Doddy use \(connection.title.lowercased()). Then ask again.")
                .foregroundStyle(Theme.secondaryText)
            Button {
                openConnection = connection
            } label: {
                Label("Turn on \(connection.title)", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("voice.turnOnConnection")
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    /// Names and details of a contact lookup. Only the agent's copy is names; this is the full view.
    /// Call, Text and Email open the iPhone's own apps, and each one is a tap.
    private func contactCard(_ card: VoiceSessionController.ContactCard, controller: VoiceSessionController) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contacts for “\(card.query)”")
                .font(.headline)
            if card.matches.isEmpty {
                Text("No contact matched.")
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(card.matches) { match in
                VStack(alignment: .leading, spacing: 8) {
                    Text(match.name)
                        .font(.body.bold())
                    ForEach(match.phoneNumbers, id: \.self) { number in
                        Text(number)
                            .textSelection(.enabled)
                        HStack(spacing: 8) {
                            contactAction("Call", systemImage: "phone") { OpenLinks.call(number: number) }
                            contactAction("Text", systemImage: "text.bubble") { OpenLinks.text(number: number, body: "") }
                        }
                    }
                    ForEach(match.emailAddresses, id: \.self) { address in
                        Text(address)
                            .textSelection(.enabled)
                        contactAction("Email", systemImage: "envelope") { OpenLinks.email(address: address, body: "") }
                    }
                }
            }
            Button("Close") {
                controller.dismissContactCard()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func contactAction(_ title: String, systemImage: String, url: @escaping () -> URL?) -> some View {
        Button {
            guard let link = url() else { return }
            Task { _ = await UIApplication.shared.open(link) }
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
    }

    /// What a list change by voice did (ADR-216), with Undo and, when "milk" matched two items,
    /// the items to tap. Read back from the store before it is shown.
    /// A change in Calendar or Reminders, checked, with Undo (ADR-253).
    private func changeReceiptCard(_ receipt: ChangeReceipt, controller: VoiceSessionController) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Label(receipt.message, systemImage: "checkmark.circle").foregroundStyle(Theme.confirmed)
                Spacer()
                Button { controller.dismissChangeReceipt() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            switch receipt.state {
            case .available:
                Button { Task { await controller.undoLastChange() } } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward").frame(minHeight: 44)
                }
                .accessibilityIdentifier("voice.undoChange")
            case .working:
                ProgressView("Putting it back…")
            case .undone:
                Label("Put back as it was. Checked.", systemImage: "arrow.uturn.backward.circle")
                    .foregroundStyle(Theme.confirmed)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
            }
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func listReceiptCard(_ receipt: ListReceipt, controller: VoiceSessionController) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(receipt.title).font(.headline)
                Spacer()
                Button { controller.dismissListReceipt() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            ForEach(Array(receipt.lines.enumerated()), id: \.offset) { _, line in
                switch line {
                case .added(let text): Label(text, systemImage: "plus")
                case .ticked(let text): Label(text, systemImage: "checkmark.square.fill").foregroundStyle(Theme.confirmed)
                case .removed(let text): Label(text, systemImage: "minus").foregroundStyle(Theme.secondaryText)
                case .open(let text): Label(text, systemImage: "square")
                case .note(let text): Text(text).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            if let choices = receipt.choices {
                Text("“\(choices.said)” matches more than one. \(choices.tick ? "Tick" : "Remove") which?")
                    .font(.subheadline.weight(.semibold))
                ForEach(choices.options) { item in
                    Button(item.text) { Task { await controller.pickListChoice(item) } }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            if let problem = receipt.problem {
                ProblemView(message: problem)
            }
            if receipt.undo != nil {
                Button("Undo") { Task { await controller.undoListReceipt() } }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("voice.list.undo")
            }
            Text("Saved on this iPhone. Open Memories › Lists to see the whole list.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("voice.listReceipt")
    }

    /// "Start translating?" (canvas 2): the pair, what changes, and Change languages.
    @ViewBuilder
    private func translatorProposal(_ setup: TranslatorSetup, controller: VoiceSessionController) -> some View {
        Text("Start translating?")
            .font(.headline)
        HStack(spacing: 8) {
            languageChip("You", setup.owner.nativeName)
            Image(systemName: setup.kind == .faceToFace ? "arrow.left.arrow.right" : "arrow.left")
                .accessibilityLabel(setup.kind == .faceToFace ? "translated both ways" : "translated into your language")
            languageChip(setup.kind == .faceToFace ? "Them" : "Around you", setup.other?.nativeName ?? "Detect")
        }
        Text(setup.kind == .faceToFace
             ? "While translating, Doddy only translates: no notes, reminders or other tools, and this conversation isn't kept on this iPhone. Their voice goes to ElevenLabs too. Doddy first tells them, in their language, that he's an AI translator."
             : "Listen only: Doddy translates what's said around you into your language and doesn't speak to anyone else. No tools while it's on, and this conversation isn't kept on this iPhone.")
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
        Button("Change languages") { changingTranslator = true }
            .buttonStyle(SecondaryButtonStyle())
            .sheet(isPresented: $changingTranslator) {
                TranslatorChangeSheet(controller: controller, setup: setup)
            }
    }

    private func languageChip(_ who: String, _ name: String) -> some View {
        VStack(spacing: 2) {
            Text(who).font(.caption).foregroundStyle(Theme.secondaryText)
            Text(name).font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    /// One side of a change card: "Now" or "After", then the title and when.
    private func changeRow(after: Bool, title: String?, when: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if after { Text("After") } else { Text("Now") }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            if let title {
                Text(title)
                    .font(.body)
            }
            Text(when)
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private func eventWhen(_ event: CalendarEventSummary) -> String {
        if event.allDay {
            return event.start.formatted(date: .abbreviated, time: .omitted) + " (all day)"
        }
        return event.start.formatted(date: .abbreviated, time: .shortened)
            + " – " + event.end.formatted(date: .omitted, time: .shortened)
    }

    private func eventWhen(_ draft: CalendarEventDraft) -> String {
        if draft.allDay {
            return draft.start.formatted(date: .abbreviated, time: .omitted) + " (all day)"
        }
        return draft.start.formatted(date: .abbreviated, time: .shortened)
            + " – " + draft.end.formatted(date: .omitted, time: .shortened)
    }

    private func controls(_ controller: VoiceSessionController) -> some View {
        HStack(spacing: 12) {
            if controller.isLive {
                Button {
                    Task { await controller.toggleMute() }
                } label: {
                    Label(controller.isMuted ? "Unmute" : "Mute", systemImage: controller.isMuted ? "mic.slash" : "mic")
                }
                .buttonStyle(SecondaryButtonStyle())
                Button {
                    Task { await controller.stop() }
                } label: {
                    Label("End", systemImage: "phone.down")
                }
                .buttonStyle(SecondaryButtonStyle(tint: Theme.error))
                .accessibilityIdentifier("voice.end")
            } else {
                Button {
                    Task { await controller.start(mode, profile: profiles.profile) }
                } label: {
                    Label("Talk again", systemImage: "waveform")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Theme.canvas)
    }

    private func statusTitle(_ phase: VoiceSessionController.Phase) -> String {
        switch phase {
        case .idle, .connecting: NSLocalizedString("Connecting…", comment: "")
        case .listening: NSLocalizedString("Listening", comment: "")
        case .thinking: NSLocalizedString("Thinking…", comment: "")
        case .speaking: NSLocalizedString("Speaking", comment: "")
        case .ended: NSLocalizedString("Conversation ended", comment: "")
        case .microphoneDenied: NSLocalizedString("Microphone is off", comment: "")
        case .failed: NSLocalizedString("Couldn't connect", comment: "")
        }
    }
}
