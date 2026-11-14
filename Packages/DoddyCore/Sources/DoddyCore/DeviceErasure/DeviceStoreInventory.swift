import Foundation

// Which source files keep something on this iPhone, and which store erases it. A test (`DeviceStoreInventoryTests`)
// reads the app's sources and fails when a file starts using a persistent place (Application Support, Caches, Documents,
// the App Group folder, the Keychain, iCloud, the search index, or the folder next to the notes database) without being
// listed here, so a new store can't be added to the app and forgotten by "Erase everything on this iPhone". The words the
// test looks for are in the test itself. The text version, with what each store holds and how it is erased, is
// `docs/architecture/DEVICE_DATA_STORES.md`.

public enum DeviceStoreInventory {
    /// File (from the repository root) → the stores that erase what it keeps.
    public static let sources: [String: [DeviceStoreID]] = [
        // The notes database, and everything opened through it.
        "DoddyApp/Infrastructure/AppEnvironment.swift":
            [.notesAndLists, .learnedFacts, .profile, .callCases, .errands, .messagesThread, .recordings],
        "DoddyApp/Features/Photos/PhotoFiles.swift": [.notePhotoFiles],
        "DoddyApp/Features/VoiceMemos/AudioFiles.swift": [.noteAudioFiles],
        "DoddyApp/Features/Recordings/RecordingFiles.swift": [.recordingFiles],
        // Their own folders in Application Support.
        "DoddyApp/Features/Sport/TrainingLogDatabase.swift": [.trainingLog],
        "DoddyApp/Features/Sport/TrainingPlanStore.swift": [.trainingPlan],
        "DoddyApp/Infrastructure/ConversationLogStore.swift": [.conversationTranscripts],
        "DoddyApp/Infrastructure/ActivityLogStore.swift": [.activityList],
        "DoddyApp/Infrastructure/UnfinishedNoteStore.swift": [.unfinishedNotes],
        "Packages/DoddyCore/Sources/DoddyCore/Invoices/InvoiceDraftFile.swift": [.invoiceDraft],
        "DoddyApp/Features/Messages/LocalMadeFilesStore.swift": [.madeFiles],
        "Packages/DoddyCore/Sources/DoddyCore/Travel/TripStore.swift": [.trips],
        // Caches and the temporary folder, and the plan's own look at the App Group folder.
        "DoddyApp/Features/Studio/StudioView.swift": [.workingFiles],
        "DoddyApp/Features/Privacy/EraseThisIPhone.swift": [.workingFiles, .sharedContainer],
        // The App Group folder.
        "Shared/Widgets/WidgetSnapshotFile.swift": [.sharedContainer],
        "Shared/Share/ShareInboxFile.swift": [.sharedContainer],
        "Shared/Screen/ScreenShareFiles.swift": [.sharedContainer],
        // The Keychain: the items, and the eraser that lists what the Keychain holds.
        "DoddyApp/Infrastructure/AccountKeyStore.swift": [.keychainPersonalKeys],
        "DoddyApp/Infrastructure/Network/KeychainCredentialStore.swift": [.keychainPersonalKeys],
        "DoddyApp/Features/Voice/VoiceAuthSession.swift": [.keychainServerHandles, .keychainPersonalKeys],
        "DoddyApp/Infrastructure/DeviceSession.swift": [.keychainServerHandles],
        "DoddyApp/Infrastructure/KeychainSessionStore.swift": [.keychainServerHandles],
        "DoddyApp/Infrastructure/Server/ServerKeychainStore.swift": [.keychainServerHandles],
        "DoddyApp/Features/Privacy/DeviceKeychainEraser.swift": [.keychainPersonalKeys, .keychainServerHandles],
        // Search and iCloud.
        "DoddyApp/Features/Spotlight/SpotlightSync.swift": [.spotlight],
        "DoddyApp/Features/Sharing/ListCloud.swift": [.sharedListsInICloud],
    ]

    /// Files that mention a persistent place but keep nothing of the person's there, and why.
    public static let reviewedNotStores: [String: String] = [
        "DoddyApp/Features/Messages/FilesShownSinceStore.swift":
            "Reads the creation date of the Documents folder (the install date) and keeps one date in preferences; "
            + "nothing of the person's is written to Documents.",
    ]

    /// Stores that no scan of the sources can find, because they are not behind a file API this list watches, and why.
    public static let notFoundBySourceScanReasons: [DeviceStoreID: String] = [
        .preferences: "UserDefaults keys are spread over many files; the plan erases every key that isn't kept (DevicePreferences).",
        .studio: "Studio's topics and opened items are in a model and in preferences; its cache is in Caches (workingFiles).",
        .notifications: "iOS holds Doddy's scheduled and delivered notifications; the plan removes all of them.",
        .alarmsAndTimers: "AlarmKit holds Doddy's alarms, timers and reminder rings; the plan cancels all of them.",
        .liveActivities: "ActivityKit holds Doddy's Live Activities; the plan ends all of them.",
        .memoryCopyOnServer: "A copy on Doddy's messaging server, emptied through the same client that keeps it equal to the notes.",
    ]

    public static var notFoundBySourceScan: Set<DeviceStoreID> { Set(notFoundBySourceScanReasons.keys) }
}
