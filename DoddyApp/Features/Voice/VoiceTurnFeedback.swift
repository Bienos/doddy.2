import DoddyCore
import Foundation
import Observation
import UIKit
import os

/// What the person sees and feels while Doddy works on an answer, and the time of each turn in the
/// phone's log (owner, 12 Nov 2026; decision `2026-11-12-voice-turn-feedback`). The rules are
/// `VoiceTurnWatch` in DoddyCore, tested on Linux; this class only feeds it the provider's events,
/// keeps the label current and gives one light tap when the person's words have arrived.
///
/// Privacy: the log line has fixed words, seconds and the agent's tool names
/// (`VoiceTurnTiming.line`); nothing said is logged and nothing leaves the phone.
@MainActor
@Observable
final class VoiceTurnFeedback {
    /// What the voice screen says under Doddy while he works. nil when nothing is waited on.
    private(set) var label: VoiceWaitLabel?

    @ObservationIgnored private var watch = VoiceTurnWatch()
    @ObservationIgnored private var stillTask: Task<Void, Never>?
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    @ObservationIgnored private var tap: UIImpactFeedbackGenerator?
    private static let log = Logger(subsystem: "com.bienos.doddy2.dev", category: "voice-audio")

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    /// The person's words reached the phone. `tap`: one soft tap, so they know they were heard
    /// before the screen changes. iOS leaves it out when System Haptics is off in Settings.
    func userFinished(tap wantsTap: Bool) {
        watch.userFinished(at: now)
        if wantsTap {
            if tap == nil { tap = UIImpactFeedbackGenerator(style: .soft) }
            tap?.impactOccurred(intensity: 0.6)
        }
        refresh()
    }

    func toolStarted(id: String, name: String) {
        watch.toolStarted(id: id, name: name, at: now)
        refresh()
    }

    func toolAnswered(id: String) {
        watch.toolAnswered(id: id, at: now)
        refresh()
    }

    /// Doddy started speaking: logs the turn the first time after the person's words.
    func agentStartedSpeaking() {
        if let timing = watch.agentStartedSpeaking(at: now) {
            Self.log.notice("voice \(timing.line, privacy: .public)")
        }
        refresh()
    }

    /// Interrupted, or the conversation is over.
    func reset() {
        watch.reset()
        holdTask?.cancel()
        holdTask = nil
        refresh()
    }

    /// True when "Working on it…" should stay although the provider said listening (a tool has
    /// just answered and Doddy hasn't spoken yet). `ended` runs when the hold runs out on its own,
    /// for the controller to show Listening then if nothing else happened.
    func holdsThinking(whenEnded ended: @escaping @MainActor () -> Void) -> Bool {
        guard watch.holdsThinking(at: now), let end = watch.holdEnds() else { return false }
        holdTask?.cancel()
        holdTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, end - (self?.now ?? end)) + 0.05))
            guard !Task.isCancelled, let self, !self.watch.holdsThinking(at: self.now) else { return }
            ended()
        }
        return true
    }

    /// The words under Doddy while he works.
    var statusText: String {
        guard let label else { return NSLocalizedString("Working on it…", comment: "") }
        if label.still {
            return label.activity == nil
                ? NSLocalizedString("Still working on it…", comment: "")
                : NSLocalizedString("Still on it, this one takes a moment…", comment: "")
        }
        return switch label.activity {
        case nil: NSLocalizedString("Working on it…", comment: "")
        case .searchingWeb: NSLocalizedString("Searching the web…", comment: "")
        case .readingNews: NSLocalizedString("Checking the news…", comment: "")
        case .lookingAtScreen: NSLocalizedString("Looking at your screen…", comment: "")
        case .searchingNotes: NSLocalizedString("Looking through your notes…", comment: "")
        case .askingClaude: NSLocalizedString("Asking Claude…", comment: "")
        case .checkingEmail: NSLocalizedString("Checking your email…", comment: "")
        case .findingPlaces: NSLocalizedString("Looking for places…", comment: "")
        case .makingDocument: NSLocalizedString("Making the document…", comment: "")
        case .checkingWeather: NSLocalizedString("Checking the weather…", comment: "")
        case .lookingUp: NSLocalizedString("Looking it up…", comment: "")
        case .checkingCalendar: NSLocalizedString("Checking your calendar…", comment: "")
        }
    }

    /// Updates the label now and again when it turns to "still".
    private func refresh() {
        let current = watch.label(at: now)
        if label != current { label = current }
        stillTask?.cancel()
        stillTask = nil
        guard let current, !current.still, let still = watch.stillFrom() else { return }
        let wait = max(0, still - now) + 0.05
        stillTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
