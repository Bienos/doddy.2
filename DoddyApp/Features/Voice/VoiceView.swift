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
    @State private var reviewingReminder: VoiceSessionController.PendingReminder?

    /// Server token when a Doddy server is connected; the public agent only in debug builds.
    private var auth: VoiceAuthChoice {
        VoiceAuthPolicy.choose(
            serverConfigured: ServerConfig.baseURL() != nil, publicAgentID: agentID,
            allowPublicAgent: ServerConfig.allowsPublicVoiceAgent)
    }

    var body: some View {
        NavigationStack {
            Group {
                if case .unavailable(let reason) = auth {
                    ScrollView {
                        ProblemView(message: reason)
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
            let auth = self.auth
            if case .unavailable = auth { return }
            let controller = self.controller ?? VoiceSessionController(store: store)
            self.controller = controller
            await controller.start(auth: auth, server: ServerConfig.client())
        }
        .sheet(item: $reviewingReminder) { reminder in
            ReminderProposalView(initialTitle: reminder.title, initialDue: reminder.due, sourceMemoryID: nil) { action in
                Task { await controller?.finishReminder(reminder.toolCallID, action) }
            }
        }
        .onChange(of: controller?.pendingReminder) { _, pending in
            // Opens the review screen as soon as Doddy proposes a reminder.
            if let pending, reviewingReminder == nil { reviewingReminder = pending }
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

                        if let pending = controller.pendingSave {
                            saveCard(pending, controller: controller)
                                .id("pendingSave")
                        }

                        if let reminder = controller.pendingReminder {
                            Button {
                                reviewingReminder = reminder
                            } label: {
                                HStack { Text("Review reminder: \(reminder.title)"); Spacer(); Image(systemName: "bell") }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("voice.reviewReminder")
                        }

                        Text("While you talk, your voice and the notes Doddy looks up are sent to ElevenLabs to run the conversation. Nothing is saved unless you tap Save.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.top, 8)
                    }
                    .padding(24)
                }
                .onChange(of: controller.lines.count) { _, _ in
                    if let last = controller.lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onChange(of: controller.pendingSave) { _, pending in
                    if pending != nil { withAnimation { proxy.scrollTo("pendingSave", anchor: .bottom) } }
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

    private func saveCard(_ pending: VoiceSessionController.PendingSave, controller: VoiceSessionController) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save this note?")
                .font(.headline)
            Text("“\(pending.text)”")
                .font(.body)
            Button {
                Task { await controller.confirmSave() }
            } label: {
                HStack { Text("Save"); Spacer(); Image(systemName: "checkmark") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("voice.confirmSave")
            Button {
                Task { await controller.declineSave() }
            } label: {
                Text("Don't save")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
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
                    Task { await controller.start(auth: auth, server: ServerConfig.client()) }
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
