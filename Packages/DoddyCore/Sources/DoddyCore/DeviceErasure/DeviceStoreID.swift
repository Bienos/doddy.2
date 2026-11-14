import Foundation

// "Erase everything on this iPhone": the list of places where Doddy keeps something about a person on this
// iPhone. One case per place that has its own way of being erased and read back. The list is the plan's checklist:
// a plan with no step for a case can never say "erased" (`DeviceErasure.run`), and the app builds its plan with a
// `switch` over every case, so a new case is a compile error until it has a step. The text version, with what each
// holds, is `docs/architecture/DEVICE_DATA_STORES.md`; a test fails if the two drift.
//
// Not on this list, because they are not Doddy's to erase from here: what the person put in Apple's Calendar,
// Reminders, Contacts, Photos or Health (the app reads them or writes on request; they belong to those apps), iOS's
// permission answers, and anything on Doddy's servers (that is the account's deletion, and the Memory on calls copy
// is `memoryCopyOnServer`). The doc says so too.

public enum DeviceStoreID: String, CaseIterable, Sendable, Codable {
    // MARK: The notes database (`Application Support/Memories/memories.sqlite`) and its siblings

    /// Notes, lists and their items, corrections, reminders on notes, list shares, the search index.
    case notesAndLists
    /// What Doddy learned: facts, routines, counts of corrections.
    case learnedFacts
    /// The "About you" answers.
    case profile
    /// Calls Doddy made for the person: cards, answers, transcripts.
    case callCases
    /// Tasks handed to Doddy: words and results.
    case errands
    /// The typed conversation in Messages.
    case messagesThread
    /// Recordings: their rows, words and search index.
    case recordings
    /// The training logbook, in its own SQLite file (`Application Support/Sport`).
    case trainingLog

    // MARK: Files in the app's own folders

    /// Photos on notes (`Memories/NotePhotos`).
    case notePhotoFiles
    /// Voice memos on notes (`Memories/NoteAudio`).
    case noteAudioFiles
    /// Recording audio (`Memories/Recordings`).
    case recordingFiles
    /// The last few voice conversations as text (`Conversations/recent.json`).
    case conversationTranscripts
    /// "What Doddy did" (`Activity/activity.json`).
    case activityList
    /// Notes typed but not saved (`Drafts`).
    case unfinishedNotes
    /// The invoice draft kept between conversations (`Invoices`).
    case invoiceDraft
    /// Files Doddy made, copied here (`MadeFiles`).
    case madeFiles
    /// Trips found in booking emails (`Trips`).
    case trips
    /// The training plan and its answers (`Sport/training-plan.json`).
    case trainingPlan
    /// What Studio keeps on this iPhone: its topics and the items opened here.
    case studio
    /// Temporary files, caches and the Documents folder: anything Doddy wrote there for its own work.
    case workingFiles

    // MARK: The App Group folder (widgets, "Save to Doddy", screen sharing)

    /// The widgets' snapshot, an item waiting from the share extension, the picture of the screen being shared.
    case sharedContainer

    // MARK: Preferences

    /// The app's UserDefaults: settings, and personal values kept there (parking spot, parcel numbers, nickname, ...).
    case preferences

    // MARK: Keychain

    /// Keys the person pasted in (the inFakt key) and retired items.
    case keychainPersonalKeys
    /// The sign-in and what ties this iPhone to Doddy's servers. Erased only after the account was deleted;
    /// otherwise kept on purpose (the sign-in is its own step).
    case keychainServerHandles

    // MARK: What iOS keeps for Doddy

    /// Notifications waiting to be delivered, and delivered ones still in Notification Centre.
    case notifications
    /// Alarms, timers and reminder rings Doddy set with AlarmKit.
    case alarmsAndTimers
    /// Live Activities and Dynamic Island activities of Doddy.
    case liveActivities
    /// Doddy's entries in iPhone search.
    case spotlight

    // MARK: iCloud

    /// Lists shared through iCloud: the copy in the person's iCloud, and the share with the people invited.
    case sharedListsInICloud

    // MARK: A copy the person asked for on Doddy's server

    /// "Memory on calls": the copy of the notes on Doddy's messaging server. The only server step here, because the
    /// switch is the person's and it kept this copy equal to the iPhone's notes until now.
    case memoryCopyOnServer
}

public enum DeviceStoreGroup: String, Sendable {
    case database, files, sharedContainer, preferences, keychain, system, iCloud, server
}

/// Whether a store is in the iPhone's backups (iCloud and computer backups). The rule, in one place: what the person
/// saved to keep is in; what Doddy fetched, recorded or drafted for its own work is out. The database holds both kinds
/// in one file and can't be split without a new file, so its other tables go with the notes (said in the doc).
public enum BackupRule: String, Sendable {
    /// In backups (default for files in Application Support).
    case included
    /// Kept out: the folder is marked `isExcludedFromBackup`.
    case excluded
    /// Some files in, some out.
    case mixed
    /// iOS doesn't back it up (caches, temporary files, Keychain items marked `ThisDeviceOnly`, the search index).
    case notBackedUpByIOS
    /// Not a file (a notification, a Live Activity, an iCloud share).
    case notApplicable
}

extension DeviceStoreID {
    /// The order the app runs the plan in. Each step's erase reads the app's own state, so the order matters:
    /// - sharing is stopped first, while the lists and the links to their iCloud shares still exist;
    /// - the server copy is emptied while the switch that says it exists, and the sign-in it needs, are still there;
    /// - the models that hold things in memory are erased through their own code before the folders they wrote to are
    ///   swept, so a model can't write its old state back;
    /// - preferences go last: other steps read them (private note ids, switches) and write markers there (the recap
    ///   marker, "files before this are not shown again").
    public static let erasureOrder: [DeviceStoreID] = [
        .sharedListsInICloud, .memoryCopyOnServer,
        .notesAndLists, .learnedFacts, .profile, .callCases, .errands, .messagesThread, .recordings, .trainingLog,
        .notePhotoFiles, .noteAudioFiles, .recordingFiles,
        .conversationTranscripts, .activityList, .unfinishedNotes, .invoiceDraft, .madeFiles, .trips, .trainingPlan, .studio,
        .sharedContainer,
        .notifications, .alarmsAndTimers, .liveActivities, .spotlight,
        .keychainPersonalKeys, .keychainServerHandles,
        .workingFiles,
        .preferences,
    ]

    public var group: DeviceStoreGroup {
        switch self {
        case .notesAndLists, .learnedFacts, .profile, .callCases, .errands, .messagesThread, .recordings, .trainingLog:
            .database
        case .notePhotoFiles, .noteAudioFiles, .recordingFiles, .conversationTranscripts, .activityList, .unfinishedNotes,
             .invoiceDraft, .madeFiles, .trips, .trainingPlan, .studio, .workingFiles:
            .files
        case .sharedContainer: .sharedContainer
        case .preferences: .preferences
        case .keychainPersonalKeys, .keychainServerHandles: .keychain
        case .notifications, .alarmsAndTimers, .liveActivities, .spotlight: .system
        case .sharedListsInICloud: .iCloud
        case .memoryCopyOnServer: .server
        }
    }

    public var backup: BackupRule {
        switch self {
        // What the person saved to keep, and what shares the database file with it.
        case .notesAndLists, .learnedFacts, .profile, .callCases, .errands, .messagesThread, .recordings,
             .notePhotoFiles, .noteAudioFiles, .madeFiles, .preferences:
            .included
        // What Doddy fetched, recorded or drafted for its own work.
        case .trainingLog, .trainingPlan, .recordingFiles, .conversationTranscripts, .activityList, .unfinishedNotes,
             .invoiceDraft, .trips:
            .excluded
        case .sharedContainer: .mixed
        case .studio, .workingFiles, .keychainPersonalKeys, .keychainServerHandles, .spotlight: .notBackedUpByIOS
        case .notifications, .alarmsAndTimers, .liveActivities, .sharedListsInICloud, .memoryCopyOnServer: .notApplicable
        }
    }
}
