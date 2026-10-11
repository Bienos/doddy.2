import Foundation

// Voice fallback and session recovery (OP-023, ADR-330). A voice conversation that stops before
// the user or Doddy ended it is never shown as a normal ending: the screen says it dropped, what
// Doddy last heard and hadn't answered is offered as a draft (a draft, not a note: nothing is saved
// without a tap), and the next conversation is told it was cut off, so Doddy doesn't pretend it
// heard anything after the cut. The conversation log records how each conversation ended.
// Plain Swift for the Linux tests; VoiceSessionController uses it.

/// How a voice conversation ended.
public enum VoiceSessionEnd: Equatable, Sendable {
    /// The user tapped End or Close, or ended it from the island.
    case userEnded
    /// Doddy ended the call (its end_call tool), for example after the user said goodbye.
    case doddyEnded
    /// Started by "Hey Doddy" and nobody spoke (ADR-254).
    case quietTimeout
    /// "Stop listening" (OP-024, ADR-335): from Siri or the listening indicator, which also turn
    /// off "Hey Doddy" and stop a voice memo.
    case stoppedListening
    /// It stopped before either side ended it.
    case dropped(Drop)

    public enum Drop: Equatable, Sendable {
        /// No internet (ADR-289).
        case offline
        /// The other side closed the connection: the server, or the network on the way.
        case connectionLost
        /// The voice service reported an error.
        case error(String)
    }

    /// What the voice SDK said when it disconnected. ElevenLabs 3.3.1 reports `.user` for its own
    /// endConversation, which the app calls on End and which the agent's end_call also triggers,
    /// and `.agent` when the connection is closed from the other side.
    public enum Disconnect: Equatable, Sendable {
        case user, agent, error
    }

    /// The end after a disconnect, given whether the user had asked to end it.
    public static func afterDisconnect(_ disconnect: Disconnect, userAsked: Bool) -> VoiceSessionEnd {
        if userAsked { return .userEnded }
        switch disconnect {
        case .user: return .doddyEnded
        case .agent: return .dropped(.connectionLost)
        case .error: return .dropped(.error(""))
        }
    }

    public var isDrop: Bool {
        if case .dropped = self { return true }
        return false
    }

    /// Kept in the conversation log (`ConversationLog.ended`), so how it ended can be looked at later.
    public var code: String {
        switch self {
        case .userEnded: "user"
        case .doddyEnded: "doddy"
        case .quietTimeout: "quiet"
        case .stoppedListening: "stopped"
        case .dropped(.offline): "dropped-offline"
        case .dropped(.connectionLost): "dropped-connection"
        case .dropped(.error): "dropped-error"
        }
    }
}

/// What Doddy last heard and hadn't answered when a conversation dropped, and any note it was
/// asking to save. Held on the screen only; it becomes a note only when the user taps Save.
public struct RecoveryDraft: Equatable, Sendable {
    /// The user's lines after Doddy's last reply, in order.
    public let unanswered: [String]
    /// The "Save this note?" card that was showing when it dropped.
    public let pendingNote: String?
    public let endedAt: Date
    /// What Save would save; the user can edit it. Starts as the note Doddy was asking about, or
    /// else what it last heard.
    public var text: String

    public init(unanswered: [String], pendingNote: String?, endedAt: Date) {
        self.unanswered = unanswered
        self.pendingNote = pendingNote
        self.endedAt = endedAt
        self.text = pendingNote ?? unanswered.joined(separator: " ")
    }
}

public enum SessionRecovery {
    /// How long after a drop the next conversation is told it was cut off.
    public static let resumeWindow: TimeInterval = 15 * 60

    /// The draft after a drop, from the lines Doddy got as final text. Nil for any other end, or
    /// when there is nothing it hadn't answered and no card was showing. Words the user was still
    /// saying when it dropped never arrived as text, so they can't be in it.
    /// After "Stop listening" only the "Save this note?" card that was showing is kept: the user
    /// chose to stop, so what they said last isn't offered back.
    public static func draft(lines: [ConversationLog.Line], pendingNote: String?, end: VoiceSessionEnd, endedAt: Date) -> RecoveryDraft? {
        if end == .stoppedListening {
            let note = pendingNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return note.isEmpty ? nil : RecoveryDraft(unanswered: [], pendingNote: note, endedAt: endedAt)
        }
        guard end.isDrop else { return nil }
        let afterLastReply = lines.lastIndex(where: { !$0.fromUser }).map { lines.index(after: $0) } ?? lines.startIndex
        let unanswered = lines[afterLastReply...]
            .filter(\.fromUser)
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let note = pendingNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pending = (note?.isEmpty ?? true) ? nil : note
        guard !unanswered.isEmpty || pending != nil else { return nil }
        return RecoveryDraft(unanswered: Array(unanswered), pendingNote: pending, endedAt: endedAt)
    }

    /// The title and line for the end of a conversation. A drop after Doddy was listening is never
    /// "Couldn't connect" and never "Conversation ended".
    public static func status(_ end: VoiceSessionEnd, connected: Bool) -> (title: String, detail: String?) {
        switch end {
        case .userEnded, .doddyEnded, .quietTimeout:
            return ("Conversation ended", nil)
        case .stoppedListening:
            return ("Stopped listening", "Doddy's microphone is off.")
        case .dropped(.offline):
            return ("You're offline", "Doddy's voice needs the internet.")
        case .dropped(let drop) where !connected:
            if case .error(let message) = drop, !message.isEmpty { return ("Couldn't connect", message) }
            return ("Couldn't connect", "Check your internet connection and try again.")
        case .dropped:
            return ("The conversation dropped",
                    "It stopped before you ended it, so Doddy didn't hear anything after that. Nothing was saved because of it.")
        }
    }

    /// For the next conversation, when the newest kept one dropped a short while ago: the agent is
    /// told it was cut off, so it offers to carry on instead of acting as if it heard the rest.
    /// Nil otherwise. Only ever sent with the conversations themselves, so it follows the same
    /// "Remember recent conversations" switch and never applies to a private conversation.
    public static func resumeNote(newest log: ConversationLog?, now: Date, timeZone: TimeZone = .current) -> String? {
        guard let log, let ended = log.ended, ended.hasPrefix("dropped"),
              now.timeIntervalSince(log.endedAt) <= resumeWindow, now >= log.endedAt else { return nil }
        return "Note: the newest conversation below was cut off at \(VoiceContext.format(log.endedAt, timeZone: timeZone)): the connection dropped; neither you nor the user ended it. Say briefly that it was cut off and offer to carry on from its last lines. Do not assume you heard anything after them or that anything after them was done."
    }

    /// The conversations text for the agent (`VoiceContext.recentConversations` of `logs`), with the
    /// resume note first when it applies and the cut-off conversation is among those sent.
    public static func withResumeNote(
        _ recent: VoiceContext.Rendered, logs: [ConversationLog], now: Date, timeZone: TimeZone = .current,
        maxCharacters: Int = VoiceContext.defaultConversationsBudget
    ) -> VoiceContext.Rendered {
        guard let newest = logs.max(by: { $0.endedAt < $1.endedAt }),
              VoiceContext.conversationsSentNextTime(logs, maxCharacters: maxCharacters, timeZone: timeZone).contains(newest.id),
              let note = resumeNote(newest: newest, now: now, timeZone: timeZone) else { return recent }
        return VoiceContext.Rendered(text: note + "\n\n" + recent.text, includedCount: recent.includedCount, truncated: recent.truncated)
    }
}
