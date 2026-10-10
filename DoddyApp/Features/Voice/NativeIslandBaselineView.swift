#if DEBUG
import ActivityKit
import SwiftUI

/// Explicitly launched offline test surface. No voice controller, SDK session or microphone.
struct NativeIslandBaselineView: View {
    @State private var isRunning = false
    @State private var isMuted = false
    @State private var nativeActivityCount = 0
    /// @State so a redraw of this view keeps the controller that holds the running activity;
    /// a plain `let` made a new one per redraw, so the system Mute/End buttons could reach a copy
    /// with no activity. That alone does not explain the red "system Island Unmute" check: the
    /// status label follows `isMuted`, which the handler toggles whichever controller it holds.
    /// So the handler most likely never ran in this process; see ADR-123 (not yet re-run on a Mac).
    @State private var island = VoiceLiveActivity()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Native Island test")
                        .font(.headline)
                    Text("Offline fixture. No microphone, audio or provider connection. The widget always says Test activity or Test muted.")
                    Text(isRunning ? (isMuted ? "Fixture muted" : "Fixture active") : "Fixture ended")
                        .accessibilityIdentifier("island.fixture.status")
                    Button("Start test activity") { start() }
                        .disabled(isRunning)
                        .accessibilityIdentifier("island.fixture.start")
                    Button("End test activity") { end() }
                        .disabled(!isRunning)
                        .accessibilityIdentifier("island.fixture.end")
                    Button("Toggle test mute") { toggleMute() }
                        .disabled(!isRunning)
                        .accessibilityIdentifier("island.fixture.mute")
                }
                Section("System observation") {
                    Text("\(nativeActivityCount) native activities")
                        .accessibilityIdentifier("island.fixture.nativeCount")
                    Text("Go Home to see the actual widget. Mute and End use the production LiveActivityIntent handlers, connected here only to this fixture.")
                }
            }
            .navigationTitle("Offline baseline")
        }
        .task {
            VoiceActivityActions.shared.endConversation = { end() }
            VoiceActivityActions.shared.toggleMute = { toggleMute() }
            while !Task.isCancelled {
                nativeActivityCount = Activity<DoddyVoiceAttributes>.activities.count
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        .onDisappear {
            end()
            VoiceActivityActions.shared.endConversation = nil
            VoiceActivityActions.shared.toggleMute = nil
        }
    }

    private func start() {
        isRunning = true
        isMuted = false
        island.show(.init(status: .testFixture, isMuted: false), startedAt: .now)
    }

    private func toggleMute() {
        guard isRunning else { return }
        isMuted.toggle()
        island.show(.init(status: .testFixture, isMuted: isMuted), startedAt: .now)
    }

    private func end() {
        island.end()
        isRunning = false
    }
}
#endif
