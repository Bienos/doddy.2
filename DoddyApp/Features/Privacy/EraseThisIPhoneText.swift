import DoddyCore
import Foundation

/// The words of "Erase everything on this iPhone": what each store is called when the result names one that wasn't confirmed,
/// and the result line. Each line has its Polish in `l10n/pl.json`. Not compiled on Linux (the hosted `ios-build` job is its
/// first compile).
extension EraseThisIPhone {
    struct Message: Equatable {
        let text: String
        let isProblem: Bool
    }

    /// What the person is told. "Erased" only when every store was read back as empty (`DeviceErasure`, DOD-08); otherwise the
    /// stores that weren't confirmed, by name, and that the rest were.
    static func message(for outcome: Outcome, signedIn: Bool) -> Message {
        switch outcome {
        case .refused(.listening):
            return Message(
                text: NSLocalizedString("Doddy is still listening or recording. End it, then try again. Nothing was erased.", comment: ""),
                isProblem: true)
        case .refused(.sharingScreen):
            return Message(
                text: NSLocalizedString("Doddy is looking at your screen. Stop sharing it, then try again. Nothing was erased.", comment: ""),
                isProblem: true)
        case .finished(let report, let scope):
            switch report.result {
            case .erased:
                var text = NSLocalizedString("Everything Doddy kept on this iPhone is erased.", comment: "")
                if scope.keepsSignIn, signedIn {
                    text += " " + NSLocalizedString("You're still signed in to your Doddy account.", comment: "")
                }
                return Message(text: text, isProblem: false)
            case .notConfirmed(let stores):
                let names = stores.map(title).joined(separator: ", ")
                return Message(
                    text: String(
                        format: NSLocalizedString("Doddy couldn't confirm that these were erased: %@. Everything else was. Try again.", comment: ""),
                        names),
                    isProblem: true)
            }
        }
    }

    /// The store's name for the result line. A `switch` with no `default`: a new store has to be named here too.
    static func title(_ id: DeviceStoreID) -> String {
        switch id {
        case .notesAndLists: NSLocalizedString("Notes and lists", comment: "")
        case .learnedFacts: NSLocalizedString("What Doddy learned", comment: "")
        case .profile: NSLocalizedString("About you", comment: "")
        case .callCases: NSLocalizedString("Calls Doddy made", comment: "")
        case .errands: NSLocalizedString("Tasks", comment: "")
        case .messagesThread: NSLocalizedString("Messages", comment: "")
        case .recordings: NSLocalizedString("Recordings", comment: "")
        case .trainingLog: NSLocalizedString("Training log", comment: "")
        case .notePhotoFiles: NSLocalizedString("Photos on notes", comment: "")
        case .noteAudioFiles: NSLocalizedString("Voice memos on notes", comment: "")
        case .recordingFiles: NSLocalizedString("Recording audio", comment: "")
        case .conversationTranscripts: NSLocalizedString("Remembered conversations", comment: "")
        case .activityList: NSLocalizedString("What Doddy did", comment: "")
        case .unfinishedNotes: NSLocalizedString("Unfinished notes", comment: "")
        case .invoiceDraft: NSLocalizedString("Invoice draft", comment: "")
        case .madeFiles: NSLocalizedString("Files Doddy made", comment: "")
        case .trips: NSLocalizedString("Trips", comment: "")
        case .trainingPlan: NSLocalizedString("Training plan", comment: "")
        case .studio: NSLocalizedString("Studio", comment: "")
        case .workingFiles: NSLocalizedString("Temporary files", comment: "")
        case .sharedContainer: NSLocalizedString("Widgets and sharing", comment: "")
        case .preferences: NSLocalizedString("Settings and saved values", comment: "")
        case .keychainPersonalKeys: NSLocalizedString("Keys you added", comment: "")
        case .keychainServerHandles: NSLocalizedString("Sign-in and server links", comment: "")
        case .notifications: NSLocalizedString("Notifications", comment: "")
        case .alarmsAndTimers: NSLocalizedString("Alarms and timers", comment: "")
        case .liveActivities: NSLocalizedString("Live Activities", comment: "")
        case .spotlight: NSLocalizedString("iPhone search", comment: "")
        case .sharedListsInICloud: NSLocalizedString("Shared lists in iCloud", comment: "")
        case .memoryCopyOnServer: NSLocalizedString("The Memory on calls copy", comment: "")
        }
    }
}
