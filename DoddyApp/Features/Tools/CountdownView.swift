import DoddyCore
import SwiftUI

/// Home → Timer and Home → Wind down (ADR-337): a plain countdown. The timer takes 3, 5, 10 or
/// 15 minutes and an optional label ("Pasta"); the wind-down 5 to 20 minutes and no label. While
/// one runs the island and the Lock Screen (and so StandBy) show the focus board with the
/// time left and Pause / Stop; this screen shows the same. The same timer also starts by voice
/// ("set a timer for ten minutes").
struct CountdownView: View {
    let purpose: CountdownSession.Purpose
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var minutes: Int
    @State private var label = ""
    @State private var starting = false
    private var countdowns: CountdownController { .shared }

    init(purpose: CountdownSession.Purpose) {
        self.purpose = purpose
        _minutes = State(initialValue: purpose == .windDown ? 10 : 5)
    }

    private var isWindDown: Bool { purpose == .windDown }
    private var presets: [Int] { isWindDown ? CountdownSession.windDownPresetMinutes : CountdownSession.timerPresetMinutes }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Doddy kneels to watch the timer, stretches sleepily for the wind-down; the
                    // island's poses for the same moments (ADR-337).
                    SceneryBackdrop(place: isWindDown ? .rooftop : .home, height: 110, focus: 0.2, pose: pose)
                        .padding(.horizontal, -24)
                    if let session = countdowns.session(purpose), !session.isOver {
                        running(session)
                    } else if let session = countdowns.session(purpose) {
                        finished(session)
                    } else {
                        startForm
                    }
                }
                .padding(24)
            }
            .background(Theme.canvas)
            .navigationTitle(isWindDown ? "Wind down" : "Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { countdowns.refresh() }
            }
        }
    }

    private var pose: IslandPose? {
        guard let session = countdowns.session(purpose) else { return nil }
        if session.isPaused { return .crosslegged }
        if case .finished = session.state { return isWindDown ? .crosslegged : .fistpump }
        if session.isOver { return nil }
        return isWindDown ? .yawnStretch : .kneelingInspect
    }

    private var startForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isWindDown ? "A quiet count to bedtime." : "A plain countdown.")
                .font(.title2.weight(.medium))
                .accessibilityAddTraits(.isHeader)
            Picker("Minutes", selection: $minutes) {
                ForEach(presets, id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("countdown.minutes")
            if !isWindDown {
                TextField("What's it for? (optional)", text: $label)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .accessibilityIdentifier("countdown.label")
                Text("This line shows on your Lock Screen and in the Dynamic Island while the timer runs. Leave it empty to show only the time.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("The time left shows on your Lock Screen, in the Dynamic Island and in StandBy, with nothing else. When it ends, a notification says it's time to put the phone down. Doddy doesn't check whether you did.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Button {
                starting = true
                Task {
                    await countdowns.start(seconds: minutes * 60, purpose: purpose, label: isWindDown ? nil : label)
                    starting = false
                }
            } label: {
                HStack { Text(isWindDown ? "Start wind-down" : "Start timer"); Spacer(); Image(systemName: isWindDown ? "moon" : "timer") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(starting)
            .accessibilityIdentifier("countdown.start")
        }
    }

    private func running(_ session: CountdownSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                IslandArtView(art: IslandBoardArt.art(.tinyPromise, scenario: session.isPaused ? 1 : 0, .expanded),
                              live: session.isRunning, maxSize: CGSize(width: 96, height: 96))
                VStack(alignment: .leading, spacing: 4) {
                    Group {
                        if let end = session.endsAt {
                            IslandCountdownText(end: end)
                        } else {
                            Text(DoddyToolAttributes.clock(session.remaining(at: Date())))
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Color.islandCream)
                    .accessibilityIdentifier("countdown.timeLeft")
                    Text(session.label ?? (session.isPaused ? "Ready when you are" : (isWindDown ? "Phone down when it ends" : "Counting down")))
                        .font(.subheadline)
                        .foregroundStyle(Color.islandSecondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.islandBlack, in: RoundedRectangle(cornerRadius: 32, style: .continuous))

            HStack(spacing: 12) {
                Button(session.isPaused ? "Resume" : "Pause") { countdowns.togglePause(purpose) }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("countdown.pause")
                Button("Stop", role: .destructive) { countdowns.stop(purpose) }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("countdown.stop")
            }
            if countdowns.notificationConfirmed[purpose] == false {
                Label("Notifications are off for Doddy or iOS didn't confirm the alert, so there may be no alert when time's up. The island and this screen still show it.",
                      systemImage: "bell.slash")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func finished(_ session: CountdownSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if case .finished = session.state {
                Text(isWindDown ? "Wind-down over." : "Time's up.")
                    .font(.title2.weight(.medium))
                Text(session.label.map { "\($0) · \(CountdownSession.lengthText(session.duration))" }
                     ?? "\(CountdownSession.lengthText(session.duration)), done.")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text(isWindDown ? "Wind-down stopped." : "Timer stopped.")
                    .font(.title2.weight(.medium))
            }
            Button("Start another") { countdowns.dismiss(purpose) }
                .buttonStyle(PrimaryButtonStyle())
            Button("Close") {
                countdowns.dismiss(purpose)
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}
