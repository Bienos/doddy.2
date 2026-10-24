#if canImport(AlarmKit)
import AlarmKit
import AppIntents
import Foundation

// The buttons on a Doddy timer's Lock Screen card and Dynamic Island (ADR-612): Pause, Resume
// and Stop. They run in the app's process, like the other Live Activity buttons (ADR-131), and
// only ever touch the one timer they were drawn for, by its AlarmKit id. AlarmKit is the truth:
// the card changes when AlarmKit's state does, so a button that fails leaves the card as it was.

@available(iOS 26.0, *)
struct PauseDoddyTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause timer"
    static let isDiscoverable = false

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Timer") var alarmID: String

    init() { alarmID = "" }
    init(alarmID: UUID) { self.alarmID = alarmID.uuidString }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try AlarmManager.shared.pause(id: id) }
        return .result()
    }
}

@available(iOS 26.0, *)
struct ResumeDoddyTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume timer"
    static let isDiscoverable = false

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Timer") var alarmID: String

    init() { alarmID = "" }
    init(alarmID: UUID) { self.alarmID = alarmID.uuidString }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try AlarmManager.shared.resume(id: id) }
        return .result()
    }
}

/// Stop: ends the countdown (or the ringing) for good, as Stop in the Clock app does.
@available(iOS 26.0, *)
struct StopDoddyTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop timer"
    static let isDiscoverable = false

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Timer") var alarmID: String

    init() { alarmID = "" }
    init(alarmID: UUID) { self.alarmID = alarmID.uuidString }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        // Stop ends a ringing timer; a countdown that won't stop is cancelled instead.
        do { try AlarmManager.shared.stop(id: id) } catch { try AlarmManager.shared.cancel(id: id) }
        return .result()
    }
}
#endif
