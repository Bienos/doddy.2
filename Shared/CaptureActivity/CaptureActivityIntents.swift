import ActivityKit
import AppIntents
import Foundation
import os

/// Lets the Live Activity's buttons reach the running recording (ADR-579). These intents run in
/// the app's process, where `RecordingCoordinator` registers these handlers. The widget extension
/// has its own, separate copy of this object whose handlers stay nil, so an intent performed there
/// does nothing; every intent therefore pins `allowedExecutionTargets` to `.main` (ADR-131).
@MainActor
final class CaptureActivityActions {
    static let shared = CaptureActivityActions()

    var stop: (@MainActor () async -> Void)?
    var pause: (@MainActor () async -> Void)?
    var resume: (@MainActor () async -> Void)?
}

/// Which process performed a button, for the Console: subsystem `com.bienos.doddy2`, category
/// `capture`. Only the process and whether a handler was there; nothing from the recording.
enum CaptureIntentLog {
    static func performed(_ intent: String, handled: Bool) {
        let process = Bundle.main.bundleIdentifier ?? "unknown"
        Logger(subsystem: "com.bienos.doddy2", category: "capture")
            .info("\(intent, privacy: .public) performed in \(process, privacy: .public); recording handler: \(handled ? "yes" : "no", privacy: .public)")
    }
}

/// "Stop" on the island and the Lock Screen, and in Shortcuts. Always available while a recording
/// exists: a recording must always be stoppable.
struct StopDoddyRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop DODDY Recording"
    static var description: IntentDescription {
        IntentDescription("Stops the recording and saves it in Recordings.")
    }

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let handler = CaptureActivityActions.shared.stop
        await handler?()
        #if !DODDY_WIDGET_EXTENSION
        // A recording's activity with nothing behind it (iOS ended the app in the background) must
        // still go away, or the island would keep saying Doddy records when nothing does.
        if handler == nil {
            for activity in Activity<DoddyCaptureAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
        CaptureIntentLog.performed("Stop", handled: handler != nil)
        return .result()
    }
}

/// "Pause" on the island and the Lock Screen. Pause closes the audio file and turns the microphone
/// off; it is not a muted microphone.
struct PauseDoddyRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause DODDY Recording"
    static var description: IntentDescription {
        IntentDescription("Pauses the recording. The microphone is off until you resume.")
    }

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let handler = CaptureActivityActions.shared.pause
        await handler?()
        CaptureIntentLog.performed("Pause", handled: handler != nil)
        return .result()
    }
}

/// "Resume" on the island and the Lock Screen. iOS may refuse a recording that starts again while
/// Doddy is in the background; then the island says to open Doddy, and it never says "recording"
/// unless the recorder reported audio coming in.
struct ResumeDoddyRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume DODDY Recording"
    static var description: IntentDescription {
        IntentDescription("Carries on a paused or interrupted recording.")
    }

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let handler = CaptureActivityActions.shared.resume
        await handler?()
        CaptureIntentLog.performed("Resume", handled: handler != nil)
        return .result()
    }
}
