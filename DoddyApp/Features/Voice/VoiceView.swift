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
    /// Back from iPhone Settings, the access card looks at iOS's answer again (ADR-577).
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(VoiceProvider.preferenceKey) private var voiceProvider = ""
    @AppStorage(ConnectionPause.preferenceKey) private var pauseAllConnections = false
    @State private var controller: VoiceSessionController?
    @State private var authSession = VoiceAuthSession.shared
    @State private var connections = ConnectionController()
    @State private var openConnection: VoiceConnection?
    /// The time picker on a note-reminder card is open (closed again for each new card).
    @State private var editingNoteReminderTime = false
    /// The plan step whose "Change" sheet is open (ADR-205).
    @State private var editingPlanStep: PlanStep?
    /// What was last copied from a BLIK card (ADR-510), to show "Copied" next to it.
    @State private var copiedForBlik: String?

    private var provider: VoiceProvider { VoiceProvider.effective(stored: voiceProvider, tokenServerSet: true) }

    /// The app endpoint is fixed in the build; users never enter server URLs or access codes.
    /// Debug builds may go straight to the agent without a DODDY voice account (ADR-551).
    private var mode: VoiceConnectionMode { VoiceConfig.connectionMode }

    var body: some View {
        NavigationStack {
            Group {
                if let controller {
                    session(controller)
                } else {
                    VoiceAccessGate(provider: provider) {
                        Task { await beginConversation() }
                    }
                }
            }
            // A full-screen cover on iPad: one readable column, the paper still edge to edge (ADR-437).
            .readableColumn()
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
            await authSession.restore()
            if (authSession.isSignedIn || VoiceConfig.directVoiceEnabled) && VoiceProviderConsent.isGranted(for: provider) {
                await beginConversation()
            }
        }
        .onDisappear {
            Task { await controller?.stop() }
        }
        .sheet(item: $openConnection, onDismiss: {
            Task {
                await connections.refresh()
                await controller?.refreshConnectionNeeded()
            }
        }) { connection in
            ConnectionSheet(connection: connection, controller: connections)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await controller?.recheckConnectionAccess() } }
        }
    }

    @MainActor
    private func beginConversation() async {
        guard controller == nil else { return }
        // One conversation at a time (ADR-496): one already starting or live is shown instead of
        // starting a second. What was asked for a
        // new conversation (a shortcut's greeting, a translator, a check-in, a note) is dropped,
        // so it can't start with a later conversation by surprise.
        if let running = VoiceSessionController.runningConversation {
            _ = ShortcutRouter.shared.takeTalkToDoddyOpening()
            _ = ShortcutRouter.shared.takeTranslatorPreset()
            _ = ShortcutRouter.shared.takeCheckInBriefing()
            _ = ShortcutRouter.shared.takeNoteToAsk()
            self.controller = running
            return
        }
        let controller = VoiceSessionController(store: store)
        self.controller = controller
        // Back Tap or another Talk to Doddy shortcut greets with "Hey <name>, what's up?", after the same
        // account and provider-consent gate used by a tap in the app.
        let openedByShortcut = ShortcutRouter.shared.takeTalkToDoddyOpening()
        let action = BackTapAction.stored(UserDefaults.standard.string(forKey: PreferenceKey.backTapAction))
        let greeting = openedByShortcut && action.startsConversation ? TalkInIsland.greeting(for: profiles.profile) : nil
        // The island opens up when Doddy starts speaking, not here (ADR-576): this screen is on top,
        // and iOS doesn't show Doddy's own island over Doddy, so a request now was always lost.
        await controller.start(
            mode, profile: profiles.profile, translator: ShortcutRouter.shared.takeTranslatorPreset(),
            checkIn: ShortcutRouter.shared.takeCheckInBriefing(),
            wakeGreeting: greeting, aboutNote: ShortcutRouter.shared.takeNoteToAsk())
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
                            VoiceDoddyView(art: screenArt(controller))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(statusTitle(controller))
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

                        // ADR-265/442: the copy below names ElevenLabs; say plainly when it isn't.
                        if controller.provider == .openAIRealtime {
                            Label {
                                Text(verbatim: "OpenAI Realtime \(controller.openAIModel.shortName) runs this conversation instead of ElevenLabs. Your voice, this conversation and what Doddy knows go to OpenAI. Weather and Wikipedia don't work with it.")
                            } icon: {
                                Image(systemName: "waveform.badge.mic")
                            }
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                                .accessibilityIdentifier("voice.openAITest")
                        }
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
                                Text("Private conversation. It won't be kept on this iPhone or brought up in your next conversation. OpenAI (or ElevenLabs, if you switched Home to it) still runs it and may keep its own recording, as in Settings › Privacy. Notes are only saved if you tap Save.")
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

                        if let card = controller.blikCard {
                            blikReceiptCard(card, controller: controller)
                                .id("blikCard")
                        }

                        if let status = controller.noteReminderStatus {
                            noteReminderStatusCard(status, controller: controller)
                                .id("noteReminderStatus")
                        }

                        if let status = controller.planStatus {
                            planStatusCard(status, controller: controller)
                                .id("planStatus")
                        }

                        if let card = controller.saveSuggestions {
                            saveSuggestionsCard(card, controller: controller)
                                .id("saveSuggestions")
                        }

                        if let learning = store.learning, learning.cards.contains(where: { $0.state != .dismissed }) {
                            LearningCardsView(learning: learning)
                                .id("learningCards")
                        }

                        if pauseAllConnections {
                            pausedCard
                                .id("connectionsPaused")
                        }

                        if let request = controller.accessRequest {
                            accessCard(request, controller: controller)
                                .id("connectionNeeded")
                        }

                        if let needed = controller.accountNeeded {
                            accountCard(needed, controller: controller)
                                .id("accountNeeded")
                        }

                        ForEach(controller.documents, id: \.url) { document in
                            documentCard(document)
                                .id("document-\(document.url.absoluteString)")
                        }

                        if let card = controller.contactCard {
                            contactCard(card, controller: controller)
                                .id("contactCard")
                        }

                        if let spot = controller.parkingCard {
                            parkingCard(spot, controller: controller)
                                .id("parkingCard")
                        }

                        Text("While you talk, your voice, this conversation, your saved notes, your list names (and a list's items when Doddy reads or changes it), your last few conversations and any calendar entries, contact names and birthdays (day and month) or drafts Doddy uses are sent to ElevenLabs, or OpenAI if you switch Home's voice to it to run Doddy. Weather and Wikipedia lookups work only with ElevenLabs, from its servers. Nothing is saved, added, started, sent or opened unless you tap for it. If you leave the app, Doddy keeps listening (you'll see him in the Dynamic Island) until you tap End. If iOS stops Doddy in the background, the island says so instead of pretending he still hears you.")
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
                    copiedForBlik = nil
                    if pending != nil { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("pendingAction", anchor: .bottom) } }
                }
                .onChange(of: controller.listReceipt) { _, receipt in
                    if receipt != nil { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("listReceipt", anchor: .bottom) } }
                }
                .onChange(of: controller.blikCard) { _, card in
                    if card != nil { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("blikCard", anchor: .bottom) } }
                }
                .onChange(of: controller.noteReminderStatus) { _, status in
                    if status != nil { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("noteReminderStatus", anchor: .bottom) } }
                }
                .onChange(of: controller.parkingCard) { _, spot in
                    if spot != nil { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("parkingCard", anchor: .bottom) } }
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
                .onChange(of: controller.saveSuggestions == nil) { _, isNil in
                    if !isNil { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("saveSuggestions", anchor: .bottom) } }
                }
                // The access card is what Doddy just asked the user to tap (ADR-577).
                .onChange(of: controller.accessRequest?.connection) { _, connection in
                    if connection != nil { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("connectionNeeded", anchor: .bottom) } }
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
            if controller.isOffline {
                OfflineNoteCard(controller: controller, startText: controller.recovery?.text ?? "")
            } else {
                ProblemView(message: message)
                if controller.recovery != nil || controller.recoverySaved != nil {
                    RecoveryDraftCard(controller: controller)
                }
            }
        case .ended:
            // After Stop listening (ADR-361): the note Doddy was asking about, as a draft.
            if controller.recovery != nil || controller.recoverySaved != nil {
                RecoveryDraftCard(controller: controller)
            }
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
            if let repeats = draft.repeats {
                Label(Self.repeatText(repeats), systemImage: "repeat")
                    .foregroundStyle(Theme.secondaryText)
            }
            // Written to the event as its notes, so shown before Add (review H4).
            if let notes = draft.notes, !notes.isEmpty {
                Label(notes, systemImage: "text.alignleft")
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
            if let repeats = draft.repeats {
                Label(Self.repeatText(repeats), systemImage: "repeat")
                    .foregroundStyle(Theme.secondaryText)
            }
            // Written to the reminder as its notes, so shown before Add (review H4).
            if let notes = draft.notes, !notes.isEmpty {
                Label(notes, systemImage: "text.alignleft")
                    .foregroundStyle(Theme.secondaryText)
            }
            Text("Doddy checks your open reminders on this iPhone first, so it isn't added twice.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        case .cancelAlarm(_, let alarm):
            Text("Turn off this alarm?")
                .font(.headline)
            Text(alarm.summary)
                .font(.title3.monospacedDigit())
            if let label = alarm.label {
                Text("“\(label)”")
            }
            Text("A repeating alarm stops for every day, not just the next one.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        case .alarm(_, let draft):
            Text("Set this alarm?")
                .font(.headline)
            Text(draft.clock)
                .font(.title2.monospacedDigit())
            Group {
                if let repeats = draft.repeats {
                    switch repeats {
                    case .everyDay: Text("Every day")
                    case .weekdays: Text("Monday to Friday")
                    case .weekends: Text("Saturday and Sunday")
                    }
                } else if let date = draft.first.date {
                    Text(date.formatted(date: .complete, time: .omitted))
                }
            }
            .foregroundStyle(Theme.secondaryText)
            if let label = draft.label {
                Text("“\(label)”")
            }
            Text("It rings even in Silent mode or a Focus, with Snooze for 9 minutes. Turn it off in Settings, Alarms, or ask Doddy.")
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
            // "Open the camera" (ADR-309): help right here if the user hasn't made the shortcut yet.
            if CameraShortcut.isCamera(name) {
                CameraShortcutHelp(style: .card)
            }
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
        case .blik(_, let draft, let contactName, let numbers):
            Text("A BLIK transfer for you to send")
                .font(.headline)
            blikDetails(draft, contactName: contactName, numbers: numbers, controller: controller)
        case .changeEvent(_, let plan):
            Text("Change this event?")
                .font(.headline)
            changeRow(after: false, title: plan.before.title, when: eventWhen(plan.before))
            changeRow(after: true, title: plan.after.title, when: eventWhen(plan.after))
            // Place and notes (ADR-281): shown here only; the old place never goes to Doddy's voice.
            if let place = plan.newLocation {
                Label(String(format: NSLocalizedString("Place: %@ → %@", comment: ""),
                             plan.locationBefore?.isEmpty == false ? plan.locationBefore! : NSLocalizedString("none", comment: ""),
                             place.isEmpty ? NSLocalizedString("none", comment: "") : place),
                      systemImage: "mappin.and.ellipse")
            }
            if let note = plan.addNote {
                Label(String(format: NSLocalizedString("Adds to its notes: “%@”", comment: ""), note), systemImage: "text.append")
            }
            // ADR-314: the old notes as they are, and what replaces them; Undo puts them back.
            if let text = plan.replaceNotes {
                VStack(alignment: .leading, spacing: 4) {
                    Label(text.isEmpty ? "Clear the notes" : "Replace the notes", systemImage: "note.text")
                    if let old = plan.notesBefore, !old.isEmpty {
                        Text("Now: “\(old)”").font(.footnote).foregroundStyle(Theme.secondaryText).lineLimit(4)
                    }
                    if !text.isEmpty {
                        Text("New: “\(text)”").font(.footnote).lineLimit(6)
                    }
                }
            }
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
            if !draft.markDone, draft.newDue != nil || !draft.changesDetails {
                changeRow(after: false, title: nil, when: ReminderText.due(reminder.due))
                changeRow(after: true, title: nil, when: ReminderText.due(draft.newDue))
            }
            // ADR-302 and ADR-314: each detail as it is now and as it will be.
            if let title = draft.newTitle {
                Label("Rename to “\(title)”", systemImage: "pencil")
            }
            if let text = draft.replaceNotes {
                VStack(alignment: .leading, spacing: 4) {
                    Label(text.isEmpty ? "Clear the notes" : "Replace the notes", systemImage: "note.text")
                    if let old = reminder.notes, !old.isEmpty {
                        Text("Now: “\(old)”").font(.footnote).foregroundStyle(Theme.secondaryText).lineLimit(4)
                    }
                    if !text.isEmpty {
                        Text("New: “\(text)”").font(.footnote).lineLimit(6)
                    }
                }
            }
            switch draft.repeatChange {
            case .set(let rule)?: Label(Self.repeatText(rule), systemImage: "repeat")
            case .stop?: Label("Stop repeating", systemImage: "repeat")
            case nil: EmptyView()
            }
            if let line = draft.addNote {
                Label("Add to the notes: “\(line)”", systemImage: "note.text")
            }
            if let priority = draft.priority {
                Label("Priority: \(Self.priorityText(reminder.priority)) → \(Self.priorityText(priority))", systemImage: "exclamationmark.circle")
            }
            if let list = draft.toList {
                Label("Move to the list “\(list.title)”", systemImage: "list.bullet")
            }
            if draft.changesDetails {
                Text("Undo isn't available for these changes.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
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
        case .bulk(_, let items, let verb, let skipped):
            Group {
                if verb == "deleted" { Text("Delete these events?") } else { Text("Move these reminders?") }
            }
            .font(.headline)
            ForEach(items) { item in
                Button { controller.toggleBulkItem(item.id) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: controller.bulkUnticked.contains(item.id) ? "circle" : "checkmark.circle.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(bulkDetail(item)).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(controller.bulkUnticked.contains(item.id) ? [] : .isSelected)
            }
            if !skipped.isEmpty {
                Text(String(format: NSLocalizedString("Left as they are (that time doesn't exist that day): %@", comment: ""), skipped.joined(separator: ", ")))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            Group {
                if verb == "deleted" {
                    Text("Untick any to keep. Each one is checked before it goes; a repeating event loses only this time. This can't be undone from Doddy.")
                } else {
                    Text("Untick any to leave. Each keeps its time and is checked before it moves.")
                }
            }
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
        case .undo(_, let entry):
            if let undo = entry.undo {
                Text(undo.question(.current))
                    .font(.headline)
                Text(undo.explanation(calendar: .current, language: .current))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        case .ingredients(_, _, let listName, let dish, let items, let alreadyOpen):
            // ADR-305: Doddy's suggestion; the user unticks what they have.
            Text("Add these to \(listName)?")
                .font(.headline)
            Text("Doddy's suggestion for \(dish). Untick what you already have.")
                .foregroundStyle(Theme.secondaryText)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button { controller.toggleIngredient(index) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: controller.ingredientsUnticked.contains(index) ? "circle" : "checkmark.circle.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item)
                            if alreadyOpen.contains(index) {
                                Text("Already on the list").font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(controller.ingredientsUnticked.contains(index) ? [] : .isSelected)
            }
        case .parking(_, let spot):
            // ADR-301: where the iPhone is now, kept only on Save, on this iPhone.
            Text("Save your parking spot here?")
                .font(.headline)
            Text("Where your iPhone is now, to within about \(Int(spot.accuracyMeters.rounded())) m.")
            if let note = spot.note {
                Text("“\(note)”")
            }
            Text("Kept only on this iPhone, and replaces any spot saved before. Doddy hears when you saved it, not where.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        case .leaveBy(_, let plan):
            // ADR-335: what Apple Maps found, so a wrong place can be turned down.
            Text("Remind you when to leave?")
                .font(.headline)
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.placeName)
                    if !plan.placeAddress.isEmpty {
                        Text(plan.placeAddress).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
            } icon: { Image(systemName: "mappin.and.ellipse") }
            Label(String(format: NSLocalizedString("Arrive by %@", comment: ""), plan.request.arriveBy.formatted(date: .abbreviated, time: .shortened)), systemImage: "flag")
            Label(String(format: NSLocalizedString("About %lld min of travel, plus %lld min spare", comment: ""), plan.travelMinutes, plan.request.bufferMinutes), systemImage: "car")
            Label(String(format: NSLocalizedString("Leave at %@", comment: ""), plan.leaveAt.formatted(date: .omitted, time: .shortened)), systemImage: "bell")
                .font(.headline)
            Text("Apple Maps worked out the travel time just now, from where your iPhone is; traffic can change. Your position isn't kept.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
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
        case .ask(_, let card, let needsTap, _, _):
            // ASK-01 (ADR-483): exactly what Doddy will do; nothing runs before the answer.
            Text(card.title)
                .font(.headline)
            ForEach(Array(card.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.body)
            }
            Text(needsTap ? "Nothing changes until you tap." : "Say yes, or tap. Nothing is looked at before that.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        case .cloudRead(_, _, let preview, _, let mode):
            if mode == .mock {
                Label("Demo — not your real account", systemImage: "theatermasks")
                    .font(.footnote)
            }
            Text(preview.title)
                .font(.headline)
            ForEach(Array(preview.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.body)
            }
            Text("Say yes, or tap. Nothing is looked at before that.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
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
                    Text(verbatim: "\(step.number). \(request.map { ActivityText.title($0.title, .current) } ?? step.toolName) · \(request?.app.title(.current) ?? "")")
                        .font(.body)
                    if let detail = request?.detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Text(result?.outcome.text(.current) ?? NSLocalizedString("Waiting", comment: ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(result.map { $0.outcome == .notDone || $0.outcome == .notSure } == true ? Theme.error : Theme.ink)
                    if let note = result?.note(.current) {
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

    /// "Worth keeping?" after the conversation (ADR-247): the user's own sentences, none ticked.
    /// The words can be changed before saving; changing them ticks the item.
    private func saveSuggestionsCard(_ card: SaveSuggestionCard, controller: VoiceSessionController) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.hasResults ? "What was saved" : "Worth keeping?")
                .font(.headline)
            if !card.hasResults {
                Text("Things you said that might be useful later, in your words. Tick what to save; nothing is saved otherwise. Doddy picked these on this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(card.items) { item in
                switch item.state {
                case .offered where !card.hasResults, .saving:
                    HStack(alignment: .top, spacing: 10) {
                        Button {
                            controller.toggleSaveSuggestion(item.id)
                        } label: {
                            Image(systemName: item.isTicked ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundStyle(item.isTicked ? Theme.accentText : Theme.secondaryText)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(item.state == .saving)
                        .accessibilityLabel(item.isTicked ? "Ticked: save this" : "Not ticked")
                        .accessibilityIdentifier("voice.suggestion.tick.\(item.id)")
                        TextField("Note", text: Binding(
                            get: { item.text },
                            set: { controller.changeSaveSuggestion(item.id, to: $0) }
                        ), axis: .vertical)
                            .font(.body)
                            .disabled(item.state == .saving)
                            .accessibilityIdentifier("voice.suggestion.text.\(item.id)")
                    }
                case .offered:
                    Label(item.text, systemImage: "minus.circle")
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityLabel("Not saved: \(item.text)")
                case .saved(let record):
                    Label(record.currentText, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.confirmed)
                        .accessibilityLabel("Saved: \(record.currentText)")
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 2) {
                        Label(item.text, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                        Text("Not saved. \(message)")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if card.hasResults {
                Button("OK") { controller.dismissSaveSuggestions() }
                    .buttonStyle(SecondaryButtonStyle())
            } else {
                HStack {
                    Button(card.tickedCount > 1 ? "Save \(card.tickedCount) notes" : "Save note") {
                        Task { await controller.saveTickedSuggestions() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(card.tickedCount == 0 || card.isSaving)
                    .accessibilityIdentifier("voice.suggestion.save")
                    Button("Not now") { controller.dismissSaveSuggestions() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(card.isSaving)
                        .accessibilityIdentifier("voice.suggestion.dismiss")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice.saveSuggestions")
    }

    static func priorityText(_ priority: ReminderPriority) -> String {
        switch priority {
        case .none: NSLocalizedString("None", comment: "Reminder priority")
        case .low: NSLocalizedString("Low", comment: "Reminder priority")
        case .medium: NSLocalizedString("Medium", comment: "Reminder priority")
        case .high: NSLocalizedString("High", comment: "Reminder priority")
        }
    }

    private func isEmptyPlan(_ pending: VoiceSessionController.PendingAction, controller: VoiceSessionController) -> Bool {
        if case .plan = pending { return controller.planTicked.isEmpty }
        // Several changes (ADR-280): nothing ticked, nothing to confirm.
        if case .bulk(_, let items, _, _) = pending { return items.allSatisfy { controller.bulkUnticked.contains($0.id) } }
        // Ingredients (ADR-305): nothing ticked, nothing to add.
        if case .ingredients(_, _, _, _, let items, _) = pending { return controller.ingredientsUnticked.count >= items.count }
        return false
    }

    private func actionLabels(_ pending: VoiceSessionController.PendingAction, controller: VoiceSessionController) -> (confirm: String, decline: String) {
        switch pending {
        case .memory: (NSLocalizedString("Save", comment: ""), NSLocalizedString("Don't save", comment: ""))
        case .event, .reminder: (NSLocalizedString("Add", comment: ""), NSLocalizedString("Don't add", comment: ""))
        case .timer: (NSLocalizedString("Start", comment: ""), NSLocalizedString("Don't start", comment: ""))
        case .alarm: (NSLocalizedString("Set alarm", comment: ""), NSLocalizedString("Don't set", comment: ""))
        case .cancelAlarm: (NSLocalizedString("Turn off", comment: ""), NSLocalizedString("Keep it", comment: ""))
        case .map: (NSLocalizedString("Open in Maps", comment: ""), NSLocalizedString("Don't open", comment: ""))
        case .shortcut: (NSLocalizedString("Run", comment: ""), NSLocalizedString("Don't run", comment: ""))
        case .message(_, let draft, _): (draft.channel == .text ? NSLocalizedString("Open in Messages", comment: "") : NSLocalizedString("Open in Mail", comment: ""), NSLocalizedString("Don't open", comment: ""))
        case .blik: (NSLocalizedString("I'll send it myself", comment: "BLIK card: the user sends it in their bank app"), NSLocalizedString("Not now", comment: ""))
        case .cloud(_, _, let preview, _, _): (preview.confirmLabel, NSLocalizedString("Don't do this", comment: ""))
        case .ask(_, let card, _, _, _): (card.confirmLabel, NSLocalizedString("No", comment: ""))
        case .cloudRead(_, _, let preview, _, _): (preview.confirmLabel, NSLocalizedString("No", comment: ""))
        case .noteReminder: (NSLocalizedString("Set reminder", comment: ""), NSLocalizedString("Don't set", comment: ""))
        case .createList: (NSLocalizedString("Create list", comment: ""), NSLocalizedString("Not now", comment: ""))
        case .changeEvent: (NSLocalizedString("Change", comment: ""), NSLocalizedString("Don't change", comment: ""))
        case .deleteEvent, .deleteReminder: (NSLocalizedString("Delete", comment: ""), NSLocalizedString("Don't delete", comment: ""))
        case .bulk(_, let items, let verb, _):
            (String(format: verb == "deleted" ? NSLocalizedString("Delete %lld", comment: "") : NSLocalizedString("Move %lld", comment: ""),
                    items.filter { !controller.bulkUnticked.contains($0.id) }.count),
             NSLocalizedString("Not now", comment: ""))
        case .changeReminder(_, _, let draft): (draft.markDone ? NSLocalizedString("Mark done", comment: "") : NSLocalizedString("Change", comment: ""), NSLocalizedString("Don't change", comment: ""))
        case .plan(_, let steps, _): (PlanProposal.confirmTitle(steps.filter { controller.planTicked.contains($0.number) }), NSLocalizedString("Not now", comment: ""))
        case .undo(_, let entry): (entry.undo?.buttonTitle(.current) ?? NSLocalizedString("Undo", comment: ""), NSLocalizedString("Keep it", comment: ""))
        case .parking: (NSLocalizedString("Save", comment: ""), NSLocalizedString("Don't save", comment: ""))
        case .leaveBy: (NSLocalizedString("Set reminder", comment: ""), NSLocalizedString("Not now", comment: ""))
        case .ingredients(_, _, _, _, let items, _):
            (String(format: NSLocalizedString("Add %lld", comment: ""), items.count - controller.ingredientsUnticked.count), NSLocalizedString("Not now", comment: ""))
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
        // A note has one reminder: name the one this replaces before the tap (review C3).
        if let previous = controller.noteReminderReplaces {
            Label(NoteReminderReplacement.cardLine(previous), systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote)
                .accessibilityIdentifier("voice.noteReminder.replaces")
        }
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

    /// The access card (ADR-577): the agent asked for a function that is off, or that iOS hasn't
    /// allowed. Allow turns it on in one tap (iOS's own prompt first if it has never asked) and
    /// Doddy carries on by itself; nothing turns on without the tap, and the action still asks for
    /// its own yes. What leaves the phone is on the card; Details opens the full terms. Only when
    /// iOS has said no before does the button open iPhone Settings, the one place iOS lets that change.
    private func accessCard(_ request: ConnectionApprovalCard, controller: VoiceSessionController) -> some View {
        let connection = request.connection
        let info = ConnectionInfo.of(connection)
        return VStack(alignment: .leading, spacing: 12) {
            Label("Allow Doddy to use \(connection.title)?", systemImage: info.symbol)
                .font(.headline)
            switch request.card {
            case .allow:
                Text(info.leavesPhone)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                Button {
                    Task { await controller.allowConnection() }
                } label: {
                    Label("Allow", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(request.isWorking)
                .accessibilityIdentifier("voice.allowConnection")
            case .openSystemSettings:
                if request.sentToSettings {
                    Text("Allow \(connection.title) for Doddy there, then come back. Doddy carries on by itself.")
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Text("iPhone has \(connection.title) turned off for Doddy, so only iPhone Settings can allow it. Doddy carries on when you're back.")
                        .foregroundStyle(Theme.secondaryText)
                }
                Button {
                    Task { await controller.openSettingsForConnection() }
                } label: {
                    Label("Open iPhone Settings", systemImage: "gear")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("voice.openConnectionSettings")
            }
            HStack(spacing: 12) {
                Button("Not now") {
                    Task { await controller.declineConnection() }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!request.canDecline)
                .accessibilityIdentifier("voice.declineConnection")
                Button("Details") {
                    openConnection = connection
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(request.isWorking)
                .accessibilityIdentifier("voice.connectionDetails")
            }
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice.accessCard")
    }

    /// ADR-563: an online account Doddy needs for what was asked. Connect opens the provider's own
    /// sign-in sheet right here (passwords and passkeys fill in as usual, 1Password included).
    private func accountCard(_ needed: VoiceSessionController.AccountNeeded, controller: VoiceSessionController) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Connect \(needed.title)?", systemImage: "link")
                .font(.headline)
            Text("Doddy needs \(needed.title) for this. You sign in with \(needed.title) itself; Doddy never sees your password, and still asks before every look and every send.")
                .foregroundStyle(Theme.secondaryText)
            if let message = controller.accountMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
            }
            HStack(spacing: 12) {
                Button {
                    Task { await controller.connectAccount() }
                } label: {
                    if controller.isConnectingAccount {
                        ProgressView()
                    } else {
                        Label("Connect \(needed.title)", systemImage: "checkmark")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(controller.isConnectingAccount)
                .accessibilityIdentifier("voice.connectAccount")
                Button("Not now") { controller.dismissAccountNeeded() }
                    .accessibilityIdentifier("voice.connectAccountLater")
            }
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    /// ADR-564: a file Claude is making. The link opens in Safari: Quick Look shows the deck,
    /// document or PDF, with Share to save or send it; until it's ready the page says so.
    private func documentCard(_ document: RunDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(document.label) from Claude", systemImage: "doc.richtext")
                .font(.headline)
            Text(document.name)
                .foregroundStyle(Theme.secondaryText)
            Text("It takes a minute or two. Open it now; it shows the file as soon as it's ready.")
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
            Button {
                UIApplication.shared.open(document.url)
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("voice.openDocument")
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

    /// "Where did I park?" (ADR-301): when it was saved and the note; Maps opens only on a tap.
    private func parkingCard(_ spot: ParkingSpot, controller: VoiceSessionController) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your parking spot")
                .font(.headline)
            Text("Saved \(spot.savedAt.formatted(date: .abbreviated, time: .shortened))")
                .foregroundStyle(Theme.secondaryText)
            if let note = spot.note {
                Text("“\(note)”")
            }
            contactAction("Open in Maps", systemImage: "car") { Parking.mapsURL(spot) }
            Button("Close") {
                controller.dismissParkingCard()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice.parkingCard")
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
    /// A change in Calendar or Reminders, checked, with Undo (ADR-258).
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

    /// After "I'll send it myself" (ADR-510): the same details, kept on screen while the user
    /// opens their bank app. Doddy never sends money and can't see whether it was sent.
    private func blikReceiptCard(_ card: VoiceSessionController.BlikCard, controller: VoiceSessionController) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Send it in your bank app").font(.headline)
                Spacer()
                Button { controller.dismissBlikCard() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            blikDetails(card.draft, contactName: card.contactName, numbers: card.numbers, controller: controller)
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("voice.blikCard")
    }

    /// Who, their numbers with Copy, how much and the title (ADR-510). The amount is shown in the
    /// iPhone's language ("50,00 zł" in Polish) but never copied: it is typed in the bank app.
    @ViewBuilder
    private func blikDetails(
        _ draft: BlikTransferDraft, contactName: String?, numbers: [BlikPhoneNumber], controller: VoiceSessionController
    ) -> some View {
        Text(draft.amount.decimal, format: .currency(code: "PLN"))
            .font(.title2.monospacedDigit())
            .accessibilityIdentifier("voice.blik.amount")
        Text("To \(contactName ?? draft.recipientName)")
            .font(.body)
        ForEach(numbers, id: \.self) { number in
            HStack {
                Label(number.shown, systemImage: "phone")
                Spacer()
                blikCopyButton(number.copy, controller: controller)
                    .accessibilityLabel("Copy phone number")
            }
        }
        if numbers.isEmpty {
            Group {
                if contactName == nil {
                    Text("Pick them in your bank app's BLIK phone transfer.")
                } else {
                    Text("No phone number in Contacts. Pick them in your bank app's BLIK phone transfer.")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryText)
        }
        if let title = draft.title {
            HStack {
                Label("“\(title)”", systemImage: "text.alignleft")
                Spacer()
                blikCopyButton(title, controller: controller)
                    .accessibilityLabel("Copy title")
            }
        }
        Text("Doddy doesn't send money and can't see your bank. Check the person and the amount in your bank app before you confirm there. They need BLIK phone transfers turned on in their own bank app.")
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
    }

    private func blikCopyButton(_ text: String, controller: VoiceSessionController) -> some View {
        Button {
            controller.copyForBlik(text)
            copiedForBlik = text
        } label: {
            if copiedForBlik == text {
                Label("Copied", systemImage: "checkmark")
            } else {
                Text("Copy")
            }
        }
        .buttonStyle(.bordered)
        .frame(minHeight: 44)
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

    /// One line under an item on the several-changes card (ADR-280).
    private func bulkDetail(_ item: BulkItem) -> String {
        switch item {
        case .deleteEvent(let event): eventWhen(event)
        case .moveReminder(let reminder, let due): ReminderText.due(reminder.due) + " → " + ReminderText.due(due)
        }
    }

    /// "Repeats every week until Thu 31 Dec 2026" (ADR-282), in the iPhone's language.
    static func repeatText(_ repeats: CalendarRepeat) -> String {
        let base = switch repeats.frequency {
        case .daily: NSLocalizedString("Repeats every day", comment: "")
        case .weekdays: NSLocalizedString("Repeats every weekday (Monday to Friday)", comment: "")
        case .weekly: NSLocalizedString("Repeats every week", comment: "")
        case .everyTwoWeeks: NSLocalizedString("Repeats every two weeks", comment: "")
        case .monthly: NSLocalizedString("Repeats every month", comment: "")
        case .yearly: NSLocalizedString("Repeats every year", comment: "")
        }
        guard let until = repeats.until else { return base }
        return base + " " + String(format: NSLocalizedString("until %@", comment: ""), ReminderText.due(until))
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
        VStack(spacing: 12) {
            // "Listen until I finish" (ADR-364); not in translator mode, which has its own hold-to-talk.
            if controller.isLive && controller.translator == nil || controller.longTurn != .off {
                LongTurnPanel(controller: controller)
            }
            HStack(spacing: 12) { mainControls(controller) }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Theme.canvas)
    }

    @ViewBuilder
    private func mainControls(_ controller: VoiceSessionController) -> some View {
            if controller.isLive {
                Button {
                    Task { await controller.toggleMute() }
                } label: {
                    Label(controller.isMuted ? "Unmute" : "Mute", systemImage: controller.isMuted ? "mic.slash" : "mic")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(controller.longTurn != .off)
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

    /// Doddy's pose on this screen (ADR-299), the island's for the same moment.
    private func screenArt(_ controller: VoiceSessionController) -> VoiceScreenArt {
        let phase: VoiceScreenArt.Phase = switch controller.phase {
        case .idle, .connecting: .connecting
        case .listening: .listening
        case .thinking: .thinking
        case .speaking: .speaking
        case .ended: .ended
        case .microphoneDenied: .microphoneOff
        case .failed: .failed
        }
        let planRunning = controller.planStatus.map { $0.isRunning && !$0.steps.isEmpty } ?? false
        return .shown(phase, muted: controller.isMuted && controller.isLive,
                      awaitingConfirmation: controller.pendingAction != nil, planRunning: planRunning)
    }

        private func statusTitle(_ controller: VoiceSessionController) -> String {
        switch controller.phase {
        case .idle, .connecting: NSLocalizedString("Connecting…", comment: "")
        case .listening: NSLocalizedString("Listening", comment: "")
        case .thinking: NSLocalizedString("Working on it…", comment: "")
        case .speaking: NSLocalizedString("Speaking", comment: "")
        case .ended: NSLocalizedString("Conversation ended", comment: "")
        case .microphoneDenied: NSLocalizedString("Microphone is off", comment: "")
        // A drop after Doddy was listening says so; it is never "Couldn't connect" (ADR-360).
        case .failed: controller.endTitle ?? NSLocalizedString("Couldn't connect", comment: "")
        }
    }
}

/// Offline (ADR-289): what still works without the internet. A note written or dictated here is
/// saved on this iPhone after Save and read back; nothing is queued to send later.
struct OfflineNoteCard: View {
    let controller: VoiceSessionController
    /// After a drop, what Doddy last heard (ADR-360); the user edits or clears it.
    var startText = ""
    @State private var text = ""
    @State private var started = false
    @State private var isSaving = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("You're offline", systemImage: "wifi.slash").font(.headline)
            Text("Doddy's voice needs the internet. You can still write or dictate a note here; it's saved on this iPhone.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            if let saved = controller.offlineSaved {
                Label(String(format: NSLocalizedString("Saved on this iPhone: “%@”", comment: ""), saved), systemImage: "checkmark.circle")
                    .accessibilityIdentifier("voice.offline.saved")
            }
            TextField("Your note", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("voice.offline.note")
            Button {
                Task { await save() }
            } label: {
                HStack { Text("Save note"); Spacer(); Image(systemName: "square.and.arrow.down") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isSaving || text.allSatisfy(\.isWhitespace))
            if let problem { ProblemView(message: problem) }
            Text("When you're back online, close this and talk to Doddy again.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .onAppear {
            guard !started else { return }
            started = true
            text = startText
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        problem = await controller.saveOfflineNote(text)
        if problem == nil {
            text = ""
            controller.discardRecovery()
        }
    }
}

/// After a conversation dropped (OP-023, ADR-360): what Doddy last heard and hadn't answered, or
/// the note it was asking about, as a draft. It is not a note until Save; Discard drops it.
struct RecoveryDraftCard: View {
    let controller: VoiceSessionController
    @State private var isSaving = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let saved = controller.recoverySaved {
                Label(String(format: NSLocalizedString("Saved as a note: “%@”", comment: ""), saved), systemImage: "checkmark.circle")
                    .accessibilityIdentifier("voice.recovery.saved")
            } else if let draft = controller.recovery {
                Group {
                    if draft.pendingNote != nil {
                        Label("Doddy was asking to save this", systemImage: "text.bubble")
                    } else {
                        Label("Doddy last heard you say", systemImage: "text.bubble")
                    }
                }
                .font(.headline)
                Text("A draft, not a note: it's saved only if you tap Save as note.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                TextField("Draft", text: Binding(get: { controller.recovery?.text ?? "" }, set: { controller.editRecovery($0) }), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("voice.recovery.text")
                HStack(spacing: 12) {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack { Text("Save as note"); Spacer(); Image(systemName: "square.and.arrow.down") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isSaving || draft.text.allSatisfy(\.isWhitespace))
                    Button("Discard") { controller.discardRecovery() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                if let problem { ProblemView(message: problem) }
            }
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("voice.recovery")
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        problem = await controller.saveRecovery()
    }
}

/// "Listen until I finish" (OP-019, ADR-364): the button, the listening card with Done, writing
/// out, and a turn that couldn't be sent, kept as a draft to retry, type or drop.
struct LongTurnPanel: View {
    let controller: VoiceSessionController
    private var language: NotificationLanguage { .current }

    var body: some View {
        switch controller.longTurn {
        case .off:
            Button {
                Task { await controller.startLongTurn() }
            } label: {
                Label { Text(verbatim: LongTurn.startLabel(language)) } icon: { Image(systemName: "hand.raised") }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("voice.longTurn.start")
        case .listening(let since):
            VStack(alignment: .leading, spacing: 10) {
                Label { Text(verbatim: LongTurn.listeningTitle(language)).font(.headline) } icon: { Image(systemName: "waveform") }
                Text(verbatim: LongTurn.listeningDetail(language))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(verbatim: "\(LongTurn.clock(context.date.timeIntervalSince(since))) / \(LongTurn.clock(LongTurn.maxSeconds))")
                        .font(.footnote.monospacedDigit()).foregroundStyle(Theme.secondaryText)
                }
                HStack(spacing: 12) {
                    Button {
                        Task { await controller.finishLongTurn() }
                    } label: {
                        HStack { Text("Done"); Spacer(); Image(systemName: "checkmark") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("voice.longTurn.done")
                    Button("Cancel") { Task { await controller.cancelLongTurn() } }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(14)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("voice.longTurn.listening")
        case .writingOut:
            HStack(spacing: 10) {
                ProgressView()
                Text(verbatim: LongTurn.writingOut(language)).font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .draft(let draft):
            VStack(alignment: .leading, spacing: 10) {
                ProblemView(message: LongTurn.problem(draft.problem, language))
                TextField("What you said", text: Binding(get: { draft.text }, set: { controller.editLongTurn($0) }), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("voice.longTurn.text")
                HStack(spacing: 12) {
                    if !draft.text.allSatisfy(\.isWhitespace) {
                        Button {
                            Task { await controller.retryLongTurn() }
                        } label: {
                            HStack { Text("Send"); Spacer(); Image(systemName: "arrow.up") }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    } else if draft.canWriteOutAgain {
                        Button("Try again") { Task { await controller.retryLongTurn() } }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    Button("Discard") { Task { await controller.discardLongTurn() } }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(14)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("voice.longTurn.draft")
        }
    }
}
