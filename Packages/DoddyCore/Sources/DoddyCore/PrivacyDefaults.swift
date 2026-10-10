/// What the app does with data. M0 values are all "off"/"none" because the
/// corresponding features do not exist yet; they are stated in Settings verbatim.
public struct PrivacyDefaults: Equatable, Sendable {
    public let accountRequired: Bool
    public let networkRequestsMade: Bool
    public let microphoneUsed: Bool
    public let contentTelemetryEnabled: Bool
    public let analyticsEnabled: Bool
    public let cloudAIEnabled: Bool
    public let syncEnabled: Bool
    /// Apple Reminders access (iOS only offers full access). Data stays on the device.
    public var remindersUsed: Bool = false

    public static let m0 = PrivacyDefaults(
        accountRequired: false, networkRequestsMade: false, microphoneUsed: false,
        contentTelemetryEnabled: false, analyticsEnabled: false, cloudAIEnabled: false, syncEnabled: false)

    /// V1 voice: the microphone and the ElevenLabs connection are used only while a voice
    /// conversation is open. Saved notes stay on the device; the ones the agent looks up
    /// during a conversation are sent to it.
    public static let v1Voice = PrivacyDefaults(
        accountRequired: false, networkRequestsMade: true, microphoneUsed: true,
        contentTelemetryEnabled: false, analyticsEnabled: false, cloudAIEnabled: true, syncEnabled: false)

    /// M4: V1 voice plus Apple Reminders, asked for the first time the user approves a reminder.
    public static let m4Reminders: PrivacyDefaults = {
        var defaults = v1Voice
        defaults.remindersUsed = true
        return defaults
    }()

    /// True when nothing leaves the device and nothing listens. Reminders access stays on the
    /// device, so it doesn't change this.
    public var isFullyLocal: Bool {
        !(accountRequired || networkRequestsMade || microphoneUsed || contentTelemetryEnabled
            || analyticsEnabled || cloudAIEnabled || syncEnabled)
    }
}

/// User-selectable appearance. Persisted by the app as a UI preference only.
public enum AppearancePreference: String, CaseIterable, Sendable {
    case system, light, dark
}
