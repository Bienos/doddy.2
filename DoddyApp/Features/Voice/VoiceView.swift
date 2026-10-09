import DoddyCore
import SwiftUI
import UIKit

/// Foreground voice conversation. It ends when the screen closes or the app goes to the
/// background (background listening and the Dynamic Island are a later step).
struct VoiceView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PreferenceKey.voiceAgentID) private var agentID = VoiceConfig.developmentAgentID
    @State private var controller: VoiceSessionController?
    @State private var connections = ConnectionController()
    @State private var openConnection: VoiceConnection?

    private var trimmedAgentID: String { agentID.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Group {
                if trimmedAgentID.isEmpty {
                    ScrollView {
                        ProblemView(message: "Voice isn't set up. Add an ElevenLabs agent ID in Settings → Voice.")
                            .padding(24)
                    }
                } else if let controller {
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
            guard !trimmedAgentID.isEmpty else { return }
            let controller = self.controller ?? VoiceSessionController(store: store)
            self.controller = controller
            await controller.start(agentID: trimmedAgentID)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task { await controller?.stop() }
            }
        }
        .onDisappear {
            Task { await controller?.stop() }
        }
        .sheet(item: $openConnection, onDismiss: {
            connections.refresh()
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

                        Text("While you talk, your voice and the notes, calendar entries and contact names Doddy uses are sent to ElevenLabs to run the conversation. Nothing is saved or added unless you tap Save or Add.")
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

    /// Card for anything that changes data. Nothing happens until the user taps the button.
    private func actionCard(_ pending: VoiceSessionController.PendingAction, controller: VoiceSessionController) -> some View {
        let isMemory: Bool
        if case .memory = pending { isMemory = true } else { isMemory = false }
        return VStack(alignment: .leading, spacing: 12) {
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
            }
            Button {
                Task { await controller.confirmPendingAction() }
            } label: {
                HStack { Text(isMemory ? "Save" : "Add"); Spacer(); Image(systemName: "checkmark") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("voice.confirm")
            Button {
                Task { await controller.declinePendingAction() }
            } label: {
                Text(isMemory ? "Don't save" : "Don't add")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    /// Names and details of a contact lookup. Only the agent's copy is names; this is the full view.
    private func contactCard(_ card: VoiceSessionController.ContactCard, controller: VoiceSessionController) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contacts for “\(card.query)”")
                .font(.headline)
            if card.matches.isEmpty {
                Text("No contact matched.")
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(card.matches) { match in
                VStack(alignment: .leading, spacing: 4) {
                    Text(match.name)
                        .font(.body.bold())
                    ForEach(match.phoneNumbers, id: \.self) { number in
                        Text(number).textSelection(.enabled)
                    }
                    ForEach(match.emailAddresses, id: \.self) { address in
                        Text(address).textSelection(.enabled)
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
                    Task { await controller.start(agentID: trimmedAgentID) }
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
