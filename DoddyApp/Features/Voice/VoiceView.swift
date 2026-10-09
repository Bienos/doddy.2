import SwiftUI
import UIKit

/// Foreground voice conversation. It ends when the screen closes or the app goes to the
/// background (background listening and the Dynamic Island are a later step).
struct VoiceView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(ConnectionsStore.self) private var connections
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PreferenceKey.voiceAgentID) private var agentID = VoiceConfig.developmentAgentID
    @State private var controller: VoiceSessionController?

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
            let controller = self.controller ?? VoiceSessionController(store: store, connections: connections)
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

                        if !controller.contactResults.isEmpty {
                            contactsCard(controller.contactResults)
                        }

                        if let receipt = controller.receipt {
                            Label(receipt.text, systemImage: receipt.verified ? "checkmark.circle.fill" : "questionmark.circle")
                                .foregroundStyle(receipt.verified ? Theme.confirmed : Theme.error)
                                .accessibilityIdentifier("voice.receipt")
                        }

                        if let pending = controller.pendingAction {
                            actionCard(pending, controller: controller)
                                .id("pendingAction")
                        }

                        Text("While you talk, your voice and anything Doddy looks up (notes, calendar events, contact names) are sent to ElevenLabs to run the conversation. Nothing is saved or added unless you tap it.")
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

    private func actionCard(_ pending: VoiceSessionController.PendingAction, controller: VoiceSessionController) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch pending.kind {
            case .saveMemory(let text):
                Text("Save this note?")
                    .font(.headline)
                Text("“\(text)”")
            case .addEvent(let draft):
                Text("Add to Calendar?")
                    .font(.headline)
                Text(draft.title).font(.title3)
                Text(Self.span(draft))
                if let location = draft.location { Text(location).foregroundStyle(Theme.secondaryText) }
                Text("Goes into your default calendar.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            case .addReminder(let draft):
                Text("Add to Reminders?")
                    .font(.headline)
                Text(draft.title).font(.title3)
                Text(draft.due.map { "Due " + Self.when($0, allDay: !draft.dueIncludesTime) } ?? "No due date")
                Text("Goes into your default list.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            Button {
                Task { await controller.confirmPending() }
            } label: {
                HStack { Text(Self.confirmLabel(pending.kind)); Spacer(); Image(systemName: "checkmark") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier(Self.isSave(pending.kind) ? "voice.confirmSave" : "voice.confirmAction")
            Button {
                Task { await controller.declinePending() }
            } label: {
                Text(Self.isSave(pending.kind) ? "Don't save" : "Don't add")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    /// Contact details stay on screen; the voice agent only received the names.
    private func contactsCard(_ matches: [ContactMatch]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("From your contacts")
                .font(.headline)
            ForEach(matches.prefix(5)) { match in
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.displayName).font(.body.bold())
                    ForEach(match.phoneNumbers, id: \.self) { Text($0).textSelection(.enabled) }
                    ForEach(match.emailAddresses, id: \.self) { Text($0).textSelection(.enabled) }
                }
                .accessibilityElement(children: .combine)
            }
            Text("Only the names were shared with the voice agent.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    private static func isSave(_ kind: VoiceSessionController.PendingAction.Kind) -> Bool {
        if case .saveMemory = kind { return true }
        return false
    }

    private static func confirmLabel(_ kind: VoiceSessionController.PendingAction.Kind) -> String {
        switch kind {
        case .saveMemory: "Save"
        case .addEvent: "Add to Calendar"
        case .addReminder: "Add to Reminders"
        }
    }

    static func when(_ date: Date, allDay: Bool) -> String {
        allDay ? date.formatted(date: .complete, time: .omitted) : date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func span(_ draft: EventDraft) -> String {
        if draft.isAllDay { return when(draft.start, allDay: true) + " · all day" }
        return "\(when(draft.start, allDay: false)) – \(draft.end.formatted(date: .omitted, time: .shortened))"
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
