import Foundation

// Texts the user sends to Doddy's number (ADR-750 unit U3, ADR-753): they become notes in the inbox
// and get no reply from this switch (answers by text are "Text with Doddy", ADR-656, a separate
// consent). The switch starts off and is only shown as on once the server confirmed it.

public struct TextSettings: Equatable, Sendable, Decodable {
    public struct Available: Equatable, Sendable, Decodable {
        /// The server can receive texts (Twilio's webhook and the encryption key are set up).
        public let notes: Bool
    }

    public let available: Available
    public let doddyNumber: String?
    public let phoneVerified: Bool
    /// Doddy may text this number (consent given, no STOP since).
    public let textsFromDoddy: Bool
    public let optedOut: Bool
    public let inboundEnabled: Bool
    /// The memory copy for calls is on (shown elsewhere; texts to Doddy never use it).
    public let memoryCopy: Bool
    public let language: String
    public let consentTextVersion: String?

    public static let off = TextSettings(
        available: Available(notes: false), doddyNumber: nil, phoneVerified: false, textsFromDoddy: false,
        optedOut: false, inboundEnabled: false, memoryCopy: false, language: "en", consentTextVersion: nil)

    public init(
        available: Available, doddyNumber: String?, phoneVerified: Bool, textsFromDoddy: Bool, optedOut: Bool,
        inboundEnabled: Bool, memoryCopy: Bool, language: String, consentTextVersion: String?
    ) {
        self.available = available
        self.doddyNumber = doddyNumber
        self.phoneVerified = phoneVerified
        self.textsFromDoddy = textsFromDoddy
        self.optedOut = optedOut
        self.inboundEnabled = inboundEnabled
        self.memoryCopy = memoryCopy
        self.language = language
        self.consentTextVersion = consentTextVersion
    }

    /// Why the switch can't be turned on yet, in the order the user would fix it; nil when it can.
    public var inboundBlocker: TextsBlocker? {
        if !available.notes { return .notSetUp }
        if !phoneVerified { return .noVerifiedPhone }
        return nil
    }

    /// Switches the server reports as on that can't do their job right now, so the screen never
    /// implies they work.
    public var pauses: [TextsPause] {
        var out: [TextsPause] = []
        if inboundEnabled && !available.notes { out.append(.notReceiving) }
        return out
    }
}

public enum TextsPause: Hashable, Sendable {
    case notReceiving

    public var message: String {
        switch self {
        case .notReceiving: "Doddy's server can't receive texts right now, so nothing you text it is kept."
        }
    }
}

public enum TextsBlocker: Equatable, Sendable {
    case notSetUp, noVerifiedPhone

    public var message: String {
        switch self {
        case .notSetUp: "Texts to Doddy aren't set up on Doddy's server yet."
        case .noVerifiedPhone: "Verify your phone number in Notifications and texts first."
        }
    }
}

/// The wording next to "Texts to Doddy"; the server stores the version with the consent, so any
/// change to `text` needs a new version.
public enum TextsToDoddyConsent {
    public static let textVersion = "texts-in-v1"
    public static let text = "Texts you send to Doddy's number go to Doddy's server and to Twilio, and wait as notes in the app. Doddy does not answer them with this switch. Text STOP to stop Doddy's texts; turn this off to stop Doddy keeping yours."
}

extension CallNote {
    /// The user's own text, word for word (ADR-753).
    public var fromText: Bool { source == "text" }
}

extension DoddyServerClient {
    public func textSettings() async throws -> TextSettings {
        try await getJSON("/v1/texts/settings")
    }

    /// On records consent to `TextsToDoddyConsent.text`.
    public func setTextsToDoddy(_ on: Bool, language: NotificationLanguage) async throws {
        try await expect(204, .put, "/v1/texts/settings", TextSettingsBody(
            inboundEnabled: on, language: language.serverCode, consentTextVersion: on ? TextsToDoddyConsent.textVersion : nil))
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
    var language: String? = nil
    var consentTextVersion: String? = nil
}
