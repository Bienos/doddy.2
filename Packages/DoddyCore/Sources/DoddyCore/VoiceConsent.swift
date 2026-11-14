import Foundation

// Before the first voice conversation the person is to agree that voice conversations are kept until they delete them,
// and that deleting the account deletes them (owner, 13 Nov 2026, decision 2026-11-12-voice-conversations-per-account).
// The words of that agreement are the owner's and a lawyer's (`docs/legal/PRIVACY_POLICY_DRAFT.md`), and they don't
// exist yet. So only the mechanism is here, and it is off: with no version of the words (`requiredVersion` is nil) there
// is nothing to ask and `requirement` says `notRequired`. Nothing in the app calls it yet, and no screen changes.

public enum VoiceConsent {
    public enum State: Equatable, Sendable {
        case notGiven
        /// The yes was given to the words of this version (1 or more).
        case given(version: Int)
    }

    /// The version of the words the person has to have agreed to. nil until the words exist: set it to 1 with them,
    /// and raise it whenever they change, so everyone is asked again.
    public static let requiredVersion: Int? = nil

    public enum Requirement: Equatable, Sendable {
        /// There are no words to agree to yet. Nothing is asked and nothing is blocked.
        case notRequired
        /// The person has agreed to the current words.
        case satisfied
        /// The person has to be asked before the conversation starts.
        case needed

        public var blocksStart: Bool { self == .needed }
    }

    public static func requirement(state: State, requiredVersion: Int? = VoiceConsent.requiredVersion) -> Requirement {
        guard let requiredVersion else { return .notRequired }
        if case .given(let version) = state, version >= requiredVersion { return .satisfied }
        return .needed
    }

    /// A stored version as a state: zero or less is "not given".
    public static func state(storedVersion: Int) -> State {
        storedVersion >= 1 ? .given(version: storedVersion) : .notGiven
    }

    // MARK: Kept on this iPhone

    /// Its own key, not the voice data notice's (`voice.providerConsent.elevenlabs.v1`), which means something else.
    public static let preferenceKey = "voice.conversationsKeptConsentVersion"

    public static func stored(in defaults: UserDefaults = .standard) -> State {
        state(storedVersion: defaults.integer(forKey: preferenceKey))
    }

    /// Records a yes to the words of `version`. A version below 1 is no yes, and an older yes never replaces a newer one.
    public static func record(version: Int, in defaults: UserDefaults = .standard) {
        guard version >= 1, version > defaults.integer(forKey: preferenceKey) else { return }
        defaults.set(version, forKey: preferenceKey)
    }

    /// The agreement is withdrawn (the account is deleted): the next account is asked again.
    public static func withdraw(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: preferenceKey)
    }
}
