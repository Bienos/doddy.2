import Foundation

extension ProfileKey {
    /// Shown in Settings → About you and in the profile export.
    public var label: String {
        switch self {
        case .name: "What to call you"
        case .help: "Useful help"
        case .style: "Answer style"
        case .language: "Language"
        case .humor: "Humor"
        case .context: "Current focus"
        }
    }
}

/// Everything the user chose about how Doddy talks to them, as stored on the phone.
public struct StyleSnapshot: Equatable, Sendable {
    public var personality: PersonalitySettings
    public var voice: VoiceStyle
    public var language: ConversationLanguage
    /// Already cleaned by `Nickname.clean`; nil when unset.
    public var nickname: String?
    /// Settings → About you → "Use in voice conversations".
    public var profileUsedInVoice: Bool
    /// Settings → "Remember recent conversations".
    public var rememberConversations: Bool

    public init(personality: PersonalitySettings, voice: VoiceStyle, language: ConversationLanguage,
                nickname: String?, profileUsedInVoice: Bool, rememberConversations: Bool) {
        self.personality = personality
        self.voice = voice
        self.language = language
        self.nickname = Nickname.clean(nickname)
        self.profileUsedInVoice = profileUsedInVoice
        self.rememberConversations = rememberConversations
    }
}

/// Export of the reviewed profile and style settings (ADR-176). Separate from
/// `MemoryExport`, whose format stays unchanged: memories and the profile are stored and
/// deleted separately, so they are exported separately too.
public enum ProfileExport {
    public static let formatVersion = 1

    private struct Envelope: Encodable {
        let formatVersion: Int
        let exportedAtMs: Int64
        let profile: [Field]
        let settings: Settings
    }

    private struct Field: Encodable {
        let key: String
        let label: String
        let value: String
        let source: String
        let approvedAtMs: Int64
        let revision: Int
    }

    private struct Settings: Encodable {
        let humour: String
        let replyLength: String
        let tone: String
        let energy: String
        let voice: String
        let speakingSpeed: String
        let expressiveness: String
        let conversationLanguage: String
        let nickname: String?
        let profileUsedInVoiceConversations: Bool
        let rememberRecentConversations: Bool
    }

    /// Profile fields in the fixed `ProfileKey` order, so the output is stable.
    private static func fields(_ profile: ApprovedProfile) -> [ProfileField] {
        ProfileKey.allCases.compactMap { profile.fields[$0] }
    }

    public static func json(_ profile: ApprovedProfile, style: StyleSnapshot, exportedAt: Date) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Envelope(
            formatVersion: formatVersion,
            exportedAtMs: EpochMilliseconds.rounded(exportedAt),
            profile: fields(profile).map {
                Field(key: $0.key.rawValue, label: $0.key.label, value: $0.value, source: $0.source.rawValue,
                      approvedAtMs: EpochMilliseconds.rounded($0.approvedAt), revision: $0.revision)
            },
            settings: Settings(
                humour: style.personality.humour.rawValue,
                replyLength: style.personality.length.rawValue,
                tone: style.personality.formality.rawValue,
                energy: style.personality.mood.rawValue,
                voice: style.voice.voice.rawValue,
                speakingSpeed: style.voice.speed.rawValue,
                expressiveness: style.voice.expressiveness.rawValue,
                conversationLanguage: style.language.rawValue,
                nickname: style.nickname,
                profileUsedInVoiceConversations: style.profileUsedInVoice,
                rememberRecentConversations: style.rememberConversations)))
    }

    public static func plainText(_ profile: ApprovedProfile, style: StyleSnapshot, exportedAt: Date) -> String {
        let iso = ISO8601DateFormatter()
        var lines = ["DODDY profile and settings — exported \(iso.string(from: exportedAt))", "", "## About you"]
        let stored = fields(profile)
        if stored.isEmpty {
            lines.append("Nothing saved.")
        }
        for field in stored {
            lines.append("\(field.key.label): \(field.value)")
            lines.append("  Saved \(iso.string(from: field.approvedAt)) after your review (revision \(field.revision))")
        }
        lines.append("Used in voice conversations: \(style.profileUsedInVoice ? "yes" : "no")")
        lines += [
            "",
            "## Voice and personality",
            "Voice: \(style.voice.voice.rawValue)",
            "Speed: \(style.voice.speed.rawValue)",
            "Expressiveness: \(style.voice.expressiveness.rawValue)",
            "Starts in: \(style.language.rawValue)",
            "What Doddy calls you: \(style.nickname ?? "not set")",
            "Humour: \(style.personality.humour.rawValue)",
            "Reply length: \(style.personality.length.rawValue)",
            "Tone: \(style.personality.formality.rawValue)",
            "Energy: \(style.personality.mood.rawValue)",
            "",
            "## Conversations",
            "Remember recent conversations: \(style.rememberConversations ? "yes" : "no")",
            "",
        ]
        return lines.joined(separator: "\n")
    }
}
