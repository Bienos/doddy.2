import DoddyCore
import Foundation

/// Where the Terms acceptance (ADR-581) is kept: a JSON `LegalAcceptanceRecord` in the app's
/// UserDefaults, next to the other settings. Doddy has no account you must have, so there is no
/// server copy yet; deleting the app deletes the record, and a new install asks again. When
/// Doddy gets accounts that need it, the same record goes to the server (ADR-581, "Later").
enum LegalAcceptanceStore {
    static var record: LegalAcceptanceRecord? {
        LegalAcceptance.decode(UserDefaults.standard.data(forKey: LegalAcceptance.preferenceKey))
    }

    /// Whether the "Before we start" step must be shown.
    static var isNeeded: Bool {
        isNeeded(UserDefaults.standard.data(forKey: LegalAcceptance.preferenceKey))
    }

    /// The same, for the stored data a view already observes (`@AppStorage`).
    static func isNeeded(_ data: Data?) -> Bool {
        #if DEBUG
        // UI tests start past it, unless a test is about it (`UITestLaunch`).
        if UserDefaults.standard.bool(forKey: "legalAcceptanceSkippedForUITests") { return false }
        #endif
        return LegalAcceptance.isNeeded(LegalAcceptance.decode(data))
    }

    /// Stores an explicit tap on Accept and reads it back. Returns false if it didn't stick, so
    /// the step stays (nothing is claimed accepted without the stored record).
    @discardableResult
    static func accept(source: LegalAcceptanceRecord.Source, at date: Date = .now) -> Bool {
        let record = LegalAcceptance.accept(at: date, source: source)
        guard let data = LegalAcceptance.encode(record) else { return false }
        UserDefaults.standard.set(data, forKey: LegalAcceptance.preferenceKey)
        return Self.record == record
    }
}
