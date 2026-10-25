import DoddyCore
import SwiftUI

/// Home → Stopwatch (ADR-652): counts up until you stop it. While it runs the Lock Screen and the
/// Dynamic Island show the same time, ticking by themselves, with Pause and Stop. No alert and no
/// score: it only measures time.
struct StopwatchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var label = ""
    private var stopwatch: StopwatchController { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SceneryBackdrop(place: .court, height: 110, focus: 0.15, pose: pose)
                        .padding(.horizontal, -24)
                    if let watch = stopwatch.watch, !watch.isOver {
                        running(watch)
                    } else if let watch = stopwatch.watch {
                        stopped(watch)
                    } else {
                        startForm
                    }
                }
                .padding(24)
            }
            .background(Theme.canvas)
            .navigationTitle("Stopwatch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { stopwatch.refresh() }
            }
        }
    }

    private var pose: IslandPose? {
        guard let watch = stopwatch.watch else { return nil }
        if watch.isPaused { return .crosslegged }
        return watch.isOver ? .fistpump : .tiptoe
    }

    private var startForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Counts up until you stop it.")
                .font(.title2.weight(.medium))
                .accessibilityAddTraits(.isHeader)
            TextField("What's it for? (optional)", text: $label)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .accessibilityIdentifier("stopwatch.label")
            Text("This line shows on your Lock Screen and in the Dynamic Island while the stopwatch runs. Leave it empty to show only the time.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Button {
                stopwatch.start(label: label)
                label = ""
            } label: {
                HStack { Text("Start stopwatch"); Spacer(); Image(systemName: "stopwatch") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("stopwatch.start")
        }
    }

    private func running(_ watch: Stopwatch) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if let from = watch.countsFrom {
                        IslandElapsedText(startedAt: from)
                    } else {
                        Text(Stopwatch.clock(watch.elapsed(at: Date()))).monospacedDigit()
                    }
                }
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(Color.islandCream)
                .accessibilityIdentifier("stopwatch.time")
                // The user's own line as typed; otherwise our words, which are translated.
                Group {
                    if let line = watch.label {
                        Text(verbatim: line)
                    } else if watch.isPaused {
                        Text("Ready when you are")
                    } else {
                        Text("Counting up")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Color.islandSecondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.islandBlack, in: RoundedRectangle(cornerRadius: 32, style: .continuous))

            HStack(spacing: 12) {
                // Two literal buttons, so both words are translated (a condition inside would not be).
                if watch.isPaused {
                    Button("Resume") { stopwatch.togglePause() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("stopwatch.pause")
                } else {
                    Button("Pause") { stopwatch.togglePause() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("stopwatch.pause")
                }
                Button("Stop", role: .destructive) { stopwatch.stop() }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("stopwatch.stop")
            }
        }
    }

    private func stopped(_ watch: Stopwatch) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(format: NSLocalizedString("Stopped at %@", comment: ""),
                        Stopwatch.clock(watch.elapsed(at: watch.stoppedAt ?? Date()))))
                .font(.title2.weight(.medium))
                .monospacedDigit()
                .accessibilityIdentifier("stopwatch.result")
            if let label = watch.label {
                Text(verbatim: label).foregroundStyle(Theme.secondaryText)
            }
            Button("Start another") { stopwatch.dismiss() }
                .buttonStyle(PrimaryButtonStyle())
            Button("Close") {
                stopwatch.dismiss()
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}
