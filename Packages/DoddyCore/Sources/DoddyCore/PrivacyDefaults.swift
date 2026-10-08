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

    public static let m0 = PrivacyDefaults(
        accountRequired: false, networkRequestsMade: false, microphoneUsed: false,
        contentTelemetryEnabled: false, analyticsEnabled: false, cloudAIEnabled: false, syncEnabled: false)

    /// True when nothing leaves the device and nothing listens.
    public var isFullyLocal: Bool {
        !(accountRequired || networkRequestsMade || microphoneUsed || contentTelemetryEnabled
            || analyticsEnabled || cloudAIEnabled || syncEnabled)
    }
}

/// User-selectable appearance. Persisted by the app as a UI preference only.
public enum AppearancePreference: String, CaseIterable, Sendable {
    case system, light, dark
}
