import Foundation

// Texting one of the user's contacts by voice (decision 2026-11-27-voice-first-doddy, step 4; the rules of decision
// 2026-11-09-texts-to-contacts, step 3 and 4): "napisz Ani, że się spóźnię 10 minut". Doddy sends it from his own
// number, through the messaging server's `POST /v1/texts/contact`.
//
// The protocol, as code:
// - The model names the person and writes the text; it never gives a number. The tool has no number argument, and the
//   app reads the number from the contact card in iPhone Contacts (`ContactText.ContactNumber`). So no number from an
//   email, a page, the screen or a call can be texted.
// - Several contacts that match are never guessed between: the user is asked for the full name.
// - A card shows the contact's name, the number and exactly the text; the person's tap or own spoken yes approves
//   exactly that number and that text (`ContactText.approvalHash`, which the server checks again). A changed text is
//   a new card.
// - The server keeps its own limits: 50 a day per account, the allowed countries, a STOP from the recipient, and an
//   account with a verified number of its own.
//
// Platforms: iPhone and iPad (the voice conversation).

public enum ContactTextVoice {
    static func parse(_ args: Arguments, name: String) -> VoiceToolRequest {
        guard let person = args.text("name")?.trimmingCharacters(in: .whitespacesAndNewlines), !person.isEmpty else {
            return .invalid(name: name, reason: "missing name: the contact's name as the user said it")
        }
        // Exactly as the agent wrote it: the card shows it and the approval covers it, so nothing is trimmed.
        guard let body = args.text("text") else { return .invalid(name: name, reason: "missing text") }
        if let problem = ContactText.cardProblem(body: body) {
            switch problem {
            case .tooLong:
                return .invalid(name: name, reason: "text is longer than \(ApprovedTextLimits.maxLength) characters; write a shorter one")
            case .hiddenCharacter:
                return .invalid(name: name, reason: "text has a hidden character; write it without one")
            default:
                return .invalid(name: name, reason: "missing text")
            }
        }
        return .textContact(name: person, body: body)
    }

    /// The card: who, which number, exactly the text, and what the person should know before saying yes.
    public static func card(to number: ContactText.ContactNumber, body: String, polish: Bool) -> AskCard {
        AskCard(
            title: polish ? "Wysłać SMS do: \(number.name)?" : "Text \(number.name)?",
            lines: [
                number.e164,
                "„\(body)”",
                polish
                    ? "Z numeru Doddy'ego, bez podpisu. Odpowiedź na ten SMS do Ciebie nie dotrze."
                    : "From Doddy's number, with no signature. A reply to it won't reach you.",
            ],
            confirmLabel: polish ? "Wyślij" : "Send")
    }

    /// The first of the contact's numbers that can take a text; nil when none can.
    public static func number(name: String, phoneNumbers: [String]) -> ContactText.ContactNumber? {
        phoneNumbers.lazy.compactMap { ContactText.ContactNumber(contactName: name, raw: $0) }.first
    }

    // MARK: Replies (the first word is what the prompt's rules read)

    public static func notFound(_ query: String) -> String {
        "not found: no contact in Contacts matches \u{201C}\(query)\u{201D}. Nothing was sent. Say so and ask who they meant; never ask for a number."
    }

    public static let sentMomentsAgo =
        "failed: Doddy sent exactly this text to this contact a few minutes ago, so it didn't send it again. Nothing new was sent."

    public static func noNumber(_ name: String) -> String {
        "failed: \(name) has no phone number in Contacts that can take a text. Nothing was sent. Say so; don't ask the user for a number."
    }

    public static func severalContacts(_ names: [String], query: String) -> String {
        "needs detail: \(names.count) contacts match \u{201C}\(query)\u{201D}: \(names.prefix(5).joined(separator: ", ")). Ask which one, by full name, then call text_contact again with it. Nothing was sent."
    }

    public static let changedMeanwhile =
        "failed: the contact's number changed after the card was shown, so nothing was sent. Call text_contact again if the user still wants it."

    public static let offOnServer =
        "not available: texts to contacts aren't switched on on Doddy's server yet, so nothing was sent. Offer to open the text in Messages for the user to send themselves (draft_message)."

    public static func refused(_ code: String) -> String {
        if code == "contact_texts_off" { return offOnServer }
        let reason = switch code {
        case "phone_not_verified":
            "Doddy texts other people only for an account with a verified number; the user can verify theirs in Settings, Notifications and texts."
        case "contact_opted_out":
            "this number replied STOP to Doddy's texts, so Doddy doesn't text it."
        case "phone_not_allowed":
            "the number is in a country Doddy doesn't text."
        case "approval_mismatch":
            "the number or the text changed after the card was shown, so the approval didn't match."
        case "daily_limit":
            "Doddy has already sent today's 50 texts to contacts."
        case "server_daily_limit":
            "Doddy's server has reached its daily limit for texts."
        case "rate_limited":
            "too many texts were sent in the last hour."
        default:
            "Doddy's server refused it (\(code))."
        }
        return "failed: nothing was sent: \(reason) Say it in one sentence."
    }

    /// After the server accepted the text: what is known about it, never more (DOD-08).
    public static func result(_ status: UpdateStatus?, to name: String) -> String {
        guard let status else {
            return "queued: Doddy's server accepted the text to \(name). It isn't confirmed as sent yet, so don't say it was sent or that it arrived."
        }
        switch status.state {
        case "queued", "sending":
            return "queued: Doddy's server accepted the text to \(name) and is sending it. Don't say it arrived."
        case "sent" where status.deliveryStatus == "delivered":
            return "delivered: the carrier reported the text reached \(name)'s phone."
        case "sent" where status.deliveryStatus == "undelivered" || status.deliveryStatus == "failed":
            return "failed: Twilio accepted the text, but the carrier couldn't deliver it to \(name)'s phone."
        case "sent":
            return "sent: Twilio accepted the text to \(name). Delivery isn't confirmed yet, so don't say it arrived."
        case "failed":
            return "failed: Doddy's server couldn't send the text to \(name)."
        default:
            return "queued: Doddy's server has the text to \(name); its state is \(status.state). Don't say it arrived."
        }
    }

    public static let unknown = """
        unknown: Doddy couldn't confirm whether its server got the text, so it may or may not arrive. Don't say it was \
        sent, and don't call text_contact again on your own. If the user asks to try again, call it with exactly the same \
        text: the server recognises a repeat of the same approval and sends it at most once.
        """
}

extension ContactText {
    /// What the card can check before the server does: an empty, too long or hidden-character text. The country, the
    /// daily limit and a STOP are checked on the server, which knows them.
    public static func cardProblem(body: String) -> Problem? {
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        if body.utf16.count > ApprovedTextLimits.maxLength { return .tooLong }
        if ApprovedTextLimits.hiddenCharacter(in: body) != nil { return .hiddenCharacter }
        return nil
    }
}
