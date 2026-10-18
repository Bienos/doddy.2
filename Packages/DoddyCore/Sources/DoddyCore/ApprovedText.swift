import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// What an approval is bound to (ADR-490, DOD-07): SHA-256 over each field in order, each written
/// as its UTF-8 byte length in decimal, a colon, then its UTF-8 bytes. Length prefixes rather than
/// JSON, so Swift and JavaScript can't disagree on escaping. Nothing is trimmed or normalised: the
/// hash covers exactly the characters the card showed.
///
/// The messaging server computes the same hash (`server/messaging/src/approval.ts`), and both are
/// tested against `contracts/phone/approval-vectors.json`.
public enum ApprovalHash {
    public static let version = "doddy-approval-1"

    /// Lowercase hex.
    public static func hex(_ fields: [String]) -> String {
        var hasher = SHA256()
        for field in fields {
            let bytes = Data(field.utf8)
            hasher.update(data: Data("\(bytes.count):".utf8))
            hasher.update(data: bytes)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// A text from Doddy's number to `to` (E.164), with exactly `body`.
    public static func text(to: String, body: String) -> String {
        hex([version, "text", to, body])
    }
}

/// Texts Doddy may send from its own number (ADR-490 unit U2). Mirrored in
/// `docs/trust/config/doddy_rules.yaml` (contact_policy) and in the server's `routes/texts.ts`.
public enum ApprovedTextLimits {
    /// UTF-16 code units, as the server counts them. Longer is refused, never cut.
    public static let maxLength = 640

    /// A character the card can't show but the approval would still cover: control characters
    /// other than new lines and tabs, and invisible format characters such as right-to-left
    /// overrides and zero-width spaces. The joiners and tag characters that emoji are built
    /// from are allowed. Nil when every character is visible or layout.
    public static func hiddenCharacter(in text: String) -> Unicode.Scalar? {
        text.unicodeScalars.first { scalar in
            switch scalar.properties.generalCategory {
            case .control: !["\n", "\r", "\t"].contains(scalar)
            case .format: !(scalar == "\u{200C}" || scalar == "\u{200D}" || (0xE0020...0xE007F).contains(scalar.value))
            default: false
            }
        }
    }
}

/// How many SMS parts a text takes, so the card can say when it is more than one (each part is
/// billed). The Messaging Service has Smart Encoding off, so any character outside the GSM-7
/// alphabet (Polish letters, emoji) sends the whole text as UCS-2. An estimate for the card,
/// not a billing figure.
public enum SMSSegments {
    public enum Encoding: Equatable, Sendable { case gsm7, ucs2 }

    public static func encoding(_ text: String) -> Encoding {
        text.unicodeScalars.allSatisfy { basic.contains($0) || extended.contains($0) } ? .gsm7 : .ucs2
    }

    public static func count(_ text: String) -> Int {
        switch encoding(text) {
        case .gsm7:
            // An extension character (€, [, ] and so on) takes two of the 160 places.
            let units = text.unicodeScalars.reduce(0) { $0 + (extended.contains($1) ? 2 : 1) }
            return parts(units, single: 160, multi: 153)
        case .ucs2:
            return parts(text.utf16.count, single: 70, multi: 67)
        }
    }

    private static func parts(_ units: Int, single: Int, multi: Int) -> Int {
        if units <= single { return 1 }
        return (units + multi - 1) / multi
    }

    /// GSM 03.38 basic character set.
    private static let basic = Set(
        "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"
            .unicodeScalars)
    /// GSM 03.38 extension table: each is sent as an escape plus the character.
    private static let extended = Set("^{}\\[~]|€\u{000C}".unicodeScalars)
}

/// A text the agent proposed, from Doddy's number to the user's own verified number. Nothing is
/// sent until the user taps Send on the card; the approval then covers exactly `body` and `to`.
public struct ApprovedTextDraft: Equatable, Sendable {
    public let body: String
    /// The user's verified number in E.164, as Doddy's server holds it.
    public let to: String

    public init(body: String, to: String) {
        self.body = body
        self.to = to
    }

    /// The card shows only the last three digits of the number.
    public var recipientEnding: String { String(to.suffix(3)) }

    public var segments: Int { SMSSegments.count(body) }

    /// What the server checks before it queues the text and again before Twilio gets it.
    public var approvalHash: String { ApprovalHash.text(to: to, body: body) }
}

/// Whether a text can be proposed at all: the user verified their number in the app, agreed to
/// texts, and hasn't replied STOP.
public enum TextReadiness: Equatable, Sendable {
    case ready(to: String)
    case noPhone
    case textsOff
    case optedOut

    public init(_ status: PhoneStatus) {
        if let phone = status.phone, status.smsEnabled, !status.optedOut {
            self = .ready(to: phone)
        } else if status.phone == nil {
            self = .noPhone
        } else if status.optedOut {
            self = .optedOut
        } else {
            self = .textsOff
        }
    }
}

extension VoiceToolReply {
    // MARK: text_me (ADR-490 unit U2)
    //
    // "delivered:" is the only done result: the carrier reported the text reached the phone.
    // Twilio accepting it ("sent:") or the server holding it ("queued:") is not delivery, so the
    // agent is told not to say it arrived, and "What Doddy did" shows it as not sure.

    public static let textDeclined = "declined: the user chose not to send this text. Nothing was sent."

    public static let textNoServer =
        "failed: Doddy's server isn't set up in this version of the app, so Doddy can't send texts yet. Nothing was sent."

    public static let textOffline =
        "failed: Doddy couldn't reach its server, so nothing was sent. The user can try again when they're online."

    /// Before the card: the server couldn't say which number is the user's.
    public static func textCheckFailed(_ error: ServerError?) -> String {
        switch error {
        case .offline?: textOffline
        case .accountMissing?: textNotReady(.noPhone)
        default: "failed: Doddy couldn't check the user's number with its server, so nothing was sent. The user can try again in a moment."
        }
    }

    /// After the tap, an answer that means the text certainly wasn't queued (a timeout or a
    /// server error is `textUnknown` instead).
    public static func textNotSent(_ error: ServerError?) -> String {
        switch error {
        case .offline?: textOffline
        case .accountMissing?:
            "failed: Doddy's server no longer knows this iPhone, so the user needs to verify their number again in Settings, Notifications and texts. Nothing was sent."
        default: "failed: Doddy's server gave an answer Doddy didn't expect. Nothing was sent."
        }
    }

    /// The request may have reached Doddy's server but no answer came back (DOD-08, DOD-09).
    public static let textUnknown = """
        unknown: Doddy couldn't confirm whether its server got the text, so it may or may not arrive. \
        Don't say it was sent, and don't call text_me again on your own. If the user asks to try again, \
        call text_me with exactly the same text: the server recognises a repeat of the same approval and \
        sends it at most once.
        """

    public static func textNotReady(_ readiness: TextReadiness) -> String {
        switch readiness {
        case .ready:
            return "failed: something went wrong before the card was shown. Nothing was sent."
        case .noPhone:
            return "failed: the user hasn't verified their phone number in Settings, Notifications and texts, so Doddy has no number to text. Nothing was sent."
        case .textsOff:
            return "failed: texts from Doddy are switched off in Settings, Notifications and texts. The user can turn them on there. Nothing was sent."
        case .optedOut:
            return "failed: the user's number replied STOP to Doddy's texts. They can text START to Doddy's number to allow texts again. Nothing was sent."
        }
    }

    /// The server refused before anything was queued; `code` is its error code.
    public static func textRefused(_ code: String) -> String {
        let reason = switch code {
        case "sms_not_enabled":
            "texts aren't switched on for the user's verified number, or it replied STOP."
        case "approval_mismatch":
            "the user's number changed after the card was shown, so the approval didn't match."
        case "daily_limit":
            "Doddy has already sent the most texts allowed for today (\(ContactCaps.approvedTextsPerDay))."
        case "server_daily_limit":
            "Doddy's server has reached its daily limit for texts."
        case "sms_not_configured":
            "Doddy's phone number isn't set up on the server yet."
        case "rate_limited":
            "there were too many tries in the last hour. Try again later."
        case "invalid":
            "the server didn't accept the text as written (it may be too long or empty)."
        default:
            "the server refused it (\(code))."
        }
        return "failed: \(reason) Nothing was sent."
    }

    /// What the server said about a queued text, a few seconds after it was queued. Nil when the
    /// status couldn't be read: the server has it, nothing more is known.
    public static func textResult(_ status: UpdateStatus?) -> String {
        guard let status else {
            return "queued: Doddy's server accepted the text. Doddy couldn't check yet whether it was sent, so don't say it was sent or that it arrived."
        }
        switch status.state {
        case "queued", "sending":
            return "queued: Doddy's server accepted the text and is sending it. It isn't confirmed as sent yet, so don't say it arrived."
        case "sent" where status.deliveryStatus == "delivered":
            return "delivered: the carrier reported the text reached the user's phone."
        case "sent" where status.deliveryStatus == "undelivered" || status.deliveryStatus == "failed":
            return "failed: Twilio accepted the text, but the carrier couldn't deliver it to the user's phone."
        case "sent":
            return "sent: Twilio accepted the text for the user's number. Delivery isn't confirmed yet, so don't say it arrived."
        case "failed":
            return "failed: \(failureReason(status.errorCode)) Nothing was sent."
        case "unknown":
            return "unknown: Twilio didn't confirm whether the text was sent. Doddy won't send it again; it checks Twilio's records instead. Don't say it was sent, and don't call text_me again for it."
        case "cancelled":
            return "failed: the text was cancelled before it was sent. Nothing was sent."
        default:
            return "unknown: Doddy couldn't tell what happened to the text. Don't say it was sent."
        }
    }

    private static func failureReason(_ code: String?) -> String {
        switch code {
        case "twilio_21610": "the user's number has replied STOP to Doddy's texts."
        case "approval_mismatch": "the text or the number changed after the card was shown, so Doddy didn't send it."
        case let code?: "Twilio refused the text (\(code))."
        case nil: "Twilio refused the text."
        }
    }
}

/// How many calls and texts Doddy may make. Mirrored in `docs/trust/config/doddy_rules.yaml`
/// (contact_policy.caps_default), which is the server's to enforce; a test keeps them equal.
public enum ContactCaps {
    public static let approvedTextsPerDay = 20
}
