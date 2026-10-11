import Foundation

/// What the Doddy menu-bar menu on the Mac offers, and which rows work (ADR-450).
///
/// The menu is decided here, not in the views, so "nothing is shown as working unless it is" can be
/// tested on any machine with Swift. A row is `available` only when the code behind it exists on
/// the Mac: Talk and Translate are not built there, so they say so instead of looking tappable.
public enum MenuBarAction: String, CaseIterable, Sendable {
    case openDoddy, talk, remember, find, translate, settings
}

public enum MenuBarAvailability: Equatable, Sendable {
    case available
    /// Shown greyed out with this plain-language reason underneath.
    case unavailable(reason: String)

    public var isAvailable: Bool { self == .available }
}

public struct MenuBarEntry: Equatable, Sendable, Identifiable {
    public let action: MenuBarAction
    public let title: String
    public let availability: MenuBarAvailability

    public var id: MenuBarAction { action }
}

/// The line under "Doddy" at the top of the menu. There is no "Listening…" state: the Mac app
/// has no microphone access and never listens.
public enum MenuBarStatus: Equatable, Sendable {
    case ready
    /// The memory store could not be opened. Nothing was deleted or reset.
    case memoryUnavailable

    public var text: String {
        switch self {
        case .ready: "Ready. Not listening."
        case .memoryUnavailable: "Can't open its memory store."
        }
    }
}

public struct MenuBarMenu: Equatable, Sendable {
    public let status: MenuBarStatus
    public let entries: [MenuBarEntry]

    /// `memoryIsOpen`: the Mac's SQLite memory file opened. Remember and Find need it.
    public init(memoryIsOpen: Bool) {
        status = memoryIsOpen ? .ready : .memoryUnavailable
        let memoryNeeded: MenuBarAvailability = memoryIsOpen
            ? .available : .unavailable(reason: "Doddy's memory store isn't open on this Mac.")
        entries = MenuBarAction.allCases.map { action in
            switch action {
            case .openDoddy:
                MenuBarEntry(action: action, title: "Open Doddy", availability: .available)
            case .talk:
                MenuBarEntry(
                    action: action, title: "Talk to Doddy",
                    availability: .unavailable(reason: "Voice isn't on the Mac yet. Use Doddy on your iPhone."))
            case .remember:
                MenuBarEntry(action: action, title: "Remember something", availability: memoryNeeded)
            case .find:
                MenuBarEntry(action: action, title: "Find in my memories", availability: memoryNeeded)
            case .translate:
                MenuBarEntry(
                    action: action, title: "Translate",
                    availability: .unavailable(reason: "Translate isn't on the Mac yet. Use Doddy on your iPhone."))
            case .settings:
                MenuBarEntry(action: action, title: "Settings", availability: .available)
            }
        }
    }

    public func entry(_ action: MenuBarAction) -> MenuBarEntry {
        entries.first { $0.action == action }!
    }
}

/// The outcome of "Remember something" in the menu. `saved` only follows a repository save that
/// returned a committed record, so the confirmation is never shown for a write that didn't happen.
public enum MenuBarSaveResult: Equatable, Sendable {
    case saved(MemoryRecord)
    case rejected(MemoryValidationError)
    /// The write threw. Nothing is shown as saved.
    case notSaved(message: String)
}

public enum MenuBarCapture {
    /// Saves `text` as an explicit text note (the user typed it and pressed Save) and verifies it.
    public static func save(
        _ text: String, to repository: any MemoryRepository, at date: Date = Date()
    ) async -> MenuBarSaveResult {
        let draft: NewMemory
        do {
            draft = try NewMemory(text: text, category: .other, source: .explicitText, capturedAt: date)
        } catch {
            return .rejected(error)
        }
        do {
            // `MemoryRepository.save` returns only a committed, read-back record (Ports.swift).
            return .saved(try await repository.save(draft))
        } catch {
            return .notSaved(message: "Doddy couldn't save the note. Nothing was marked as saved.")
        }
    }
}
