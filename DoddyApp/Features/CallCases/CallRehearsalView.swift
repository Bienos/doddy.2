import DoddyCore
import SwiftUI

/// Rehearse the call first (owner backlog #20/#116, ADR-507): Doddy plays the person who answers,
/// in Polish, through the OpenAI voice with no tools. Nobody is called and nothing is saved.
/// Afterwards: "Doddy calls" (back to the approval) or "I'll call myself" (the script on screen).
/// Without the OpenAI voice consent the session refuses to start, and the same consent step as the
/// voice screen (`VoiceAccessGate`) opens first. Not heard on a device yet.
struct CallRehearsalView: View {
    enum Choice { case doddyCalls, callMyself }

    let preview: CallPreview
    let onChoice: (Choice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var session = CallRehearsalSession()
    @State private var askingConsent = false

    var body: some View {
        VStack(spacing: 0) {
            Text(CallRehearsal.banner)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(16)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your question").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                            Text(preview.question).font(.title3)
                        }
                        .padding(.bottom, 8)
                        ForEach(session.lines) { line in
                            VStack(alignment: .leading, spacing: 2) {
                                Group {
                                    if line.fromUser { Text("You") } else { Text(preview.callee.name) }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(line.fromUser ? Theme.accentText : Theme.secondaryText)
                                Text(line.text)
                            }
                            .id(line.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                }
                .onChange(of: session.lines.count) {
                    if let last = session.lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

            VStack(spacing: 10) {
                switch session.state {
                case .idle, .ended, .needsConsent, .failed:
                    if case .failed(let message) = session.state {
                        Text(message).font(.footnote).foregroundStyle(Theme.error).multilineTextAlignment(.center)
                    }
                    Button {
                        Task { await startOrAskConsent() }
                    } label: {
                        Group {
                            if session.state == .idle || session.state == .needsConsent {
                                Label("Start the rehearsal", systemImage: "mic.fill")
                            } else {
                                Label("Rehearse again", systemImage: "mic.fill")
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("callRehearsal.start")
                case .connecting:
                    ProgressView()
                case .live:
                    Text("Call them as you would on the phone. Say \"koniec próby\" for tips.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
                    HStack {
                        Button("Tips on how it went") { Task { await session.askForFeedback() } }
                            .buttonStyle(.bordered)
                        Button("Stop", role: .destructive) { Task { await session.stop() } }
                            .buttonStyle(.bordered)
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        Task { await session.stop(); onChoice(.doddyCalls) }
                    } label: {
                        Label("Doddy calls", systemImage: "phone.arrow.up.right.fill").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        Task { await session.stop(); onChoice(.callMyself) }
                    } label: {
                        Label("I'll call myself", systemImage: "phone").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
        .background(Theme.canvas)
        .navigationTitle("Rehearsal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { Task { await session.stop(); dismiss() } }
            }
        }
        .onDisappear { Task { await session.stop() } }
        .interactiveDismissDisabled(session.isRunning)
        .sheet(isPresented: $askingConsent) {
            NavigationStack {
                VoiceAccessGate(provider: CallRehearsal.provider) {
                    askingConsent = false
                    Task { await startOrAskConsent() }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { askingConsent = false }
                    }
                }
            }
        }
    }

    /// Starts the rehearsal; if the session says the OpenAI voice consent is missing, opens that step.
    private func startOrAskConsent() async {
        await session.start(preview: preview)
        if session.state == .needsConsent { askingConsent = true }
    }
}
