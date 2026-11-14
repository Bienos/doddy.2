import Foundation

/// Texts from Doddy's own number to one of the user's iPhone contacts (owner, 9 Nov 2026: "a możemy
/// zmienić reguły, że dla moich kontaktów tylko", "bez limitów albo 50 tylko"; decision
/// `docs/decisions/2026-11-09-texts-to-contacts.md`).
///
/// The rules, as code so they are tested on Linux:
/// - the number comes from a contact card the app read from iPhone Contacts; the model names the
///   person and never gives a number (`ContactNumber`);
/// - the user taps a card showing the contact, the number and exactly the text; the approval is
///   bound to that number and text (`ApprovalHash.text`), so a changed text needs a new tap;
/// - no signature is added: the text is exactly what the card showed;
/// - at most `maxPerDay` such texts a day per account, and only to the calling codes the server allows.
///
/// This is step 1 of the decision: the rules. Nothing sends a text to a contact yet: the server route,
/// the card and the voice tool come in later steps.
public enum ContactText {
    /// Texts to contacts per account per day (owner, 9 Nov 2026: "50 tylko").
    public static let maxPerDay = 50
    /// Calling code added to a contact's number written without one: the app's users are in Poland.
    public static let defaultCallingCode = "48"

    /// A number read by the app from one contact card. There is no way to make one from the model's words.
    public struct ContactNumber: Equatable, Sendable {
        /// The contact's name as it is in Contacts, for the card.
        public let name: String
        /// E.164, e.g. "+48600123456".
        public let e164: String

        /// `raw` is the number exactly as the contact card has it ("600 123 456", "+48 600-123-456").
        /// Nil when it isn't a phone number that can take a text.
        public init?(contactName: String, raw: String, defaultCallingCode: String = ContactText.defaultCallingCode) {
            let name = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let e164 = ContactText.e164(raw, defaultCallingCode: defaultCallingCode) else { return nil }
            self.name = name
            self.e164 = e164
        }
    }

    public enum Problem: Equatable, Sendable {
        case empty
        case tooLong
        case hiddenCharacter
        /// The number's country isn't one the server texts (`allowed_calling_codes`).
        case numberNotAllowed
        /// `maxPerDay` texts to contacts were already sent today.
        case dailyLimit
    }

    /// Nil when the text may be shown on a card for a tap. Nothing is trimmed: the text is sent as shown.
    public static func problem(body: String, to number: ContactNumber, sentToday: Int, allowedCallingCodes: [String]) -> Problem? {
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        if body.utf16.count > ApprovedTextLimits.maxLength { return .tooLong }
        if ApprovedTextLimits.hiddenCharacter(in: body) != nil { return .hiddenCharacter }
        if !allowedCallingCodes.contains(where: { number.e164.hasPrefix("+" + $0) }) { return .numberNotAllowed }
        if sentToday >= maxPerDay { return .dailyLimit }
        return nil
    }

    /// What the tap approves: exactly this number and this text, the same hash the server checks.
    public static func approvalHash(to number: ContactNumber, body: String) -> String {
        ApprovalHash.text(to: number.e164, body: body)
    }

    /// "+48600123456" from the ways numbers are written in Contacts; nil when it isn't one.
    static func e164(_ raw: String, defaultCallingCode: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Separators people type; anything else (letters, "*", "#", extensions) means it isn't a plain number.
        text.removeAll { " -.()/\u{00A0}".contains($0) }
        if text.hasPrefix("00") { text = "+" + text.dropFirst(2) }
        let international = text.hasPrefix("+")
        let digits = international ? String(text.dropFirst()) : text
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let full: String
        if international {
            full = digits
        } else if digits.count == 9, !digits.hasPrefix("0") {
            // A Polish number written without +48.
            full = defaultCallingCode + digits
        } else {
            return nil
        }
        guard (8...15).contains(full.count), !full.hasPrefix("0") else { return nil }
        return "+" + full
    }
}
