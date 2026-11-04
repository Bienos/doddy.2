import Foundation

// The optional Face ID lock (ADR-310) covers the whole app. A cover drawn inside the app's own
// view cannot stop a shortcut, a link, a notification or a sheet from reaching what is under it,
// so every way in asks this policy first (ADR-723). The rules are here, tested on Linux; the
// iPhone app asks them through `AppLock` and holds the requests (`ShortcutRouter`).
//
// With the lock off nothing here changes anything: `allows` is true for every entry, no request
// is held and no cover is shown.

/// Every way into Doddy that shows saved notes, or starts something that uses them, or opens a
/// screen over the Face ID cover. The policy decides each one separately, and `AppLockPolicy`
/// switches over this enum without a default, so a new way in cannot be added without deciding.
public enum AppLockEntry: String, CaseIterable, Sendable {
    /// A voice conversation, which is given the saved notes: Back Tap, the Action Button, Siri, the
    /// icon's menu, "Start listening when I open Doddy", "Ask me about it", the translator and
    /// "Talk it through" on the check-in.
    case startConversation
    /// A capture screen (New note, Save to Doddy). It opens with the newest unfinished note.
    case openCapture
    /// Find in Doddy.
    case openFind
    /// A screen built from the saved notes: the morning check-in, the tidy-up, the wrap-up, the
    /// look-back and the weekly plan.
    case openNoteSheet
    /// The "ways to open Doddy" sheet. It shows no note, but it changes settings.
    case openWays
    /// Recordings, and "Open Latest Recording".
    case openRecordings
    /// The saved parking spot, opened in Maps.
    case openParking
    /// Siri reading a saved note aloud.
    case readNotesAloud
    /// Siri or Shortcuts reading a list aloud ("What's on my shopping list in Doddy?").
    case readListAloud
    /// Siri or Shortcuts adding to a list or ticking an item on it. It answers with what it did, so it
    /// shows the list's words too.
    case changeList
    /// Bringing forward a conversation that runs without a screen (Talk in the Island).
    case showRunningConversation
}

/// What happens to a request that arrives while Doddy is locked.
public enum AppLockDeferral: Equatable, Sendable {
    /// Kept for a short while and carried out once the person has unlocked Doddy.
    case afterUnlock
    /// Not carried out. The caller says that Doddy is locked where it can.
    case drop
}

public enum AppLockPolicy {
    /// True when `entry` may go ahead now. Locked, nothing that shows notes or opens a screen may.
    public static func allows(_ entry: AppLockEntry, isLocked: Bool) -> Bool {
        guard isLocked else { return true }
        switch entry {
        case .startConversation, .openCapture, .openFind, .openNoteSheet, .openWays, .openRecordings,
             .openParking, .readNotesAloud, .readListAloud, .changeList, .showRunningConversation:
            return false
        }
    }

    /// What to do with `entry` when `allows` said no.
    public static func whenLocked(_ entry: AppLockEntry) -> AppLockDeferral {
        switch entry {
        case .startConversation, .openCapture, .openFind, .openNoteSheet, .openWays, .openRecordings, .openParking:
            // The person asked to open Doddy, and Face ID is the next thing they see.
            return .afterUnlock
        case .readNotesAloud, .readListAloud, .changeList:
            // Siri is waiting for an answer and cannot wait for a face.
            return .drop
        case .showRunningConversation:
            // The app brings it forward itself when the unlock has happened (ADR-577).
            return .drop
        }
    }

    /// What Siri says for a request that needs the notes or the lists while Doddy is locked. Plain
    /// English like the other answers in `SiriReadback`.
    public static let lockedAnswer = "Doddy is locked. Open Doddy and unlock him."

    /// True when an opaque cover should hide Doddy's screen from the app switcher (ADR-723): the
    /// Face ID lock is on and the scene is not in front. With the lock off there is never a cover.
    public static func coverShown(lockOn: Bool, sceneIsActive: Bool) -> Bool {
        lockOn && !sceneIsActive
    }
}

/// Requests that arrived while Doddy was locked, kept to be carried out after the unlock (ADR-723).
/// Generic so the app can keep a closure and the tests a string. It lives in one main-actor owner, so it is not `Sendable`.
///
/// A request waits at most `lifetime` seconds, so a conversation asked for minutes ago does not start
/// by itself when the person unlocks later for another reason. A second request for the same entry
/// replaces the first; when more than `capacity` wait, the oldest goes.
public struct AppLockHold<Action> {
    public static var lifetime: TimeInterval { 120 }
    public static var capacity: Int { 4 }

    private struct Held {
        let entry: AppLockEntry
        let action: Action
        let heldAt: Date
    }

    private var held: [Held] = []

    public init() {}

    public var isEmpty: Bool { held.isEmpty }
    public var entries: [AppLockEntry] { held.map(\.entry) }

    public mutating func hold(_ action: Action, for entry: AppLockEntry, at now: Date) {
        held.removeAll { $0.entry == entry }
        held.append(Held(entry: entry, action: action, heldAt: now))
        if held.count > Self.capacity { held.removeFirst(held.count - Self.capacity) }
    }

    /// The requests that are still fresh, oldest first. The hold is empty afterwards.
    public mutating func release(at now: Date) -> [Action] {
        defer { held = [] }
        return held.filter { now.timeIntervalSince($0.heldAt) <= Self.lifetime }.map(\.action)
    }

    /// Forgets everything (for example when the lock is switched off).
    public mutating func clear() { held = [] }
}
