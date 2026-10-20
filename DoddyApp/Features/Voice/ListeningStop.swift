import AVFAudio
import DoddyCore
import Observation
import SwiftUI
import UIKit
import os

/// Audio privacy signal and stop (OP-024, ADR-361). Rules and words are in DoddyCore
/// (ListeningPrivacy.swift); this reads each microphone user's own state, stops them, and shows
/// the indicator above every screen.
@MainActor
enum ListeningStop {
    private static let log = Logger(subsystem: "com.bienos.doddy2.dev", category: "stop-listening")

    /// Who has the microphone open now, from each one's own state.
    static func snapshot() -> MicrophoneSnapshot {
        MicrophoneSnapshot(
            conversation: VoiceSessionController.microphone,
            voiceMemoRecording: MicrophoneHolders.shared.isRecording)
    }

    /// Ends the conversation and stops a voice memo, then reads each one
    /// again and asks iOS to let go of Doddy's audio. Nothing is saved by it.
    static func stopAll() async -> ListeningStopReport {
        let before = snapshot()
        var keptNoteDraft = false
        if let conversation = VoiceSessionController.current {
            keptNoteDraft = await conversation.stopListening()
        }
        let keptMemoDraft = MicrophoneHolders.shared.stopAll()
        var after = snapshot()
        let release: AudioRelease
        if before.open.isEmpty {
            release = .notNeeded
        } else if !after.open.isEmpty {
            // Still open: don't pull the audio from under it; the report says what is still on.
            release = .notNeeded
        } else {
            release = releaseAudio()
            after = snapshot()
        }
        let report = ListeningStopReport(before: before, after: after, release: release,
                                         keptNoteDraft: keptNoteDraft, keptMemoDraft: keptMemoDraft)
        log.notice("stop listening: still open \(report.stillOpen.map(\.rawValue), privacy: .public), release \(String(describing: release), privacy: .public)")
        ListeningIndicatorModel.shared.refresh()
        return report
    }

    /// Deactivating the session stops anything of Doddy's still recording or playing; iOS answers
    /// "busy" when it had to stop something, which still leaves the audio released.
    private static func releaseAudio() -> AudioRelease {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return .released
        } catch let error as NSError where error.code == AVAudioSession.ErrorCode.isBusy.rawValue {
            return .stoppedWhatWasRunning
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// Voice memo recorders that are recording now, so Stop listening can reach one on any screen.
@MainActor
final class MicrophoneHolders {
    static let shared = MicrophoneHolders()
    private var recorders: [ObjectIdentifier: WeakRecorder] = [:]

    private struct WeakRecorder { weak var recorder: VoiceMemoRecorder? }

    private init() {}

    var isRecording: Bool { recorders.values.contains { $0.recorder?.isCapturing == true } }

    func recording(_ recorder: VoiceMemoRecorder, _ on: Bool) {
        if on { recorders[ObjectIdentifier(recorder)] = WeakRecorder(recorder: recorder) } else { recorders[ObjectIdentifier(recorder)] = nil }
        ListeningIndicatorModel.shared.refresh()
    }

    /// Stops every recording; true when one was long enough to be kept as the note's draft.
    func stopAll() -> Bool {
        var kept = false
        for holder in recorders.values {
            if holder.recorder?.stopFromOutside() == true { kept = true }
        }
        recorders = recorders.filter { $0.value.recorder?.isCapturing == true }
        return kept
    }
}

/// What the indicator shows. Refreshed whenever a conversation or a memo changes.
@MainActor
@Observable
final class ListeningIndicatorModel {
    static let shared = ListeningIndicatorModel()

    private(set) var indicator: ListeningIndicator?
    /// The answer to the last Stop listening, shown for a moment (or until tapped when it failed).
    private(set) var result: ListeningStopReport?
    private(set) var isStopping = false
    /// The voice screen shows its own status and End, so the indicator steps aside there.
    private(set) var isHidden = false
    @ObservationIgnored private var clearResult: Task<Void, Never>?

    private init() {}

    func refresh() {
        indicator = ListeningIndicator.current(ListeningStop.snapshot())
        isHidden = ShortcutRouter.shared.isVoicePresented
        ListeningIndicatorWindow.shared.update()
    }

    func stop() async {
        guard !isStopping else { return }
        isStopping = true
        let report = await ListeningStop.stopAll()
        isStopping = false
        show(report)
    }

    /// Shows the answer. "Stopped" goes away by itself; a failure stays until dismissed.
    func show(_ report: ListeningStopReport) {
        result = report
        clearResult?.cancel()
        if report.stopped {
            clearResult = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                self?.dismissResult()
            }
        }
        refresh()
    }

    func dismissResult() {
        result = nil
        refresh()
    }
}

/// A small window above every screen and sheet, holding only the indicator, so it shows over
/// the capture sheet and Settings too. Taps outside the pill reach the app below.
@MainActor
final class ListeningIndicatorWindow {
    static let shared = ListeningIndicatorWindow()
    private var window: UIWindow?
    private var host: UIHostingController<ListeningIndicatorPill>?

    private init() {}

    /// Called when Doddy comes to the front; does nothing once installed.
    func install() {
        guard window == nil, let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        let host = UIHostingController(rootView: ListeningIndicatorPill())
        host.view.backgroundColor = .clear
        let window = UIWindow(windowScene: scene)
        // Above sheets and alerts, below the system's own.
        window.windowLevel = .alert + 1
        window.rootViewController = host
        window.backgroundColor = .clear
        window.isHidden = true
        self.window = window
        self.host = host
        update()
    }

    func update() {
        guard let window else { return }
        let model = ListeningIndicatorModel.shared
        let shows = !model.isHidden && (model.indicator != nil || model.result != nil)
        guard shows else {
            window.isHidden = true
            return
        }
        // Sized once SwiftUI has drawn the new content.
        DispatchQueue.main.async { [weak self] in self?.layout() }
    }

    private func layout() {
        let model = ListeningIndicatorModel.shared
        guard let window, let host, let scene = window.windowScene,
              !model.isHidden, model.indicator != nil || model.result != nil else { return }
        let bounds = scene.screen.bounds
        let top = scene.windows.first(where: \.isKeyWindow)?.safeAreaInsets.top ?? 47
        // Leaves the navigation bar's buttons at both edges free.
        let maxWidth = bounds.width - 120
        let size = host.sizeThatFits(in: CGSize(width: maxWidth, height: 240))
        let width = min(maxWidth, size.width)
        window.frame = CGRect(x: (bounds.width - width) / 2, y: top + 2, width: width, height: size.height)
        window.isHidden = false
    }
}

/// The pill: what is listening, and Stop listening.
struct ListeningIndicatorPill: View {
    private let model = ListeningIndicatorModel.shared
    @State private var expanded = false
    private var language: NotificationLanguage { .current }

    var body: some View {
        Group {
            if let report = model.result {
                Button { model.dismissResult() } label: {
                    Label { Text(verbatim: report.reply(language)).font(.footnote).multilineTextAlignment(.leading) } icon: {
                        Image(systemName: report.stopped ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("listening.result")
            } else if let indicator = model.indicator {
                HStack(spacing: 8) {
                    Button { expanded.toggle(); ListeningIndicatorWindow.shared.update() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: indicator.symbol).foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: indicator.title(language))
                                    .font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                if expanded {
                                    Text(verbatim: indicator.detail(language)).font(.caption2)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text(verbatim: indicator.detail(language)))
                    Button { Task { await model.stop() } } label: {
                        Text(verbatim: ListeningIndicator.stopLabel(language)).font(.footnote.weight(.semibold))
                    }
                    .disabled(model.isStopping)
                    .accessibilityIdentifier("listening.stop")
                }
                .accessibilityIdentifier("listening.indicator")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
        .fixedSize(horizontal: false, vertical: true)
    }
}
