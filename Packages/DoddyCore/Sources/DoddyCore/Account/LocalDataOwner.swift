import Foundation

// Local data belongs to the account that made it (decision 2026-11-12-local-data-owner). Notes, lists and the
// Messages thread live on this iPhone; some of it is also copied to the signed-in account on Doddy's servers
// (the Messages copy for Doddy Web, Memory on calls, notes and conversations kept on the server, Logbook). The
// iPhone records which account its data belongs to, and every one of those uploads asks `upload(for:)` first:
// nothing goes to an account that isn't the owner, and nothing goes while nobody is signed in (DOD-06, DOD-11).
// UI-free and tested on Linux; the app gives it the signed-in account and its stores.

/// Whether this iPhone's data may be sent to the signed-in account's copy on Doddy's servers now.
public enum LocalDataUpload: Equatable, Sendable {
    /// The signed-in account owns this iPhone's data (or this build has no Doddy accounts at all).
    case allowed
    /// Nobody is signed in, or the iPhone hasn't recorded whose data it holds yet. Nothing is sent and nothing
    /// is said: there is no account to send to, or the owner is recorded a moment later.
    case waiting
    /// The data here was made with another account. Nothing is sent to the signed-in one, and the screens that
    /// would send it say why.
    case otherAccount
}

/// This iPhone holds data made with another account than the signed-in one. Uploads are refused until the
/// person erases the data on this iPhone (then the signed-in account takes the empty iPhone over) or the owner
/// signs in again.
public struct DataOwnerMismatch: Equatable, Sendable {
    /// The account the data on this iPhone was made with.
    public let owner: String
    /// The account signed in now.
    public let signedIn: String

    public init(owner: String, signedIn: String) {
        self.owner = owner
        self.signedIn = signedIn
    }
}

public enum LocalDataOwner {
    /// The account id (the account service's user id) the data on this iPhone belongs to. In UserDefaults,
    /// which go with the app: a fresh install starts with no owner.
    public static let ownerKey = "localData.ownerAccountID"

    public enum Claim: Equatable, Sendable {
        /// The signed-in account already owned the data.
        case alreadyOwner
        /// No owner was recorded yet (a first sign-in, or the first launch of this version), or the data on
        /// this iPhone was empty: the signed-in account owns it from now on.
        case adopted
        /// Another account's data is here. It stays on this iPhone and is never sent to the signed-in account.
        case mismatch(DataOwnerMismatch)
    }

    /// The rule. `localDataIsEmpty` matters only when another account is recorded.
    public static func decide(owner: String?, signedIn: String, localDataIsEmpty: Bool) -> Claim {
        guard let owner = normalized(owner) else { return .adopted }
        let signedIn = normalized(signedIn) ?? ""
        if owner == signedIn { return .alreadyOwner }
        return localDataIsEmpty ? .adopted : .mismatch(DataOwnerMismatch(owner: owner, signedIn: signedIn))
    }

    /// The account recorded as the owner, or nil.
    public static func owner(in defaults: UserDefaults = .standard) -> String? {
        normalized(defaults.string(forKey: ownerKey))
    }

    /// After a sign-in, and at launch while signed in. When no owner is recorded the account takes the data
    /// over at once, before anything is awaited, so a launch's first uploads already find it. Only when another
    /// account is recorded is `localDataIsEmpty` asked; the app counts a store it can't read as not empty.
    /// Nil for an empty account id: nothing is recorded.
    @MainActor
    @discardableResult
    public static func claim(
        for signedIn: String, defaults: UserDefaults = .standard, localDataIsEmpty: @MainActor () async -> Bool
    ) async -> Claim? {
        guard let account = normalized(signedIn) else { return nil }
        var empty = true
        if let recorded = owner(in: defaults), recorded != account { empty = await localDataIsEmpty() }
        // Read again after the wait, in case another claim recorded an owner meanwhile.
        let decision = decide(owner: owner(in: defaults), signedIn: account, localDataIsEmpty: empty)
        if decision == .adopted { defaults.set(account, forKey: ownerKey) }
        return decision
    }

    /// The gate every upload of this iPhone's data asks first. `accountsConfigured` is false in a build with no
    /// Doddy accounts set up; such a build has only its own device sign-in, so nothing can go to another person.
    public static func upload(owner: String?, signedIn: String?, accountsConfigured: Bool) -> LocalDataUpload {
        guard accountsConfigured else { return .allowed }
        guard let signedIn = normalized(signedIn), let owner = normalized(owner) else { return .waiting }
        return owner == signedIn ? .allowed : .otherAccount
    }

    public static func upload(
        for signedInAccountID: String?, accountsConfigured: Bool = true, defaults: UserDefaults = .standard
    ) -> LocalDataUpload {
        upload(owner: owner(in: defaults), signedIn: signedInAccountID, accountsConfigured: accountsConfigured)
    }

    /// True only when the signed-in account owns this iPhone's data.
    public static func mayUpload(
        for signedInAccountID: String?, accountsConfigured: Bool = true, defaults: UserDefaults = .standard
    ) -> Bool {
        upload(for: signedInAccountID, accountsConfigured: accountsConfigured, defaults: defaults) == .allowed
    }

    /// The mismatch the screens show, or nil when there is none.
    public static func mismatch(for signedInAccountID: String?, defaults: UserDefaults = .standard) -> DataOwnerMismatch? {
        guard let signedIn = normalized(signedInAccountID), let owner = owner(in: defaults), owner != signedIn else { return nil }
        return DataOwnerMismatch(owner: owner, signedIn: signedIn)
    }

    private static func normalized(_ id: String?) -> String? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !id.isEmpty else { return nil }
        return id
    }
}

/// What a sign-out turns off on this iPhone (decision 2026-11-12-local-data-owner), besides the models' own
/// `accountSignedOut()`: the switches that send this iPhone's data to the account. They stay off until the
/// person turns them on again, signed in. What the account already keeps on Doddy's servers stays there, with
/// the account, until it is deleted from it.
public enum AccountSignOutReset {
    /// Sets each switch off. The app passes its own keys (Memory on calls: `PreferenceKey.memoryCopyOn`).
    public static func apply(switchesOff keys: [String], to defaults: UserDefaults = .standard) {
        for key in keys { defaults.set(false, forKey: key) }
    }
}
