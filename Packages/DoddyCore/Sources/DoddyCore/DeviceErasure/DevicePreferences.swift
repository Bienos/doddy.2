import Foundation

// The preferences (UserDefaults) side of "Erase everything on this iPhone". The app keeps many personal values in
// UserDefaults (a parking spot, parcel numbers, a delivery address, what Doddy calls the person, pinned and private
// note ids, ...) next to ordinary settings, under keys spread over many files. So the rule is turned around:
// **every key is erased unless a rule below says to keep it, and every kept key has a reason.** A key nobody
// classified is erased, which a new feature can only get wrong in the safe direction (it is asked again, not leaked).
//
// What is kept, and why, in plain words (the doc repeats it, `docs/architecture/DEVICE_DATA_STORES.md`):
// - the sign-in, and what ties this iPhone to Doddy's servers (until the account is deleted): without it the app would
//   treat a signed-in person as a device and start a new anonymous account on the server;
// - the markers that say this install already cleared old Keychain items (erased, the next launch would sign the person
//   out), the first-run flags and the Terms acceptance (erased, the first-run screens would cover the result of the erase
//   the moment it finishes), the language, developer-only settings;
// - markers that something was deleted, so it isn't offered again (files Doddy made before the conversation was deleted;
//   recaps of conversations that were deleted);
// - the person's privacy choices: a switch that limits what Doddy shows, reads out, shares or sends keeps its position,
//   so erasing can never loosen a choice (Ask Doddy, Logbook counts and remembered conversations are on unless the
//   person turned them off; Face ID lock; widgets showing notes; Siri reading notes);
// - the switches that mirror a copy on Doddy's server (Memory on calls, notes and conversations kept on the server): left
//   on, the app's own sync makes the server copy as empty as the iPhone; turned off here, the copy would stay unreachable.

/// Why a key is kept.
public enum KeptReason: String, Sendable, CaseIterable {
    /// The signed-in Doddy account: how this iPhone uses each server for it. Erased with the account.
    case signIn
    /// An identifier that lets the copies of this iPhone on Doddy's servers (the voice provider, the backend) be found
    /// and deleted. Erased with the account.
    case serverTie
    /// "This install already cleared the Keychain items an earlier install left."
    case installMarker
    /// Which first-run screens were shown, and the Terms acceptance.
    case firstRunFlag
    /// The app's language.
    case displayLanguage
    /// An address or switch for development builds; a shipped build ignores it.
    case developerSetting
    /// Records that something was deleted, so it isn't offered or written again.
    case deletionMarker
    /// Whose data this iPhone holds (`LocalDataOwner`). Cleared by the app only after the whole erase was confirmed, so
    /// data left behind is never handed to the next account.
    case dataOwner
    /// A choice that limits what Doddy shows, reads out, shares or sends. Never reset to a looser default.
    case privacyChoice
    /// A switch that says Doddy's server keeps a copy; the sync then keeps the copy as empty as the iPhone. Erased with
    /// the account.
    case serverCopySwitch

    /// Whether the account's deletion ends the reason to keep it.
    var endsWithTheAccount: Bool {
        switch self {
        case .signIn, .serverTie, .serverCopySwitch: true
        case .installMarker, .firstRunFlag, .displayLanguage, .developerSetting, .deletionMarker, .dataOwner, .privacyChoice: false
        }
    }
}

public enum PreferenceRule: Equatable, Sendable {
    case erase
    case keep(KeptReason)
    /// iOS's own key in the app's domain (language lists, interface style): not Doddy's, neither erased nor counted.
    case ignore
}

public enum DevicePreferences {
    /// Keys kept on purpose.
    public static let keptKeys: [String: KeptReason] = [
        // Server ties.
        "deviceSession.expiresAt": .serverTie,
        "voiceUserID": .serverTie,
        // Install markers (`ServerKeychainStore`, `KeychainCredentialStore`, `AccountKeyStore`).
        "serverKeychainInstalled": .installMarker,
        "assistantKeychainInstalled": .installMarker,
        "accountKeysInstalled": .installMarker,
        // First-run flags and the Terms acceptance.
        "welcomeSeen": .firstRunFlag,
        "firstRunAccessSeen": .firstRunFlag,
        "legalAcceptance": .firstRunFlag,
        "quickStartOffered": .firstRunFlag,
        "hadFirstConversation": .firstRunFlag,
        // Language.
        "appLanguage": .displayLanguage,
        "appLanguage.polishDefaultApplied": .displayLanguage,
        // Development builds.
        "voiceTokenServer": .developerSetting,
        "connectedAppsServerURL": .developerSetting,
        "messagingServerURL": .developerSetting,
        "voiceAgentID": .developerSetting,
        "developer.directVoice": .developerSetting,
        "releaseScope.previewEverything": .developerSetting,
        "backTapSetupStatus": .developerSetting,
        // Deletion markers.
        "messages.conversationDeletedAt": .deletionMarker,
        "recaps.links.v1": .deletionMarker,
        // Whose data this iPhone holds.
        "localData.ownerAccountID": .dataOwner,
        // Privacy choices.
        "assistantConsent": .privacyChoice,
        "logbook.on": .privacyChoice,
        "rememberConversations": .privacyChoice,
        "siriReadsNotes": .privacyChoice,
        "widgetsShowContent": .privacyChoice,
        "privacy.appLock": .privacyChoice,
        "connections.pauseAll": .privacyChoice,
        // Switches that mirror a copy on Doddy's server.
        "memoryCopyOn": .serverCopySwitch,
        "webMemory.notes": .serverCopySwitch,
        "webMemory.conversations": .serverCopySwitch,
        "logbook.serverOn": .serverCopySwitch,
        "pushUpdatesOn": .serverCopySwitch,
        "textsToDoddyOn": .serverCopySwitch,
    ]

    /// Key families kept on purpose.
    public static let keptPrefixes: [String: KeptReason] = [
        "doddyAccount.": .signIn,
    ]

    /// The `PreferenceKey` values that are erased, on purpose. Not needed for the erase to work (every key not kept is
    /// erased); it is what makes a new `PreferenceKey` get a decision (see `isClassified`).
    public static let erasedKeys: Set<String> = [
        "showNoteTextInNotifications", "memoriesShowsLists", "notificationExplainerSeen", "appearance", "memorySort",
        "pinnedNotes", "hideCharacterArt", "savedIsland", "listenOnOpen", "watchShowContent",
        "backTapAction", "talkLaunchMode", "islandExpands", "backTapSetup", "openWaysOffer",
        "personality.humour", "personality.length", "personality.formality", "personality.mood", "personality.nickname",
        "voice.choice", "voice.speed", "voice.expressiveness", "voice.language",
        "shareProfileWithVoice", "learning.on", "learning.shareWithVoice",
        "paymentsEverEnabled", "paymentsAcknowledgedUnresolved", "paymentsLastUnresolved",
        "assistantUseNotes", "suggestSavesAfterConversation", "connectedConversations", "welcomeReplay",
        "deals.programsNotUsed", "deals.myShops", "deals.minimumSaving",
    ]

    /// True when somebody decided about this key: it is kept with a reason, or listed as erased.
    public static func isClassified(_ key: String) -> Bool {
        keptKeys[key] != nil || erasedKeys.contains(key) || keptPrefix(of: key) != nil
    }

    /// What to do with `key` now. Unknown keys are erased.
    public static func rule(for key: String, scope: DeviceErasureScope) -> PreferenceRule {
        if isSystemKey(key) { return .ignore }
        guard let reason = keptKeys[key] ?? keptPrefix(of: key) else { return .erase }
        if scope == .afterAccountDeleted, reason.endsWithTheAccount { return .erase }
        return .keep(reason)
    }

    private static func keptPrefix(of key: String) -> KeptReason? {
        keptPrefixes.first { key.hasPrefix($0.key) }?.value
    }

    /// Keys iOS and its frameworks put in the app's domain.
    private static let systemPrefixes = ["Apple", "NS", "com.apple.", "WebKit"]

    private static func isSystemKey(_ key: String) -> Bool {
        systemPrefixes.contains { key.hasPrefix($0) }
    }
}

public enum DefaultsErasure {
    /// Removes every key in `domain` that the rules say to erase and returns them. The app passes
    /// `UserDefaults.standard` and its bundle identifier; a test passes a suite and its name.
    @discardableResult
    public static func erase(_ defaults: UserDefaults, domain: String, scope: DeviceErasureScope) -> [String] {
        let keys = leftover(defaults, domain: domain, scope: scope)
        for key in keys { defaults.removeObject(forKey: key) }
        return keys
    }

    /// The keys that should be gone and are still there: the read-back. Empty means erased.
    public static func leftover(_ defaults: UserDefaults, domain: String, scope: DeviceErasureScope) -> [String] {
        (defaults.persistentDomain(forName: domain) ?? [:]).keys
            .filter { DevicePreferences.rule(for: $0, scope: scope) == .erase }
            .sorted()
    }

    /// What stays, with the reason, for the line that tells the person what was kept.
    public static func kept(_ defaults: UserDefaults, domain: String, scope: DeviceErasureScope) -> [String: KeptReason] {
        var kept: [String: KeptReason] = [:]
        for key in (defaults.persistentDomain(forName: domain) ?? [:]).keys {
            if case .keep(let reason) = DevicePreferences.rule(for: key, scope: scope) { kept[key] = reason }
        }
        return kept
    }
}
