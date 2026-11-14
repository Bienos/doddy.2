import Foundation

/// One data type the app's privacy manifest (`DoddyApp/Resources/PrivacyInfo.xcprivacy`) declares as collected,
/// in Apple's terms: it leaves the iPhone and Doddy or a service Doddy uses keeps it longer than one answer
/// takes. Each type names the rows of What leaves this iPhone (`DataFlow.rows`) that send it, so the manifest
/// follows the same list the person reads. `PrivacyManifestTests` reads the manifest and fails when its types,
/// linked flags or purposes differ from `DataFlow.collectedData`, or a row named here no longer exists.
public struct CollectedDataType: Equatable, Sendable {
    public enum Purpose: String, CaseIterable, Sendable {
        case appFunctionality = "NSPrivacyCollectedDataTypePurposeAppFunctionality"
        case analytics = "NSPrivacyCollectedDataTypePurposeAnalytics"
    }

    /// Apple's key, e.g. `NSPrivacyCollectedDataTypeEmailAddress`.
    public let type: String
    /// Tied to the person's Doddy account (or their phone number) where it is kept.
    public let linked: Bool
    /// Doddy tracks nobody (`NSPrivacyTracking` is false), so this is false for every type.
    public let tracking: Bool
    public let purposes: Set<Purpose>
    /// The `DataFlowRow.id`s that send it.
    public let rows: [String]

    init(_ type: String, linked: Bool = true, purposes: Set<Purpose> = [.appFunctionality], rows: [String]) {
        self.type = "NSPrivacyCollectedDataType" + type
        self.linked = linked
        self.tracking = false
        self.purposes = purposes
        self.rows = rows
    }
}

extension DataFlow {
    /// Every type is linked: since decision 2026-11-08-required-account everyone signs in with a Doddy account,
    /// and what Doddy's servers keep is kept under it (or under the person's verified phone number). Over-declaring
    /// is the safe direction (ADR-118); the App Store Connect answers are the owner's to confirm.
    public static let collectedData: [CollectedDataType] = [
        // Your voice to ElevenLabs, which keeps a recording of each conversation; calls Doddy places run there too.
        CollectedDataType("AudioData", rows: ["elevenlabs", "translator", "callCases", "phoneRecaps"]),
        // Notes, conversations, typed questions, tasks, Studio topics, the Messages copy, a shared screen.
        CollectedDataType("OtherUserContent", rows: [
            "elevenlabs", "askDoddy", "errands", "studio", "webMemory", "messagesCopy", "screenLook", "recaps", "callCases",
        ]),
        // Your first name from About you on a call's brief, your introduction to the voice, the name Apple or Google gives.
        CollectedDataType("Name", rows: ["elevenlabs", "callCases", "doddyAccount"]),
        // The Doddy account's email address (Supabase; the owner's /admin page shows it).
        CollectedDataType("EmailAddress", rows: ["doddyAccount"]),
        // Your number, once confirmed with a code, for texts and calls.
        CollectedDataType("PhoneNumber", rows: ["messagingServer", "callCases", "updates"]),
        // Contact names and birthdays in a conversation; the name and number of whom Doddy calls for you.
        CollectedDataType("Contacts", rows: ["elevenlabs", "callCases"]),
        // A photo you send with a question in Messages (Doddy's server keeps none; Anthropic keeps requests under its rules).
        CollectedDataType("PhotosorVideos", rows: ["askDoddy"]),
        // The week's Apple Health summary: in Messages (to Anthropic, and in the Messages copy) or to the voice.
        CollectedDataType("Health", rows: ["askDoddy", "messagesCopy", "elevenlabs"]),
        // Steps, distance and floors from Motion & Fitness, to the voice when you ask.
        CollectedDataType("Fitness", rows: ["elevenlabs"]),
        // The Doddy account's id on every Doddy server.
        CollectedDataType("UserID", rows: ["doddyAccount", "doddyServer", "messagingServer"]),
        // The random device ID that signs this iPhone in, and its notification token.
        CollectedDataType("DeviceID", rows: ["doddyServer", "messagingServer"]),
        // Logbook: counts of how you use Doddy, for you on the web and for Doddy's team.
        CollectedDataType("ProductInteraction", purposes: [.analytics, .appFunctionality], rows: ["logbook"]),
    ]
}
