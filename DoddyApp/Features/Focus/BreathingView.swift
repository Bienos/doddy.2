import DoddyCore
import Observation
import SwiftUI

/// The breathing exercise (ADR-215): in 4 s, out 6 s for 1, 2 or 3 minutes, followed on this
/// screen with the owner's Calm Tide board. The island shows only "Breathing" and the time
/// left: it can't switch In/Out while the app isn't running, so it never claims a phase.
@MainActor
@Observable
final class BreathingController {
    static let shared = BreathingController()

    private(set) var session: BreathingSession?
    @ObservationIgnored private let island = ToolLiveActivity(kind: .breathing)
    @ObservationIgnored private var endTimer: Task<Void, Never>?
    private static let doneCardFor: TimeInterval = 60

    init() {
        ToolActivityActions.shared.stop[.breathing] = { [weak self] in self?.stop() }
    }

    func start(minutes: Int) {
        endTimer?.cancel()
        let new = BreathingSession(minutes: minutes, now: Date())
        session = new
        island.show(.init(isPaused: false, endsAt: new.endsAt), startedAt: new.startedAt, duration: new.duration)
        endTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(new.duration + 0.5))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    /// Called when the app returns: an exercise whose time passed is over.
    func refresh() {
        guard let session, session.isOver(at: Date()) else { return }
        finish()
    }

    func stop() {
        endTimer?.cancel()
        session = nil
        island.end(final: nil)
    }

    private func finish() {
        island.end(final: .init(isPaused: false, endsAt: nil, isFinished: true), keepFor: Self.doneCardFor)
        session = nil
        finished = true
    }

    /// The last exercise ran to its end (for the "Nicely done" line).
    var finished = false
}

struct BreathingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var minutes = 1
    private var breathing: BreathingController { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let session = breathing.session {
                        exercise(session)
                    } else {
                        startForm
                    }
                }
                .padding(24)
            }
            .background(Theme.canvas)
            .navigationTitle("Breathe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { breathing.refresh() }
            }
        }
    }

    private var startForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            if breathing.finished {
                Text("Nicely done.")
                    .font(.title2.weight(.medium))
            }
            Text("Breathe in for 4 seconds, out for 6. Follow the words and the tide.")
                .foregroundStyle(Theme.secondaryText)
            Picker("Minutes", selection: $minutes) {
                ForEach(BreathingSession.presetMinutes, id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.segmented)
            Button {
                breathing.finished = false
                breathing.start(minutes: minutes)
            } label: {
                HStack { Text("Start"); Spacer(); Image(systemName: "wind") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("breathe.start")
            Text("This is a simple paced-breathing guide, not medical advice.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func exercise(_ session: BreathingSession) -> some View {
        // Redraws a few times a second while open; the phase comes from the clock.
        TimelineView(.periodic(from: session.startedAt, by: reduceMotion ? 1 : 0.1)) { context in
            let now = context.date
            let phase = session.phase(at: now)
            let breathingIn = phase.phase == .breatheIn
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 14) {
                    // Calm Tide's two boards: inhale (second) and exhale (first).
                    IslandArtView(art: IslandBoardArt.art(.calmTide, scenario: breathingIn ? 1 : 0, .expanded),
                                  live: true, maxSize: CGSize(width: 160, height: 140))
                        .scaleEffect(reduceMotion ? 1 : (breathingIn ? 0.9 + 0.15 * phase.progress : 1.05 - 0.15 * phase.progress))
                    Text(breathingIn ? "Breathe in" : "Breathe out")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(Color.islandCream)
                        .accessibilityAddTraits(.updatesFrequently)
                    Text("\(Int(phase.secondsLeft.rounded(.up)))")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(Color.islandSecondary)
                        .accessibilityHidden(true)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(Color.islandBlack, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                HStack {
                    Text("\(DoddyToolAttributes.clock(session.remaining(at: now))) left")
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Button("Stop", role: .destructive) { breathing.stop() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("breathe.stop")
                }
            }
        }
    }
}
