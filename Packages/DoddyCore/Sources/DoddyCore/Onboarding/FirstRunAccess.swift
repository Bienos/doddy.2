import Foundation

// The first-run "Allow access" step (ADR-814): one screen after "Before we start" that asks iOS for the
// permissions Doddy uses, so the person is not interrupted by them later. Pure rules only (no UI, no
// strings, no iOS calls), so they are tested on Linux. The screen is `DoddyApp/Features/Onboarding`.
//
// Honest by construction: asking is not getting. iOS asks each question once and the person may say no;
// nothing here turns a feature on unless iOS said yes.

/// One thing the step can ask for, in the order the questions come.
public enum FirstRunAccessItem: String, CaseIterable, Sendable, Identifiable {
    case microphone, notifications, contacts, calendar, reminders, location, motion, photos, camera

    public var id: String { rawValue }

    /// The Settings › Connections switch that goes on once iOS says yes (`ConnectionController.setOn` asks
    /// iOS and stores the switch only if it allowed), if the item has one. The
    /// microphone and location have none: the microphone is asked by iOS when a conversation starts, and
    /// location has its own "Use where I am" button on a place reminder.
    public var connection: VoiceConnection? {
        switch self {
        case .microphone, .location: nil
        // Timers and note reminders both ring through notifications.
        case .notifications: .timers
        case .contacts: .contacts
        case .calendar: .calendar
        case .reminders: .reminders
        case .motion: .steps
        case .photos: .photos
        case .camera: .camera
        }
    }

    /// Asked with all the others when the person taps Allow. Every item is on the list; the person
    /// can untick any of them.
    public var tickedAtStart: Bool { true }
}

/// What came back for one item. `.allowed` and `.refused` are iOS's answer, including one given earlier:
/// iOS shows its question only once, so a "no" can only be changed in iPhone Settings.
public enum FirstRunAccessOutcome: Equatable, Sendable {
    case allowed
    case refused
    /// Not asked: the person unticked it, or the iPhone can't (no camera, location services off).
    case skipped
}

public enum FirstRunAccessRule {
    /// Whether the step shows. One rule, so it is tested.
    /// - Parameters:
    ///   - seen: the person has been through it (or skipped it) on this installation.
    ///   - firstInstallation: a genuinely new installation (`ProfileStore.isFirstInstallation`). Someone
    ///     updating from an older version is not asked for everything at once.
    ///   - override: a UI-test launch argument: `-firstRunAccess YES` shows it until it has been answered
    ///     (so a test can get past it), `NO` never shows it.
    public static func shouldShow(seen: Bool, firstInstallation: Bool, override: Bool?) -> Bool {
        if let override { return override && !seen }
        return firstInstallation && !seen
    }

    /// The items to ask about, in order, from what the person left ticked.
    public static func itemsToAsk(ticked: Set<FirstRunAccessItem>) -> [FirstRunAccessItem] {
        FirstRunAccessItem.allCases.filter(ticked.contains)
    }

    /// How many were allowed and how many were refused, for the line under the button. Skipped ones count
    /// in neither.
    public static func summary(_ outcomes: [FirstRunAccessItem: FirstRunAccessOutcome]) -> (allowed: Int, refused: Int) {
        (outcomes.values.filter { $0 == .allowed }.count, outcomes.values.filter { $0 == .refused }.count)
    }
}
