import Foundation

// Phoning one of the user's contacts to pass on a message, by voice (decision 2026-11-27-voice-first-doddy, step 4,
// second part): "zadzwoń do Marka i powiedz, że spóźnię się o godzinę". The server half is the `tell` kind of call
// (server/messaging/src/taskCalls/tell.ts): its own agent, which says exactly one server-built sentence.
//
// The protocol, as code:
// - The model names the person and writes the message; it never gives a number. The tool has no number argument, and
//   the app reads it from the contact card in iPhone Contacts (`TellByPhoneVoice.place`). A number from an email, a
//   page, the screen or a caller can't be dialled.
// - Several contacts that match are never guessed between: the user is asked for the full name.
// - Only a Polish number Doddy may call (`PolishNumber`); the server checks it again with its own limits, hours and
//   the blocked list.
// - The card shows the name, the number, exactly what Doddy will say and what he won't do; a tap, or the user's own
//   "tak, dzwoń" after the card appeared, approves exactly that (`ConfirmationTiers.strongYes`). After outside text only
//   a tap works.
// - On the call Doddy says he is a virtual assistant, passes on the message word for word, listens to one short reply
//   and agrees to nothing; anyone who tries to steer him ends the call.
//
// Platforms: iPhone and iPad (the voice conversation).

public enum TellByPhoneVoice {
    /// The message, as the server allows it (server/messaging/src/taskCalls/tell.ts): one breath on the phone.
    public static let messageMin = 3
    public static let messageMax = 300

    static func parse(_ args: Arguments, name: String) -> VoiceToolRequest {
        guard let person = args.text("name")?.trimmingCharacters(in: .whitespacesAndNewlines), !person.isEmpty else {
            return .invalid(name: name, reason: "missing name: the contact's name as the user said it")
        }
        guard person.count <= CallTaskLimits.nameLength else {
            return .invalid(name: name, reason: "a name is longer than \(CallTaskLimits.nameLength) characters")
        }
        guard let message = args.text("message")?.trimmingCharacters(in: .whitespacesAndNewlines),
              message.count >= messageMin else {
            return .invalid(name: name, reason: "missing message: what Doddy should say, at least \(messageMin) characters")
        }
        guard message.count <= messageMax else {
            return .invalid(name: name, reason: "message is longer than \(messageMax) characters; one short breath on the phone")
        }
        if ApprovedTextLimits.hiddenCharacter(in: message) != nil {
            return .invalid(name: name, reason: "message has a hidden character; write it without one")
        }
        if message.contains("{") || message.contains("}") {
            return .invalid(name: name, reason: "no curly braces in the message")
        }
        return .tellByPhone(name: person, message: message)
    }

    /// The first of the contact's numbers Doddy may call (Poland only, no short, premium or special numbers).
    public static func place(name: String, phoneNumbers: [String]) -> CallTaskPlace? {
        let shown = name.filter { $0 != "{" && $0 != "}" }.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shown.isEmpty, shown.count <= CallTaskLimits.nameLength else { return nil }
        for raw in phoneNumbers {
            if case .allowed = PolishNumber.classify(raw) { return CallTaskPlace(name: shown, phone: raw) }
        }
        return nil
    }

    /// What goes to the server: one person, the message, no question (the server builds it), no text to the user.
    public static func draft(place: CallTaskPlace, message: String) -> CallTaskDraft {
        let goal = String("Przekazać wiadomość: \(place.name)".prefix(CallTaskLimits.goalLength))
        return CallTaskDraft(places: [place], question: "", goal: goal, textResult: false, message: message)
    }

    // MARK: Replies (the first word is what the prompt's rules read)

    public static func notFound(_ query: String) -> String {
        "not found: no contact in Contacts matches \u{201C}\(query)\u{201D}. Nobody was called. Say so and ask who they meant; never ask for a number."
    }

    public static func severalContacts(_ names: [String], query: String) -> String {
        "needs detail: \(names.count) contacts match \u{201C}\(query)\u{201D}: \(names.prefix(5).joined(separator: ", ")). Ask which one, by full name, then call tell_by_phone again with it. Nobody was called."
    }

    public static func noNumber(_ name: String) -> String {
        "failed: \(name) has no Polish phone number in Contacts that Doddy may call. Nobody was called. Say so; don't ask the user for a number. Offer text_contact or call_contact (the user taps Call)."
    }

    public static let off =
        "not available: messages by phone aren't switched on on Doddy's server yet. Nobody was called. Offer text_contact, or call_contact so the user phones them."

    public static let declined = "declined: the user chose not to have Doddy call with this message. Nobody was called."
}
