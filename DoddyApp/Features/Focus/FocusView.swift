import DoddyCore
import SwiftUI

/// Home → Focus (ADR-214): pick 15, 25 or 45 minutes and, if you like, a line saying what it's
/// for. While it runs the island shows the owner's Tiny Promise board; this screen shows the
/// same drawing, the time left and Pause / Stop.
struct FocusView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var minutes = 25
    @State private var label = ""
    @State private var starting = false
    private var focus: FocusController { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let session = focus.session, !session.isOver {
                        running(session)
                    } else if let session = focus.session {
                        finished(session)
                    } else {
                        startForm
                    }
                }
                .padding(24)
            }
            .background(Theme.canvas)
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { focus.refresh() }
            }
        }
    }

    private var startForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("One thing at a time.")
                .font(.title2.weight(.medium))
                .accessibilityAddTraits(.isHeader)
            Picker("Minutes", selection: $minutes) {
                ForEach(FocusSession.presetMinutes, id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("focus.minutes")
            TextField("What's it for? (optional)", text: $label)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .accessibilityIdentifier("focus.label")
            Text("This line shows on your Lock Screen and in the Dynamic Island while the timer runs. Leave it empty to show only the time.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Button {
                starting = true
                Task {
                    await focus.start(minutes: minutes, label: label)
                    starting = false
                }
            } label: {
                HStack { Text("Start focus"); Spacer(); Image(systemName: "timer") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(starting)
            .accessibilityIdentifier("focus.start")
        }
    }

    private func running(_ session: FocusSession) -> some View {
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
                    .accessibilityIdentifier("focus.timeLeft")
                    Text(session.label ?? (session.isPaused ? "Ready when you are" : "One thing at a time"))
                        .font(.subheadline)
                        .foregroundStyle(Color.islandSecondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.islandBlack, in: RoundedRectangle(cornerRadius: 32, style: .continuous))

            HStack(spacing: 12) {
                Button(session.isPaused ? "Resume" : "Pause") { focus.togglePause() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("focus.pause")
                Button("Stop", role: .destructive) { focus.stop() }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("focus.stop")
            }
            if focus.notificationConfirmed == false {
                Label("Notifications are off for Doddy or iOS didn't confirm the alert, so there may be no alert when time's up. The island and this screen still show it.",
                      systemImage: "bell.slash")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func finished(_ session: FocusSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if case .finished = session.state {
                Text("Time's up.")
                    .font(.title2.weight(.medium))
                Text(session.label.map { "\($0) · \(Int((session.duration / 60).rounded())) min" }
                     ?? "\(Int((session.duration / 60).rounded())) minutes, done.")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("Focus stopped.")
                    .font(.title2.weight(.medium))
            }
            Button("Start another") { focus.dismiss() }
                .buttonStyle(PrimaryButtonStyle())
            Button("Close") {
                focus.dismiss()
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}
