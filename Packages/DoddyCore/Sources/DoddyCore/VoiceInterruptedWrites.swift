import Foundation

/// A change that ran although the person spoke over it while it was running (decision
/// `2026-11-15-conversation-core-and-corrections`, research "Human Conversation Intelligence" of 15 Nov 2026).
///
/// The problem it closes: most of Doddy's own changes run at once ("Ustaw minutnik na dziesięć…"). If the person
/// speaks while such a tool is running ("…nie, na pięć"), ElevenLabs abandons the call (interruption mode `allow`)
/// and the model is told "Tool execution was abandoned due to user input", so it believes nothing happened. The app
/// had the call already and finishes it: a ten-minute timer is set. The model then sets a five-minute one and says
/// one timer is running. The person has two.
///
/// What this does: it remembers which of those changes were running when the person interrupted, and when one of
/// them finishes it gives the controller one short fact to put into the conversation as background context
/// (`LiveVoiceLink.updateContext`, ElevenLabs' contextual update): the tool, that it ran, and its own result. The
/// prompt says what to do with it (change or undo that one, never make a second). It never changes, undoes or
/// repeats anything itself: the app can't know whether the person's words were a correction or "dzięki".
///
/// What it doesn't cover: a call the provider never sent (nothing ran), a change with a card (it waits for the
/// person and is answered by their tap or yes), a read (abandoning it changes nothing), and a call whose result
/// reached the provider before the interruption (the model has it already).
///
/// Plain Swift: tool names, call ids and the app's own result text in, one string out. Used by the iPhone app; the
/// Watch and Mac apps (paused) don't use it.
public struct VoiceInterruptedWrites: Sendable, Equatable {
    /// Doddy's own changes that run at once with no card (`ToolCatalog`: a change on the iPhone or a text to the
    /// person's own number, approval `runsNow`). Computed from the catalog, so a tool that gains or loses a card is
    /// covered without a second list. Translator mode is a session switch, not a change, and is left out.
    public static let atOnceChanges: Set<String> = Set(ToolCatalog.all.filter {
        ($0.effect == .localChange || $0.effect == .sendText) && $0.approval == .runsNow
    }.map(\.name))

    /// The longest result quoted back. Results are the app's own short sentences; a long one is cut.
    public static let maxResultCharacters = 300

    private var running: [String: String] = [:]
    private var interrupted: Set<String> = []

    public init() {}

    /// A tool call reached the app and is about to run. Only Doddy's own at-once changes are followed.
    public mutating func started(id: String, name: String) {
        guard Self.atOnceChanges.contains(name), !id.isEmpty else { return }
        running[id] = name
    }

    /// The person spoke over Doddy (the provider's interruption event): every change still running may have been
    /// abandoned by the provider.
    public mutating func personInterrupted() {
        interrupted.formUnion(running.keys)
    }

    /// The app answered a call. Returns the fact to put into the conversation when this call was a change that was
    /// still running when the person interrupted, and nil otherwise (and for an id it never saw).
    public mutating func answered(id: String, result: String, isError: Bool) -> String? {
        guard let name = running.removeValue(forKey: id) else { return nil }
        guard interrupted.remove(id) != nil else { return nil }
        return Self.note(tool: name, result: result, isError: isError)
    }

    /// The conversation ended or a new one began.
    public mutating func reset() {
        running = [:]
        interrupted = []
    }

    /// The fact, in English like the rest of the agent's instructions, starting with the app's prefix. The tool name
    /// comes from the agent's own tool list; the result is the app's own text, cut to `maxResultCharacters`, with
    /// line breaks flattened so it stays one line.
    public static func note(tool: String, result: String, isError: Bool) -> String {
        let flat = result.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let quoted = flat.count > maxResultCharacters ? String(flat.prefix(maxResultCharacters)) + "…" : flat
        let name = VoiceTurnTiming.safeName(tool)
        if isError {
            return "(app) \(name) was still running when the user spoke, and it did not go through: \(quoted)"
        }
        return "(app) \(name) had already run when the user spoke, so it is done even if you were told it was abandoned. "
            + "Its result: \(quoted). If the user's words corrected it, change or undo this one; never make a second one."
    }
}
