import Foundation

/// Doddy's Terms & Conditions and Privacy Policy, and the user's acceptance of them (ADR-581).
///
/// The documents themselves live on the website (`site/terms/`, `site/privacy/`), never in the
/// app. Their versions here must match the "Version" line on those pages: bump both together.
/// Accepting the Terms is not consent to anything optional. The microphone, voice data sharing,
/// online accounts and every other optional use keep their own questions in the app.
public enum LegalDocuments {
    /// The Terms version on https://www.doddy.lol/terms/.
    public static let termsVersion = "2026-10-22"
    /// The Privacy Policy version on https://www.doddy.lol/privacy/.
    public static let privacyVersion = "2026-10-22"
    /// The oldest Terms version that still counts. Raise it to `termsVersion` only when a change
    /// is material and everyone must accept again; a wording fix keeps it.
    public static let minimumTermsVersion = "2026-10-22"
    /// The oldest Privacy Policy version the user must have seen. Raised the same way.
    public static let minimumPrivacyVersion = "2026-10-22"

    public enum Kind: Sendable {
        case terms, privacy
    }

    /// The page for the app's language: Polish has its own pages, every other language the
    /// English ones (the site has no machine-translated legal text).
    public static func url(_ kind: Kind, languageCode: String?) -> URL {
        let polish = (languageCode ?? "").lowercased().hasPrefix("pl")
        let path: String
        switch kind {
        case .terms: path = polish ? "/pl/terms/" : "/terms/"
        case .privacy: path = polish ? "/pl/privacy/" : "/privacy/"
        }
        return URL(string: "https://www.doddy.lol" + path)!
    }
}

/// What was accepted, when and where. Kept on this iPhone; no account is needed to use Doddy.
public struct LegalAcceptanceRecord: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// The "Before we start" step of first use.
        case onboarding
        /// Shown again because the Terms or Privacy Policy changed, or to someone who used
        /// Doddy before the step existed.
        case updatedTerms
    }

    public var termsVersion: String
    public var privacyVersion: String
    public var acceptedAt: Date
    public var source: Source

    public init(termsVersion: String, privacyVersion: String, acceptedAt: Date, source: Source) {
        self.termsVersion = termsVersion
        self.privacyVersion = privacyVersion
        self.acceptedAt = acceptedAt
        self.source = source
    }
}

public enum LegalAcceptance {
    /// UserDefaults key for the JSON record.
    public static let preferenceKey = "legalAcceptance"

    /// Whether the "Before we start" step must be shown: never accepted, or an accepted version
    /// is older than the minimum. Versions are ISO dates, so they compare as strings.
    public static func isNeeded(
        _ record: LegalAcceptanceRecord?,
        minimumTerms: String = LegalDocuments.minimumTermsVersion,
        minimumPrivacy: String = LegalDocuments.minimumPrivacyVersion
    ) -> Bool {
        guard let record else { return true }
        return record.termsVersion < minimumTerms || record.privacyVersion < minimumPrivacy
    }

    /// Someone who used Doddy before the step existed, or whose accepted version is out of date,
    /// sees the "updated" wording; a new user sees "Before we start".
    public static func source(hasUsedDoddyBefore: Bool, previous: LegalAcceptanceRecord?) -> LegalAcceptanceRecord.Source {
        (previous != nil || hasUsedDoddyBefore) ? .updatedTerms : .onboarding
    }

    /// The record for an explicit tap on Accept. There is no other way to make one: nothing is
    /// accepted by continuing, scrolling or a preset switch.
    /// The time is kept to the whole second, as the stored record keeps it, so the record read
    /// back equals the one written.
    public static func accept(at date: Date, source: LegalAcceptanceRecord.Source) -> LegalAcceptanceRecord {
        LegalAcceptanceRecord(
            termsVersion: LegalDocuments.termsVersion, privacyVersion: LegalDocuments.privacyVersion,
            acceptedAt: Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down)), source: source)
    }

    public static func decode(_ data: Data?) -> LegalAcceptanceRecord? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LegalAcceptanceRecord.self, from: data)
    }

    public static func encode(_ record: LegalAcceptanceRecord) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(record)
    }
}
