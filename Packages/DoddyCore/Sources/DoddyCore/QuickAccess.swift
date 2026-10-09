import Foundation

/// Text the App Intents ("Save to Doddy", "Ask Doddy") give back to Siri and Shortcuts.
/// Same rule as voice: only stored text, never a guessed answer.
public enum ShortcutReply {
    public static func saved(_ record: MemoryRecord) -> String {
        "Saved on this iPhone: “\(record.currentText)”"
    }

    public static func ask(_ outcome: RecallOutcome, limit: Int = 3) -> String {
        guard case .matches(let candidates) = outcome, !candidates.isEmpty else {
            return RecallCopy.noMatch
        }
        let shown = candidates.prefix(limit)
        var lines = [candidates.count == 1 ? "I found 1 saved note:" : "I found \(candidates.count) saved notes:"]
        lines += shown.map { "“\($0.record.currentText)”" }
        if candidates.count > shown.count {
            lines.append("…and \(candidates.count - shown.count) more. Open Doddy to see them all.")
        }
        return lines.joined(separator: "\n")
    }
}

/// One card of the guided Back Tap setup. Doddy cannot open these Settings pages or see
/// which one the user is on: the guide follows what the user reports.
public struct QuickAccessStep: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let route: String
    public let instruction: String
    /// What the user taps to tell Doddy where they are.
    public let report: String
}

public enum BackTapGuide {
    /// Name of the user's personal shortcut. Back Tap lists only shortcuts in the user's own
    /// library, so the App Shortcut has to be added there once.
    public static let shortcutName = "Talk to Doddy"

    public static let makeShortcut = QuickAccessStep(
        id: "shortcut",
        title: "Make the shortcut",
        route: "Shortcuts app",
        instruction: "Open Shortcuts and tap +. Search for Doddy, add Talk to Doddy, then tap Done. Back Tap can only use shortcuts from your own list.",
        report: "I made the shortcut")

    /// Copy follows the v1.2 setup prototype (`design/interface-v1.2/setup.js`).
    public static let settingsSteps: [QuickAccessStep] = [
        QuickAccessStep(
            id: "settings", title: "Open Settings", route: "Settings",
            instruction: "Open the Settings app. On its main list, choose Accessibility.",
            report: "I'm in Settings"),
        QuickAccessStep(
            id: "accessibility", title: "Choose Touch", route: "Settings → Accessibility",
            instruction: "In Accessibility, find the Physical and Motor section, then choose Touch.",
            report: "I'm in Accessibility"),
        QuickAccessStep(
            id: "touch", title: "Find Back Tap", route: "Settings → Accessibility → Touch",
            instruction: "Scroll down in Touch and choose Back Tap.",
            report: "I'm in Touch"),
        QuickAccessStep(
            id: "back-tap", title: "Choose Double Tap", route: "Settings → Accessibility → Touch → Back Tap",
            instruction: "Choose Double Tap. If it already has an action you want to keep, you can leave setup for later.",
            report: "I'm in Back Tap"),
        QuickAccessStep(
            id: "double-tap", title: "Choose \(shortcutName)", route: "Back Tap → Double Tap",
            instruction: "Scroll to the Shortcuts section and choose \(shortcutName). Then come back to Doddy for the tap test.",
            report: "I'm in Double Tap"),
    ]
}

/// The tap test. A shortcut arriving proves only that a shortcut reached Doddy; that it was
/// Double Back Tap is the user's own report. Nothing here claims iOS verified the setting.
public struct ShortcutTest: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case waiting
        case received(at: Date)
        case confirmedBackTap(at: Date)
    }

    public private(set) var phase: Phase = .idle

    public init() {}

    public var isWaiting: Bool { phase == .waiting }

    public mutating func start() { phase = .waiting }

    /// Returns true when the shortcut was taken by the test (so no conversation should start).
    @discardableResult
    public mutating func receiveShortcut(at date: Date) -> Bool {
        guard phase == .waiting else { return false }
        phase = .received(at: date)
        return true
    }

    /// The user says the shortcut came from Double Back Tap. Only valid after one arrived.
    public mutating func confirmBackTap() {
        guard case .received(let date) = phase else { return }
        phase = .confirmedBackTap(at: date)
    }

    /// Ran another way (Siri, the Shortcuts app…): Back Tap stays unconfirmed.
    public mutating func reset() { phase = .idle }
}

public enum QuickAccessStatus {
    /// `testedAt` is set only after the tap test received a shortcut and the user confirmed it was Back Tap.
    public static func backTap(testedAt: Date?) -> String {
        guard let testedAt else { return "Not tested" }
        return "Tested by you · \(testedAt.formatted(date: .abbreviated, time: .omitted))"
    }
}
