import Foundation

// Texts the user sends to Doddy's number (ADR-490 unit U3, ADR-494): they become notes in the
// inbox, or, with replies on, Doddy (Claude, on the server) answers by text. Every switch starts
// off and is only shown as on once the server confirmed it.

public struct TextSettings: Equatable, Sendable, Decodable {
    public struct Available: Equatable, Sendable, Decodable {
        /// The server can receive texts (Twilio's webhook and the encryption key are set up).
        public let notes: Bool
        /// The server can also write replies (Claude is set up).
        public let replies: Bool
    }

    public let available: Available
    public let doddyNumber: String?
    public let phoneVerified: Bool
    /// Doddy may text this number (consent given, no STOP since); replies need it.
    public let textsFromDoddy: Bool
    public let optedOut: Bool
    public let inboundEnabled: Bool
    public let repliesEnabled: Bool
    public let repliesUseMemories: Bool
    /// The memory copy for calls is on; replies can only use memories when it is.
    public let memoryCopy: Bool
    public let language: String
    public let consentTextVersion: String?

    public static let off = TextSettings(
        available: Available(notes: false, replies: false), doddyNumber: nil, phoneVerified: false, textsFromDoddy: false,
        optedOut: false, inboundEnabled: false, repliesEnabled: false, repliesUseMemories: false, memoryCopy: false,
        language: "en", consentTextVersion: nil)

    public init(
        available: Available, doddyNumber: String?, phoneVerified: Bool, textsFromDoddy: Bool, optedOut: Bool,
        inboundEnabled: Bool, repliesEnabled: Bool, repliesUseMemories: Bool, memoryCopy: Bool, language: String,
        consentTextVersion: String?
    ) {
        self.available = available
        self.doddyNumber = doddyNumber
        self.phoneVerified = phoneVerified
        self.textsFromDoddy = textsFromDoddy
        self.optedOut = optedOut
        self.inboundEnabled = inboundEnabled
        self.repliesEnabled = repliesEnabled
        self.repliesUseMemories = repliesUseMemories
        self.memoryCopy = memoryCopy
        self.language = language
        self.consentTextVersion = consentTextVersion
    }

    /// Why a switch can't be turned on yet, in the order the user would fix it; nil when it can.
    public var inboundBlocker: TextsBlocker? {
        if !available.notes { return .notSetUp }
        if !phoneVerified { return .noVerifiedPhone }
        return nil
    }

    public var repliesBlocker: TextsBlocker? {
        if let inboundBlocker { return inboundBlocker }
        if !available.replies { return .repliesNotSetUp }
        if !inboundEnabled { return .textsToDoddyOff }
        if !textsFromDoddy { return .textsFromDoddyOff }
        return nil
    }

    public var memoriesBlocker: TextsBlocker? {
        if let repliesBlocker { return repliesBlocker }
        if !repliesEnabled { return .repliesOff }
        if !memoryCopy { return .memoryCopyOff }
        return nil
    }
}

public enum TextsBlocker: Equatable, Sendable {
    case notSetUp, noVerifiedPhone, repliesNotSetUp, textsToDoddyOff, textsFromDoddyOff, repliesOff, memoryCopyOff

    public var message: String {
        switch self {
        case .notSetUp: "Doddy's phone number isn't set up on the server yet."
        case .noVerifiedPhone: "Verify your phone number in Notifications and texts first."
        case .repliesNotSetUp: "Replies aren't set up on Doddy's server yet."
        case .textsToDoddyOff: "Turn on Texts to Doddy first."
        case .textsFromDoddyOff: "Replies are texts from Doddy: turn on texts in Notifications and texts first. If you sent STOP, text START to Doddy's number."
        case .repliesOff: "Turn on replies first."
        case .memoryCopyOff: "Turn on Memory on calls first: replies use the same copy of your notes."
        }
    }
}

/// The wording next to "Texts to Doddy"; the server stores the version with the consent, so any
/// change to `text` needs a new version.
public enum TextsToDoddyConsent {
    public static let textVersion = "texts-in-v1"
    public static let text = "Texts you send to Doddy's number go to Doddy's server and to Twilio, and wait as notes in the app. If you turn on replies, Doddy, an AI, answers by text, and your text goes to Anthropic to write the answer. Text STOP to stop Doddy's texts; turn this off to stop Doddy keeping yours."
}

extension CallNote {
    /// The note came from a text the user sent Doddy (ADR-494), not from a call.
    public var fromText: Bool { source == "text" }
}

extension DoddyServerClient {
    public func textSettings() async throws -> TextSettings {
        try await getJSON("/v1/texts/settings")
    }

    /// On records consent to `TextsToDoddyConsent.text`; off also turns replies off on the server.
    public func setTextsToDoddy(_ on: Bool, language: NotificationLanguage) async throws {
        try await expect(204, .put, "/v1/texts/settings", TextSettingsBody(
            inboundEnabled: on, language: language.serverCode, consentTextVersion: on ? TextsToDoddyConsent.textVersion : nil))
    }

    public func setTextReplies(_ on: Bool, language: NotificationLanguage) async throws {
        try await expect(204, .put, "/v1/texts/settings", TextSettingsBody(repliesEnabled: on, language: language.serverCode))
    }

    public func setTextRepliesUseMemories(_ on: Bool) async throws {
        try await expect(204, .put, "/v1/texts/settings", TextSettingsBody(repliesUseMemories: on))
    }

    /// Everything the server holds about the user's calls and texts, as JSON for the user to keep.
    public func phoneHistory() async throws -> Data {
        let response = try await authorized(.get, "/v1/phone/history", body: nil)
        guard response.status == 200, (try? JSONSerialization.jsonObject(with: response.body)) is [String: Any]
        else { throw Self.error(from: response) }
        return response.body
    }
}

extension NotificationLanguage {
    /// The code the messaging server uses for Doddy's fixed texts.
    public var serverCode: String { self == .polish ? "pl" : "en" }
}

private struct TextSettingsBody: Encodable {
    var inboundEnabled: Bool? = nil
    var repliesEnabled: Bool? = nil
    var repliesUseMemories: Bool? = nil
    var language: String? = nil
    var consentTextVersion: String? = nil
}
