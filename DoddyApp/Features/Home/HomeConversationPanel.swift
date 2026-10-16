import DoddyCore
import SwiftUI

/// Keeps the live voice state on Home; the complete conversation opens only after Transcript.
struct HomeConversationPanel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let controller: VoiceSessionController
    let isStarting: Bool
    let openTranscript: () -> Void
    let toggleMute: () -> Void
    let endConversation: () -> Void
    let hideEndedConversation: () -> Void
    let openSettings: () -> Void

    private var latestReply: String? {
        controller.lines.last(where: { !$0.fromUser })?.text
    }

    @ViewBuilder private var statusTitle: some View {
        if isStarting {
            Text("Starting voice…")
        } else if controller.isPreparingMessageReadBack {
            Text("Preparing spoken review…")
        } else if controller.isReadingMessageDraft {
            Text("Doddy is reading the draft aloud")
        } else if controller.isLive && controller.isMuted {
            Text("Muted")
        } else if controller.connectionNeeded != nil {
            Text("Connection needed")
        } else if controller.pendingMessage != nil && controller.canConfirmMessageByVoice {
            Text("Waiting for your confirmation")
        } else {
            switch controller.phase {
            case .idle: Text("Ready")
            case .connecting: Text("Connecting…")
            case .listening: Text("Listening")
            case .thinking: Text("Thinking…")
            case .speaking: Text("Doddy is speaking")
            case .ended:
                Text(verbatim: controller.endTitle ?? NSLocalizedString("Conversation ended", comment: ""))
            case .microphoneDenied: Text("Microphone is off")
            case .failed:
                Text(verbatim: controller.endTitle ?? NSLocalizedString("Couldn't connect", comment: ""))
            }
        }
    }

    @ViewBuilder private var detailMessage: some View {
        if isStarting {
            Text("Checking microphone access and starting your voice conversation.")
        } else if controller.isPreparingMessageReadBack {
            Text("Getting the message ready to read aloud.")
        } else if controller.isReadingMessageDraft {
            Text("Doddy is reading the recipient and exact message. You can cancel at any time.")
        } else if controller.isLive && controller.isMuted {
            Text("Doddy can't hear you while the microphone is muted.")
        } else if let connection = controller.connectionNeeded {
            Text("\(connection.title) is off or unavailable. Review it in Settings, Connections.")
        } else if controller.pendingMessage != nil && controller.canConfirmMessageByVoice {
            Text("Say “open it” to review the draft in Messages, or “cancel” to discard it.")
        } else {
            switch controller.phase {
            case .connecting: Text("Starting your voice conversation.")
            case .listening: Text("Doddy is listening while this conversation is open.")
            case .thinking: Text("Working on a reply.")
            case .speaking: Text("Doddy's voice is playing.")
            case .microphoneDenied:
                Text("Microphone access is off, so Doddy can't hear you. Turn it on in Settings or use text in the app.")
            case .failed(let message): Text(verbatim: message)
            case .ended, .idle: Text("Your conversation is no longer active.")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Circle()
                    .fill(controller.isLive ? Theme.accentText : Theme.secondaryText)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                statusTitle
                    .font(.headline)
                    .accessibilityIdentifier("home.voice.status")
                Spacer(minLength: 8)
                if controller.isPrivate {
                    Label("Private", systemImage: "eye.slash.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            if let pending = controller.pendingMessage {
                MessageReviewCard(
                    recipientName: pending.draft.recipientName,
                    address: pending.address,
                    message: Binding(
                        get: { controller.pendingMessage?.draft.body ?? "" },
                        set: controller.updatePendingMessageBody
                    ),
                    status: controller.messageReviewStatus,
                    canConfirmByVoice: controller.canConfirmMessageByVoice,
                    open: { Task { await controller.confirmPendingAction() } },
                    cancel: { Task { await controller.declinePendingAction() } }
                )
            } else if let connection = controller.connectionNeeded {
                Text("\(connection.title) is off or unavailable. Review it in Settings, Connections.")
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home.voice.detail")
            } else if case .microphoneDenied = controller.phase {
                detailMessage
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home.voice.detail")
            } else if case .failed = controller.phase {
                detailMessage
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home.voice.detail")
            } else if let latestReply {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latest transcript")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Text(verbatim: latestReply)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(4)
                }
            } else {
                detailMessage
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home.voice.detail")
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 10) { transcriptButton; muteButton; sessionButton }
                } else {
                    HStack(spacing: 10) { transcriptButton; muteButton; sessionButton }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if case .microphoneDenied = controller.phase {
                Button("Open Settings", action: openSettings)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("home.voice.openSettings")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.separator, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private var transcriptButton: some View {
        Button(action: openTranscript) {
            Label("Transcript", systemImage: "text.bubble")
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier("home.voice.transcript")
    }

    @ViewBuilder private var sessionButton: some View {
        if controller.isLive || isStarting {
            Button(action: endConversation) {
                Label(isStarting ? "Cancel" : "End", systemImage: isStarting ? "xmark" : "phone.down")
            }
            .buttonStyle(SecondaryButtonStyle(tint: Theme.error))
            .accessibilityIdentifier("home.voice.end")
        } else {
            Button(action: hideEndedConversation) {
                Label("Hide", systemImage: "xmark")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("home.voice.hide")
        }
    }

    @ViewBuilder private var muteButton: some View {
        if controller.isLive {
            Button(action: toggleMute) {
                Label(controller.isMuted ? "Unmute" : "Mute",
                      systemImage: controller.isMuted ? "mic.slash" : "mic")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(controller.longTurn != .off || controller.isReadingMessageDraft || controller.isPreparingMessageReadBack)
            .accessibilityLabel(controller.isMuted ? "Unmute" : "Mute")
            .accessibilityIdentifier("home.voice.mute")
        }
    }
}
