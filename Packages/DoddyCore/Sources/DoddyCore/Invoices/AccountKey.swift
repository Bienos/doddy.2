import Foundation

// A key the person pastes in for their own account (ADR-633): today the inFakt API key. The key is
// theirs and stays on their iPhone, in the Keychain (DoddyApp/Infrastructure/AccountKeyStore.swift);
// it is never put in the repository, in preferences or in a message to Doddy's server. Only the
// checks live here, so they are tested on Linux.
//
// The format of an inFakt key is not documented anywhere I could read (INFAKT_STATUS.md), so the
// check is about what is safe, not about what is right: printable ASCII with no spaces, so the value
// can go into one HTTP header and nothing else, and never a line break inside it (a pasted key with
// a second line would otherwise become a second header). A key that passes this may still be wrong;
// only inFakt can say that.
//
// Platforms: iPhone and iPad.

public struct AccountKey: Equatable, Sendable {
    public static let minLength = 10
    public static let maxLength = 200

    public let value: String

    /// What a copy from a web page or a message leaves around a key: spaces, line breaks and the
    /// invisible characters (zero-width space, joiner, word joiner, byte-order mark, no-break space).
    /// Listed here rather than left to Foundation, whose idea of whitespace differs between platforms.
    private static let pasteDust = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}\u{00A0}"))

    /// Paste dust around a key is dropped; anything else odd, inside or outside, refuses the key.
    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: Self.pasteDust)
        guard (Self.minLength...Self.maxLength).contains(trimmed.count),
              trimmed.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else { return nil }
        value = trimmed
    }

    /// What Settings shows once the key is saved: the key is never shown again. The last four
    /// characters tell two keys apart; a short key shows none of itself.
    public var masked: String {
        value.count >= 12 ? "••••" + String(value.suffix(4)) : "••••"
    }
}

/// Where one key is kept: the Keychain in the app, a fake in tests.
public protocol AccountKeyStoring: Sendable {
    /// nil when no key is held (or what is held no longer passes `AccountKey`).
    func read() throws -> AccountKey?
    func save(_ key: AccountKey) throws
    func remove() throws
}

public enum AccountKeyOutcome: Equatable, Sendable {
    case saved(masked: String)
    /// What was pasted is not something that can be a key. Nothing was stored.
    case notAKey
    /// The store refused, or did not hold the key when asked afterwards.
    case couldNotSave
    case removed
    case couldNotRemove
}

/// Saves and removes a key and says so only after asking the store again (constitution: never claim
/// something was saved or forgotten without a verified storage operation).
public struct AccountKeyManager: Sendable {
    private let store: any AccountKeyStoring

    public init(store: any AccountKeyStoring) { self.store = store }

    /// What Settings shows. A store that cannot be read is `.unavailable`, never "no key".
    public func state() -> AccountKeyState {
        do {
            guard let key = try store.read() else { return .none }
            return .saved(masked: key.masked)
        } catch {
            return .unavailable
        }
    }

    /// `.saved` only if reading the store afterwards returns exactly what was pasted.
    public func save(pasted: String) -> AccountKeyOutcome {
        guard let key = AccountKey(pasted) else { return .notAKey }
        do {
            try store.save(key)
            guard try store.read() == key else { return .couldNotSave }
            return .saved(masked: key.masked)
        } catch {
            return .couldNotSave
        }
    }

    /// `.removed` only if reading the store afterwards finds nothing.
    public func remove() -> AccountKeyOutcome {
        do {
            try store.remove()
            return try store.read() == nil ? .removed : .couldNotRemove
        } catch {
            return .couldNotRemove
        }
    }
}

/// What Settings knows about a saved key, with no key in it.
public enum AccountKeyState: Equatable, Sendable {
    case none
    case saved(masked: String)
    /// The Keychain refused to read or write; said as it is, never as "no key".
    case unavailable

    public var isSaved: Bool {
        if case .saved = self { return true }
        return false
    }
}
