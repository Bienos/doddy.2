import Foundation

// Two more of Doddy's own things on a saved note, by voice (decision 2026-11-27-voice-first-doddy, rows of
// docs/product/VOICE_COVERAGE.md still marked "next"): pin a note to the top of Memories (or unpin it), and snooze a
// note's reminder by an hour.
//
// The protocol, as code:
// - The model names the note by its exact text, as for change_note; the app finds exactly one (never a private note) and
//   reads the real state (is it pinned, has it a time reminder) before anything changes (`decidePin`).
// - Both run at once: a pin is a display preference that the opposite action undoes, and a snooze moves a reminder by an
//   hour, which another snooze or the reminder's screen changes again. Neither reaches another app, account or person.
// - Every reply is read back from the store after the change: "pinned" only when the stored pins say so, "snoozed" only
//   when the reminder's time really moved.
//
// Platforms: iPhone and iPad (the voice conversation).

public enum NoteTouchVoice {
    static func parsePin(_ args: Arguments, name: String) -> VoiceToolRequest {
        guard let quote = args.text("note").flatMap(ListText.cleaned) else { return .invalid(name: name, reason: "missing note") }
        switch args.text("action")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pin": return .pinNote(quote: quote, pin: true)
        case "unpin": return .pinNote(quote: quote, pin: false)
        default: return .invalid(name: name, reason: "action must be \"pin\" or \"unpin\"")
        }
    }

    static func parseSnooze(_ args: Arguments, name: String) -> VoiceToolRequest {
        guard let quote = args.text("note").flatMap(ListText.cleaned) else { return .invalid(name: name, reason: "missing note") }
        return .snoozeNoteReminder(quote: quote)
    }

    public enum PinDecision: Equatable, Sendable {
        /// The note is in the other state: toggle it, then read it back.
        case change
        /// Nothing to change; this is what Doddy is told.
        case reply(String)
    }

    public static func decidePin(pin: Bool, isPinned: Bool) -> PinDecision {
        switch (pin, isPinned) {
        case (true, false), (false, true): return .change
        case (true, true): return .reply("not changed: this note is already pinned to the top. Nothing changed.")
        case (false, false): return .reply("not changed: this note isn't pinned. Nothing changed.")
        }
    }

    /// After the change, from the stored pins read again.
    public static func pinResult(pin: Bool, nowPinned: Bool, text: String) -> String {
        guard nowPinned == pin else {
            return VoiceToolReply.failed("The note's pin didn't change. Tell the user it is still \(nowPinned ? "pinned" : "not pinned").")
        }
        return (pin
            ? "changed: the note is pinned to the top of Memories. Unpinning it is the same by voice."
            : "changed: the note is unpinned.") + "\n" + ToolData.block([VoiceToolReply.quoted("Note", text)])
    }

    public static let pinFull =
        "not changed: \(PinnedNotes.maxPins) notes are already pinned, the most there can be. Ask which one to unpin first. Nothing changed."

    /// A place reminder has no time to move.
    public static func notATimeReminder(_ text: String) -> String {
        "not changed: this note's reminder is for a place, not a time, so there is nothing to snooze. Nothing changed.\n"
            + ToolData.block([VoiceToolReply.quoted("Note", text)])
    }

    /// `when` is the reminder as the app words it after the move (`ReminderFormat.summary`).
    public static func snoozed(_ text: String, when: String) -> String {
        "changed: the note's reminder is moved by an hour. It now says the line below; read it from the result.\n"
            + ToolData.block([VoiceToolReply.quoted("Note", text), "- Reminder: \(ToolData.clean(when))"])
    }

    /// The time didn't move (iOS or the store refused): never said as snoozed.
    public static func snoozeFailed(_ text: String) -> String {
        "failed: the reminder's time didn't change, so it was not snoozed. Tell the user it is unchanged.\n"
            + ToolData.block([VoiceToolReply.quoted("Note", text)])
    }
}
