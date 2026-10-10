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
                        .accessibilityHint("When on, this conversation isn't kept on your iPhone.")
                        .accessibilityIdentifier("voice.private")
                    }
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .task {
            let controller = self.controller ?? VoiceSessionController(store: store)
            self.controller = controller
            await controller.start(mode, profile: profiles.profile)
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

    private func session(_ controller: VoiceSessionController) -> some View {
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

                        Text("While you talk, your voice, this conversation, your saved notes, your last few conversations and any calendar entries, contact names or drafts Doddy uses are sent to ElevenLabs to run Doddy. Weather and Wikipedia lookups run from ElevenLabs\u{2019} servers. Nothing is saved, added, started, sent or opened unless you tap for it. If you leave the app, Doddy keeps listening (you'll see him in the Dynamic Island) until you tap End. If iOS stops Doddy in the background, the island says so instead of pretending he still hears you.")
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
                    if pending != nil { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("pendingAction", anchor: .bottom) } }
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
                ForEach(MemoryCategory.allCases, id: \.self) { Text($0.displayName).tag($0) }
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
        case .noteReminder(_, _, let noteText, let target):
            noteReminderContent(noteText: noteText, target: target, controller: controller)
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
            onToggle: { controller.togglePlanStep($0) }, onChange: { editingPlanStep = $0 })
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
        case .memory: ("Save", "Don't save")
        case .event, .reminder: ("Add", "Don't add")
        case .timer: ("Start", "Don't start")
        case .map: ("Open in Maps", "Don't open")
        case .shortcut: ("Run", "Don't run")
        case .message(_, let draft, _): (draft.channel == .text ? "Open in Messages" : "Open in Mail", "Don't open")
        case .cloud(_, _, let preview, _, _): (preview.confirmLabel, "Don't do this")
        case .noteReminder: ("Set reminder", "Don't set")
        case .plan(_, let steps, _): (PlanProposal.confirmTitle(steps.filter { controller.planTicked.contains($0.number) }), "Not now")
        }
    }

    /// Note reminder card (ADR-198): the note exactly as saved, then the time with its zone, or the
    /// Apple Maps results to pick from. Doddy's own reminder, not Apple Reminders.
    @ViewBuilder
    private func noteReminderContent(
        noteText: String, target: VoiceSessionController.NoteReminderCardTarget, controller: VoiceSessionController
    ) -> some View {
        Text("Remind you about this note?")
            .font(.headline)
        Text("“\(noteText)”")
            .font(.body)
        switch target {
        case .time(let date, let zone):
            Text(ReminderFormat.full(date, timeZoneID: zone))
                .foregroundStyle(Theme.secondaryText)
            Text("A notification on this iPhone from Doddy, not Apple Reminders.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        case .place(let results, let onArrival):
            Text(onArrival ? "When you arrive at (within 200 m):" : "When you leave (within 200 m):")
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
            Text("Each time, until you mark it Done. Uses notifications and your location while you use Doddy; iOS watches the place, Doddy doesn't follow where you go.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
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
        case .idle, .connecting: "Connecting…"
        case .listening: "Listening"
        case .thinking: "Thinking…"
        case .speaking: "Speaking"
        case .ended: "Conversation ended"
        case .microphoneDenied: "Microphone is off"
        case .failed: "Couldn't connect"
        }
    }
}
