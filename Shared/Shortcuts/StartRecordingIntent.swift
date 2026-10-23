import AppIntents
import DoddyCore
import Foundation

/// What a start intent shows when the recording did not start (Shortcuts or the control shows the
/// sentence). The words come from `CaptureFailure`, so they say what is true.
struct CaptureIntentProblem: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }
}

/// "Start DODDY Recording" (ADR-579): Siri, Shortcuts, and the Action Button through a shortcut.
/// Works on iOS 17 too, which is why it is a plain App Intent.
///
/// It OPENS Doddy. iOS does not let a recording begin from a cold background: developers report
/// "Live Activity start failed … Target is not foreground" when an intent starts both (Apple
/// forums, thread 815725, not yet confirmed on a device here). With Doddy on screen the start is
/// an ordinary foreground start; the recording then carries on in the background and with the
/// screen locked. Whether this can be made to start with no screen at all is an open experiment
/// for a device (docs/implementation/CAPTURE_STATUS.md): flip `openAppWhenRun` and read the Console.
///
/// It answers "Recording." only after `RecordingCoordinator.start` has seen the recorder deliver
/// audio. Compiled into the app and the widget extension (the control needs the type); only the
/// app's copy does anything.
struct StartDoddyRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start DODDY Recording"
    static var description: IntentDescription {
        IntentDescription("Starts recording a meeting or conversation. Doddy opens first; the recording then carries on in the Dynamic Island and with the screen locked. The audio stays on this iPhone.")
    }
    static let openAppWhenRun = true
    /// A recording of other people, started from a locked iPhone, would be a recording nobody saw begin.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if !DODDY_WIDGET_EXTENSION
        switch await RecordingCoordinator.shared.start(origin: .intent) {
        case .started:
            return .result(dialog: "\(CapturePresentation.startedLine(.current))")
        case .rejected(let rejection):
            return .result(dialog: "\(rejection.message(.current))")
        case .failed(let failure):
            throw CaptureIntentProblem(message: failure.message(.current))
        }
        #else
        return .result(dialog: "")
        #endif
    }
}

/// The same start, as an `AudioRecordingIntent` (iOS 18 and later) for the control and the Action
/// Button: it tells iOS that this intent records audio, so iOS shows its recording indicator, and it
/// requires the Live Activity that `RecordingCoordinator` starts before it says "recording".
/// Not an App Shortcut, because the App Shortcuts list can't hold an iOS 18 intent in an app that
/// still runs on iOS 17 (see `TalkInIslandIntent`); `StartDoddyRecordingIntent` is the Siri one.
@available(iOS 18.0, *)
struct RecordWithDoddyIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Record with DODDY"
    static var description: IntentDescription {
        IntentDescription("Opens Doddy and starts recording. The recording carries on in the Dynamic Island. The audio stays on this iPhone.")
    }
    static let isDiscoverable = false
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !DODDY_WIDGET_EXTENSION
        switch await RecordingCoordinator.shared.start(origin: .control) {
        case .started, .rejected:
            break
        case .failed(let failure):
            throw CaptureIntentProblem(message: failure.message(.current))
        }
        #endif
        return .result()
    }
}

/// "Open Latest Recording": the newest recording's page. Navigation only.
struct OpenLatestRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Latest Recording"
    static var description: IntentDescription {
        IntentDescription("Opens the newest recording in Doddy.")
    }
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !DODDY_WIDGET_EXTENSION
        await ShortcutRouter.shared.openLatestRecording()
        #endif
        return .result()
    }
}
