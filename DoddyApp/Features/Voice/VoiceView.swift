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
    @AppStorage(PreferenceKey.voiceAgentID) private var agentID = VoiceConfig.developmentAgentID
    @AppStorage(PreferenceKey.voiceTokenServer) private var tokenServer = ""
    @State private var controller: VoiceSessionController?
    @State private var connections = ConnectionController()
    @State private var openConnection: VoiceConnection?

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

                        problem(controller)

                        ForEach(controller.lines) { line in
                            transcriptLine(line)
                                .id(line.id)
                        }

                        if let pending = controller.pendingAction {
                            actionCard(pending, controller: controller)
                                .id("pendingAction")
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
                    if let last = controller.lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onChange(of: controller.pendingAction) { _, pending in
                    if pending != nil { withAnimation { proxy.scrollTo("pendingAction", anchor: .bottom) } }
                }
                .onChange(of: controller.contactCard) { _, card in
                    if card != nil { withAnimation { proxy.scrollTo("contactCard", anchor: .bottom) } }
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
        let labels = actionLabels(pending)
        return VStack(alignment: .leading, spacing: 12) {
            actionContent(pending)
            Button {
                Task { await controller.confirmPendingAction() }
            } label: {
                HStack { Text(labels.confirm); Spacer(); Image(systemName: "checkmark") }
            }
            .buttonStyle(PrimaryButtonStyle())
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
    }

    @ViewBuilder
    private func actionContent(_ pending: VoiceSessionController.PendingAction) -> some View {
        switch pending {
        case .memory(_, let text):
            Text("Save this note?")
                .font(.headline)
            Text("“\(text)”")
                .font(.body)
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
            if let due = draft.due {
                Text(draft.dueHasTime
                     ? due.formatted(date: .abbreviated, time: .shortened)
                     : due.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(Theme.secondaryText)
            }
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
        }
    }

    private func actionLabels(_ pending: VoiceSessionController.PendingAction) -> (confirm: String, decline: String) {
        switch pending {
        case .memory: ("Save", "Don't save")
        case .event, .reminder: ("Add", "Don't add")
        case .timer: ("Start", "Don't start")
        case .map: ("Open in Maps", "Don't open")
        case .shortcut: ("Run", "Don't run")
        case .message(_, let draft, _): (draft.channel == .text ? "Open in Messages" : "Open in Mail", "Don't open")
        }
    }

    /// Shown when the agent asked for something that is switched off. One tap opens the same
    /// Connections sheet as Settings, so the terms are visible before anything turns on.
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
