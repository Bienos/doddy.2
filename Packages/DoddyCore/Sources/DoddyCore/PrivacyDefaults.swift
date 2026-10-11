/// What the app does with data. M0 values are all "off"/"none" because the
/// corresponding features do not exist yet; they are stated in Settings verbatim.
public struct PrivacyDefaults: Equatable, Sendable {
    public let accountRequired: Bool
    public let networkRequestsMade: Bool
    public let microphoneUsed: Bool
    public let contentTelemetryEnabled: Bool
    public let analyticsEnabled: Bool
    public let cloudAIEnabled: Bool
    /// Notes sync between the user's devices. Not built.
    public let syncEnabled: Bool
    /// A list the user shares goes to their iCloud and the people they invite (ADR-263).
    public let sharesListsThroughICloud: Bool

    init(
        accountRequired: Bool, networkRequestsMade: Bool, microphoneUsed: Bool, contentTelemetryEnabled: Bool,
        analyticsEnabled: Bool, cloudAIEnabled: Bool, syncEnabled: Bool, sharesListsThroughICloud: Bool = false
    ) {
        self.accountRequired = accountRequired
        self.networkRequestsMade = networkRequestsMade
        self.microphoneUsed = microphoneUsed
        self.contentTelemetryEnabled = contentTelemetryEnabled
        self.analyticsEnabled = analyticsEnabled
        self.cloudAIEnabled = cloudAIEnabled
        self.syncEnabled = syncEnabled
        self.sharesListsThroughICloud = sharesListsThroughICloud
    }

    public static let m0 = PrivacyDefaults(
        accountRequired: false, networkRequestsMade: false, microphoneUsed: false,
        contentTelemetryEnabled: false, analyticsEnabled: false, cloudAIEnabled: false, syncEnabled: false)

    /// V1 voice: the microphone and the ElevenLabs connection are used only while a voice
    /// conversation is open. Saved notes stay on the device; the notes, calendar entries and
    /// contact names the agent uses during a conversation are sent to it. This is also what the
    /// shipping app states, so it includes the lists the user shares through iCloud.
    public static let v1Voice = PrivacyDefaults(
        accountRequired: false, networkRequestsMade: true, microphoneUsed: true,
        contentTelemetryEnabled: false, analyticsEnabled: false, cloudAIEnabled: true, syncEnabled: false,
        sharesListsThroughICloud: true)

    /// The Settings → Privacy "Sync" row. Shared lists and the server copies are not a sync of
    /// notes, but "Off" alone would hide that lists you share do leave through iCloud.
    public var syncText: String {
        if syncEnabled { return "On" }
        guard sharesListsThroughICloud else { return "Off (not built)" }
        return "Only lists you share, through iCloud. Notes don't sync between devices"
    }

    /// M2: adds typed questions to the Doddy gateway and OpenAI, only after the user turns Ask Doddy on.
    /// Same flags as V1; the difference is which services receive data (see Settings copy).
    public static let m2 = v1Voice

    /// True when nothing leaves the device and nothing listens.
    public var isFullyLocal: Bool {
        !(accountRequired || networkRequestsMade || microphoneUsed || contentTelemetryEnabled
            || analyticsEnabled || cloudAIEnabled || syncEnabled || sharesListsThroughICloud)
    }
}

/// User-selectable appearance. Persisted by the app as a UI preference only.
public enum AppearancePreference: String, CaseIterable, Sendable {
    case system, light, dark
}
