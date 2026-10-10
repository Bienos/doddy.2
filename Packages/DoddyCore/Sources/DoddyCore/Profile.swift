import Foundation

// Reviewed personal profile (design/interface-v1.2/docs/ONBOARDING-AND-PERSONAL-HOME.md).
// Answers are a transient draft until the user reviews them and taps Save; only then are
// the approved fields stored. Nothing here is inferred, and the profile is separate from
// saved memories.

/// The six optional fields the first introduction may ask about. Nothing else is stored.
public enum ProfileKey: String, CaseIterable, Codable, Sendable {
    case name, help, style, language, humor, context

    /// Maximum length in Unicode scalars (same counting rule as memories and SQLite `length`).
    public var maxLength: Int {
        switch self {
        case .name: 60
        case .help: 240
        case .style: 120
        case .language: 60
        case .humor: 120
        case .context: 400
        }
    }
}

public enum ProfileSource: String, Codable, Sendable {
    /// The only source: the user reviewed the value and tapped Save.
    case explicitUserReview = "explicit_user_review"
}

public enum ProfileValidationError: Error, Equatable, Sendable {
    case tooLong(ProfileKey, length: Int, maximum: Int)
}

/// One approved, stored field.
public struct ProfileField: Equatable, Sendable {
    public let key: ProfileKey
    public let value: String
    public let source: ProfileSource
    public let approvedAt: Date
    /// Starts at 1; increases each time the user approves a changed value.
    public let revision: Int

    public init(key: ProfileKey, value: String, source: ProfileSource = .explicitUserReview, approvedAt: Date, revision: Int) {
        self.key = key
        self.value = value
        self.source = source
        self.approvedAt = approvedAt
        self.revision = revision
    }
}

/// What is currently stored. Missing fields are simply absent.
public struct ApprovedProfile: Equatable, Sendable {
    public let fields: [ProfileKey: ProfileField]

    public init(fields: [ProfileKey: ProfileField] = [:]) {
        self.fields = fields
    }

    public static let empty = ApprovedProfile()

    public var isEmpty: Bool { fields.isEmpty }

    public func value(_ key: ProfileKey) -> String? { fields[key]?.value }

    /// The approved values as an editable draft (for "Edit" in Settings).
    public var draft: ProfileDraft { ProfileDraft(values: fields.mapValues(\.value)) }
}

/// Unsaved answers. Lives only in memory; never written until `ProfileRepository.commit`.
public struct ProfileDraft: Equatable, Sendable {
    public private(set) var values: [ProfileKey: String]

    public init(values: [ProfileKey: String] = [:]) {
        self.values = values
    }

    public subscript(key: ProfileKey) -> String? {
        get { values[key] }
        set { values[key] = newValue }
    }

    public mutating func remove(_ key: ProfileKey) { values[key] = nil }

    /// True when there is nothing worth reviewing (every answer blank or skipped).
    public var isEffectivelyEmpty: Bool {
        values.values.allSatisfy { ProfileDraft.normalize($0).isEmpty }
    }

    /// Trimmed values ready to store. Blank answers are dropped (they mean "skipped");
    /// an over-long answer is an error, never silently cut.
    public func validated() throws -> [ProfileKey: String] {
        var result: [ProfileKey: String] = [:]
        for key in ProfileKey.allCases {
            guard let raw = values[key] else { continue }
            let value = ProfileDraft.normalize(raw)
            if value.isEmpty { continue }
            let length = value.unicodeScalars.count
            guard length <= key.maxLength else {
                throw ProfileValidationError.tooLong(key, length: length, maximum: key.maxLength)
            }
            result[key] = value
        }
        return result
    }

    /// Trims surrounding whitespace and collapses line breaks to spaces (profile values are
    /// one line each).
    public static func normalize(_ raw: String) -> String {
        raw.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Preset answers shown as chips. The user can always type their own words instead.
public enum ProfileChoices {
    public static func options(for key: ProfileKey) -> [String] {
        switch key {
        case .name, .context: []
        case .help: ["Keep useful details", "Help me follow through", "Explain things clearly", "A bit of everything"]
        case .style: ["Short and clear", "More detail", "Talk it through"]
        case .language: ["Follow my language", "English", "Polski"]
        case .humor: ["A little, when it fits", "Just the useful bit"]
        }
    }
}

public enum ProfileStoreError: Error, Equatable, Sendable {
    /// The stored profile changed since the draft was opened. The draft is kept; nothing
    /// was written.
    case revisionConflict
    /// The write could not be read back exactly. Treated as not saved.
    case verificationFailed
    /// A stored row no longer satisfies the domain rules.
    case corruptRecord(String)
}

/// Durable profile and onboarding progress. Writes are atomic and read back before success.
public protocol ProfileRepository: Sendable {
    func profile() async throws -> ApprovedProfile
    /// Replaces the stored profile with `draft` (validated) in one transaction: new or changed
    /// values are stored with a new approval time and revision, unchanged ones are kept as
    /// they are, and keys missing from the draft are removed. Throws `revisionConflict` if the
    /// stored profile is no longer `basedOn`.
    func commit(_ draft: ProfileDraft, basedOn: ApprovedProfile) async throws -> ApprovedProfile
    /// Removes every profile field. Saved memories are not touched.
    func forgetProfile() async throws
    func onboarding() async throws -> OnboardingProgress
    func saveOnboarding(_ progress: OnboardingProgress) async throws -> OnboardingProgress
}

public struct UnavailableProfileRepository: ProfileRepository {
    public init() {}
    public func profile() async throws -> ApprovedProfile { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func commit(_ draft: ProfileDraft, basedOn: ApprovedProfile) async throws -> ApprovedProfile { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func forgetProfile() async throws { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func onboarding() async throws -> OnboardingProgress { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func saveOnboarding(_ progress: OnboardingProgress) async throws -> OnboardingProgress { throw DoddyError.capabilityUnavailable(.memoryStorage) }
}
