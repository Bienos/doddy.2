import AppIntents
import Foundation
import Observation

/// The "Open Doddy" action in the Shortcuts app. It only opens Doddy; the user puts it in a
/// personal shortcut and picks that shortcut for Back Tap in Settings.
struct OpenDoddyIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Doddy"
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        OpenDoddyReceipts.shared.record()
        return .result()
    }
}

/// When the Open Doddy action last ran in this app session. Kept in memory only. It shows the
/// shortcut reached Doddy; it can't show whether a double tap started it.
@MainActor
@Observable
final class OpenDoddyReceipts {
    static let shared = OpenDoddyReceipts()

    private(set) var lastReceivedAt: Date?

    func record(at date: Date = .now) {
        lastReceivedAt = date
    }
}
