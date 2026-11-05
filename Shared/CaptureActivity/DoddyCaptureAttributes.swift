import ActivityKit
import DoddyCore
import Foundation

/// The Live Activity (Dynamic Island and Lock Screen) for a DODDY Capture recording (ADR-588).
/// Compiled into the app, which starts, updates and ends it, and into the DoddyWidgets extension,
/// which draws it. Its content is `CaptureActivitySnapshot` (DoddyCore): phases, numbers and an
/// interruption kind. Never a word from the recording: the Lock Screen is visible to anyone.
struct DoddyCaptureAttributes: ActivityAttributes {
    typealias ContentState = CaptureActivitySnapshot

    /// Which recording this is, so a leftover activity can be told from the current one.
    var recordingID: UUID
    var startedAt: Date
}
