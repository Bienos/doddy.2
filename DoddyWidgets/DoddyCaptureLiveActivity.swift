import ActivityKit
import AppIntents
import DoddyCore
import SwiftUI
import WidgetKit

/// Dynamic Island and Lock Screen for a DODDY Capture recording (ADR-579). Restrained on purpose:
/// a small orange dot and the running time, no waveform, no banner. The dot is orange only while
/// audio is being captured; paused, interrupted and saving are grey. Stop, and Pause or Resume,
/// are always one tap away, and the island opens Doddy.
///
/// Nothing from the recording appears here: the content is `CaptureActivitySnapshot`, phases and
/// numbers only, because the Lock Screen is visible to anyone.
///
/// NOT COMPILED OR RUN: written without Xcode (docs/implementation/CAPTURE_STATUS.md).
struct DoddyCaptureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DoddyCaptureAttributes.self) { context in
            CaptureLockScreenView(snapshot: context.state, isStale: context.isStale)
                .doddyCreamLockScreen()
        } dynamicIsland: { context in
            let snapshot = context.state
            let language = NotificationLanguage.current
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: language == .polish ? "DODDY nagrywa" : "DODDY is recording")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.islandCream)
                        Text(verbatim: CapturePresentation.status(snapshot, language))
                            .font(.system(size: 12))
                            .foregroundStyle(CapturePresentation.isRecordingCue(snapshot) ? Color.islandOrange : Color.islandSecondary)
                    }
                    .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CaptureElapsed(snapshot: snapshot)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.islandCream)
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        if let detail = CapturePresentation.detail(snapshot, language) {
                            Text(verbatim: detail)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.islandSecondary)
                                .multilineTextAlignment(.center)
                        }
                        CaptureControls(snapshot: snapshot, language: language)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                CaptureDot(snapshot: snapshot)
            } compactTrailing: {
                CaptureElapsed(snapshot: snapshot)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.islandCream)
                    .frame(maxWidth: 52)
                    .minimumScaleFactor(0.7)
            } minimal: {
                CaptureDot(snapshot: snapshot)
            }
            .keylineTint(CapturePresentation.isRecordingCue(snapshot) ? Color.islandOrange : Color.islandSecondary)
        }
    }
}

/// The recording cue: orange while audio is captured, grey when it is not. Never decorative.
private struct CaptureDot: View {
    let snapshot: CaptureActivitySnapshot

    var body: some View {
        if CapturePresentation.isRecordingCue(snapshot) {
            Circle().fill(Color.islandOrange).frame(width: 9, height: 9)
                .accessibilityLabel(NotificationLanguage.current == .polish ? "Nagrywanie" : "Recording")
        } else {
            Image(systemName: CapturePresentation.symbol(snapshot))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.islandSecondary)
                .accessibilityLabel(CapturePresentation.status(snapshot, .current))
        }
    }
}

/// The time recorded. The system runs it from a start date, so nothing updates it: while paused it
/// stands still, and it counts audio, not the time since the button was pressed.
private struct CaptureElapsed: View {
    let snapshot: CaptureActivitySnapshot

    var body: some View {
        if let start = CapturePresentation.timerStart(snapshot) {
            Text(timerInterval: start...Date.distantFuture, countsDown: false).monospacedDigit()
        } else {
            Text(verbatim: RecordingClock.string(milliseconds: snapshot.capturedMilliseconds)).monospacedDigit()
        }
    }
}

/// Pause or Resume, Stop, and Open Doddy. A recording can always be stopped from here.
private struct CaptureControls: View {
    let snapshot: CaptureActivitySnapshot
    let language: NotificationLanguage

    var body: some View {
        HStack(spacing: 6) {
            if CapturePresentation.canPause(snapshot) {
                Button(intent: PauseDoddyRecordingIntent()) {
                    IslandPillLabel(title: CapturePresentation.label(.pause, language), systemImage: "pause.fill")
                }
            }
            if CapturePresentation.canResume(snapshot) {
                Button(intent: ResumeDoddyRecordingIntent()) {
                    IslandPillLabel(title: CapturePresentation.label(.resume, language), systemImage: "play.fill", prominent: true)
                }
            }
            if CapturePresentation.canStop(snapshot) {
                Button(intent: StopDoddyRecordingIntent()) {
                    IslandPillLabel(title: CapturePresentation.label(.stop, language), systemImage: "stop.fill",
                                    prominent: !CapturePresentation.canResume(snapshot))
                }
            }
            Link(destination: DeepLink.recordings.url) {
                IslandPillLabel(title: CapturePresentation.label(.open, language), systemImage: "arrow.up.forward")
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CaptureLockScreenView: View {
    let snapshot: CaptureActivitySnapshot
    let isStale: Bool
    private var language: NotificationLanguage { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: CapturePresentation.symbol(snapshot))
                    .foregroundStyle(CapturePresentation.isRecordingCue(snapshot) && !isStale ? Color.islandOrange : Color("SecondaryText"))
                Text(verbatim: CapturePresentation.name)
                    .font(.headline)
                    .foregroundStyle(Color("Ink"))
            }
            // "Recording • 12:43". If iOS says this card is out of date, it says so instead.
            if isStale {
                Text(verbatim: language == .polish ? "Nie wiadomo, czy nagrywanie trwa. Otwórz Doddy’ego." : "Can't tell whether it's still recording. Open Doddy.")
                    .font(.subheadline)
                    .foregroundStyle(Color("Error"))
            } else {
                HStack(spacing: 6) {
                    Text(verbatim: CapturePresentation.status(snapshot, language))
                    Text(verbatim: "•")
                    CaptureElapsed(snapshot: snapshot)
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color("Ink"))
                if let detail = CapturePresentation.detail(snapshot, language) {
                    Text(verbatim: detail).font(.footnote).foregroundStyle(Color("SecondaryText"))
                }
            }
            HStack(spacing: 8) {
                if CapturePresentation.canPause(snapshot), !isStale {
                    Button(intent: PauseDoddyRecordingIntent()) { lockLabel(.pause, "pause.fill") }
                }
                if CapturePresentation.canResume(snapshot), !isStale {
                    Button(intent: ResumeDoddyRecordingIntent()) { lockLabel(.resume, "play.fill") }
                }
                if CapturePresentation.canStop(snapshot) {
                    Button(intent: StopDoddyRecordingIntent()) { lockLabel(.stop, "stop.fill") }
                }
                Link(destination: DeepLink.recordings.url) { lockLabel(.open, "arrow.up.forward") }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .accessibilityElement(children: .contain)
    }

    private func lockLabel(_ action: CapturePresentation.Action, _ symbol: String) -> some View {
        Label(CapturePresentation.label(action, language), systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.lockScreenInk)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color.lockScreenInk.opacity(0.08), in: Capsule())
            .contentShape(Capsule())
    }
}
