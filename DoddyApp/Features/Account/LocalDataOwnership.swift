import DoddyCore
import Foundation

// Decision 2026-11-12-local-data-owner: the data on this iPhone (notes, lists, the Messages thread) belongs to the
// Doddy account that made it. The rules are `LocalDataOwner` in DoddyCore, tested on Linux; this file gives them
// the signed-in account and the app's stores, and says what a sign-out turns off. Not compiled on Linux: the
// hosted ios-build job is its first compile.
//
// The way out of a mismatch is Settings › Memories › "Erase everything on this iPhone" (`EraseThisIPhone`, DoddyCore
// `DeviceErasure`): it erases every store, and only when each was read back as empty it clears the owner and calls
// `claimLocalData()`, so the signed-in account takes the empty iPhone over. That row says so while `localDataMismatch` is not
// nil. The switches that would send data say why nothing is sent (`otherAccountsData`). A button on those screens is not added.
extension DoddyAccountServers {
    /// The gate every upload of this iPhone's data asks first: the Messages copy for Doddy Web, Memory on calls,
    /// notes and conversations kept on Doddy's server, and Logbook.
    static func localDataUpload() -> LocalDataUpload {
        let model = DoddyAccountModel.shared
        return LocalDataOwner.upload(for: model.session?.userID, accountsConfigured: model.isConfigured)
    }

    static var mayUploadLocalData: Bool { localDataUpload() == .allowed }

    /// Another account's data is on this iPhone while this account is signed in, or nil.
    static var localDataMismatch: DataOwnerMismatch? {
        LocalDataOwner.mismatch(for: DoddyAccountModel.shared.session?.userID)
    }

    /// After each new sign-in and at launch while signed in: records whose data this iPhone holds. With no owner
    /// recorded yet (a first sign-in, or the first launch of this version) the account takes it over at once.
    static func claimLocalData() async {
        guard let account = DoddyAccountModel.shared.session?.userID else { return }
        await LocalDataOwner.claim(for: account, localDataIsEmpty: localDataIsEmpty)
    }

    /// No notes, no lists and no messages on this iPhone. A store that can't be read counts as not empty, so
    /// nothing is handed to another account on a guess.
    private static func localDataIsEmpty() async -> Bool {
        let environment = AppEnvironment.shared
        guard let notes = try? await environment.memoryRepository.list(limit: 1),
              let messages = try? await environment.messageThreadRepository.recent(limit: 1)
        else { return false }
        return notes.isEmpty && messages.isEmpty
    }

    /// The Doddy account signed out, by the person or because its session ended. Nothing more of this iPhone's
    /// data is sent: Memory on calls and the notes and conversations kept on Doddy's server are switched off here
    /// (the person turns them on again, signed in), Logbook forgets what it counted for the account, and the
    /// older voice session from Sign in with Apple ends too, so voice needs a sign-in again. What the account
    /// already keeps on Doddy's servers stays with the account until it is deleted from it.
    static func stopUploadsAfterSignOut() {
        AccountSignOutReset.apply(switchesOff: [PreferenceKey.memoryCopyOn])
        MemoryCopySync.shared.stop()
        WebMemory.shared.accountSignedOut()
        Logbook.shared.accountSignedOut()
        let voice = VoiceAuthSession.shared
        if voice.isSignedIn || voice.hasSavedSession { Task { await voice.signOut() } }
    }
}
