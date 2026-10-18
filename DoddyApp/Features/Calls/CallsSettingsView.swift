import DoddyCore
import SwiftUI

/// Settings → Phone calls: call Doddy's number, let Doddy call you, PIN, memory on calls, texts
/// to Doddy (ADR-494), notes from calls and texts (waiting for your confirmation), and the export
/// of your phone and text history.
struct CallsSettingsView: View {
    @Environment(MemoryStore.self) private var store
    @State private var model = CallsModel()
    @State private var pinInput = ""

    var body: some View {
        Form {
            if !model.isServerConfigured {
                Section {
                    Text("Phone calls need a Doddy messaging server, and none is connected in this build yet.")
                }
            } else if let settings = model.settings {
                content(settings)
            } else if !model.isWorking {
                Section { Button("Try again") { Task { await model.refresh() } } }
            }

            if let message = model.message {
                Section {
                    Label(message, systemImage: "info.circle")
                        .accessibilityIdentifier("calls.message")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Phone calls")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isWorking)
        .overlay { if model.isWorking { ProgressView() } }
        .task { await model.refresh() }
    }

    @ViewBuilder
    private func content(_ s: CallSettings) -> some View {
        if !s.available.inbound {
            Section {
                Text("Doddy's phone line isn't set up on the server yet. Everything below starts working once it is.")
            }
        }

        if !s.phoneVerified {
            Section {
                Text("First verify your phone number, so Doddy knows it's you calling.")
                NavigationLink("Verify my number") { UpdatesSettingsView() }
            }
        }

        if !model.notes.isEmpty || !model.unreadableNotes.isEmpty || model.notesProblem != nil {
            Section("Notes waiting for you") {
                if let problem = model.notesProblem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.error)
                    Button("Try again") { Task { await model.refresh() } }
                }
                ForEach(model.notes) { note in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(note.text)
                        Text(note.fromText
                             ? String(format: NSLocalizedString("From your text · %@", comment: ""), DateText.full(note.createdDate))
                             : String(format: NSLocalizedString("Said on a call · %@", comment: ""), DateText.full(note.createdDate)))
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                        HStack {
                            Button(model.savedNoteIDs.contains(note.id)
                                   ? NSLocalizedString("Saved. Remove from this list", comment: "")
                                   : NSLocalizedString("Save to memories", comment: "")) {
                                Task { await model.keep(note, into: store) }
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                            Button("Discard", role: .destructive) { Task { await model.discard(note.id) } }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                ForEach(model.unreadableNotes) { note in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This note can't be read any more, so it can't be saved.")
                        Text(String(format: NSLocalizedString("Waiting since %@", comment: ""), DateText.full(note.createdDate)))
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                        Button("Discard", role: .destructive) { Task { await model.discard(note.id) } }
                            .buttonStyle(.borderless)
                    }
                }
                Text("Doddy wrote these down during calls, or kept them from your texts. They become memories only when you save them.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }

        Section("Your PIN") {
            StatusRow(title: "PIN", value: s.pinLocked ? "Locked for a few minutes" : s.pinSet ? "Set" : "Not set")
            SecureField(s.pinSet ? "New PIN (6–8 digits)" : "PIN (6–8 digits)", text: $pinInput)
                .keyboardType(.numberPad)
                .textContentType(.newPassword)
                .accessibilityIdentifier("calls.pin")
            Button(s.pinSet ? "Change PIN" : "Set PIN") {
                Task { await model.setPIN(pinInput); pinInput = "" }
            }
            .disabled(pinInput.count < 6)
            if s.pinSet {
                Button("Remove PIN", role: .destructive) { Task { await model.removePIN() } }
            }
            Text("On every call, Doddy asks for this PIN before looking at your memories or taking a note, because a caller's number can be faked. After five wrong tries PIN entry locks, for longer each time, and you get a notification.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }

        Section("Calling Doddy") {
            if let number = s.doddyNumber, let url = URL(string: "tel:\(number)") {
                StatusRow(title: "Doddy's number", value: number)
                // iPad has no phone; the number above is for calling from a phone (ADR-437).
                if DeviceSupport.hasPhoneCalls { Link("Call Doddy", destination: url) }
            }
            Toggle("Answer calls from my number", isOn: Binding(
                get: { s.inboundEnabled },
                set: { on in Task { await model.setInbound(on) } }))
                .disabled(!s.phoneVerified)
                .accessibilityIdentifier("calls.inbound")
        }

        Section("Memory on calls") {
            Toggle("Let Doddy use my memories on calls", isOn: Binding(
                get: { s.memoryCopy.enabled },
                set: { on in Task { await model.setMemoryCopy(on, records: store.memories) } }))
                .accessibilityIdentifier("calls.memoryCopy")
            if s.memoryCopy.enabled {
                StatusRow(title: "Copied to the server", value: "\(s.memoryCopy.count) memories")
                if case .failed(let error) = MemoryCopySync.shared.status {
                    Label("Last update failed: \(error)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.error)
                }
            }
            Text("Off by default. When on, an encrypted copy of your memories is kept on the Doddy messaging server so Doddy can answer from them on a call, after your PIN. The server can read this copy in order to answer, so it is not end-to-end encrypted. What Doddy reads out is processed by ElevenLabs. Turning this off deletes the copy.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }

        Section("Doddy calls you") {
            Toggle("Doddy may call me", isOn: Binding(
                get: { s.outboundConsent },
                set: { on in Task { await model.setOutbound(on) } }))
                .disabled(!s.phoneVerified)
                .accessibilityIdentifier("calls.outbound")
            Text(CallConsent.text)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            if s.outboundConsent && s.available.outbound {
                Button("Call me now") { Task { await model.callMeNow() } }
                    .accessibilityIdentifier("calls.callMeNow")
            }
        }

        textsSection(s)

        if !model.recent.isEmpty {
            Section("Recent calls") {
                ForEach(model.recent) { call in
                    StatusRow(
                        title: call.direction == "inbound" ? "You called Doddy" : "Doddy called you",
                        value: DateText.full(call.createdDate) + outcomeNote(call))
                }
            }
        }
    }

    /// Texts to Doddy (ADR-494): each switch only once the server says the one before it is on.
    @ViewBuilder
    private func textsSection(_ calls: CallSettings) -> some View {
        let t = model.textSettings ?? .off
        Section("Texts to Doddy") {
            if let number = t.doddyNumber ?? calls.doddyNumber {
                StatusRow(title: "Doddy's number", value: number)
            }
            Toggle("Accept texts from my number", isOn: Binding(
                get: { t.inboundEnabled },
                set: { on in Task { await model.setTextsToDoddy(on) } }))
                .disabled(!t.inboundEnabled && t.inboundBlocker != nil)
                .accessibilityIdentifier("texts.inbound")
            Text(TextsToDoddyConsent.text)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Toggle("Doddy replies by text", isOn: Binding(
                get: { t.repliesEnabled },
                set: { on in Task { await model.setTextReplies(on) } }))
                .disabled(!t.repliesEnabled && t.repliesBlocker != nil)
                .accessibilityIdentifier("texts.replies")
            if t.repliesEnabled {
                Toggle("Replies may use my memories", isOn: Binding(
                    get: { t.repliesUseMemories },
                    set: { on in Task { await model.setTextRepliesUseMemories(on) } }))
                    .disabled(!t.repliesUseMemories && t.memoriesBlocker != nil)
                    .accessibilityIdentifier("texts.memories")
            }
            if let blocker = nextBlocker(t) {
                Label(blocker.localized, systemImage: "info.circle")
                    .font(.footnote)
            }
            Text("Off by default. Only texts from your verified number count; texts from anyone else are dropped without a reply. Without replies, each text waits here as a note. With replies, Doddy answers each text once, within 10 minutes, up to 30 a day, and only to your number; it can leave a note for you to confirm. With memories allowed, a reply can quote a saved note, and texts aren't encrypted between phone networks.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }

        Section("Your phone and text history") {
            Button("Export phone and text history") { Task { await model.exportHistory() } }
                .accessibilityIdentifier("texts.export")
            if let file = model.historyFile {
                ShareLink(item: file) { Label("Share the export", systemImage: "square.and.arrow.up") }
            }
            Text("A file with your calls, the status of texts between you and Doddy, and the notes waiting here. The text of messages isn't in it: Doddy's server erases it once a message is sent. Doddy's server also deletes its records at Twilio after each call or text, a day later unless the server is set up otherwise.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    /// Why the next switch down is off and can't be turned on yet; nil when nothing is in the way.
    private func nextBlocker(_ t: TextSettings) -> TextsBlocker? {
        if !t.inboundEnabled { return t.inboundBlocker }
        if !t.repliesEnabled { return t.repliesBlocker }
        if !t.repliesUseMemories, let blocker = t.memoriesBlocker, blocker != .repliesOff { return blocker }
        return nil
    }

    /// How a call went, as Twilio reported it to Doddy's server (ADR-490). Nothing is added while
    /// there is nothing to say, such as a call that is still being placed.
    private func outcomeNote(_ call: CallRecord) -> String {
        let word: String?
        switch (call.direction, call.status) {
        case (_, "failed"): word = NSLocalizedString("failed", comment: "Recent calls: the call didn't go through")
        case (_, "unknown"): word = NSLocalizedString("not confirmed", comment: "Recent calls: unclear whether the call was placed")
        case ("outbound", "ringing"): word = NSLocalizedString("ringing", comment: "Recent calls: Doddy's call is ringing")
        case ("outbound", "answered"), ("outbound", "completed"):
            word = NSLocalizedString("answered", comment: "Recent calls: you picked up Doddy's call")
        case ("outbound", "no_answer"): word = NSLocalizedString("no answer", comment: "Recent calls: nobody picked up Doddy's call")
        case ("outbound", "busy"): word = NSLocalizedString("busy", comment: "Recent calls: your line was busy")
        case ("outbound", "canceled"): word = NSLocalizedString("cancelled", comment: "Recent calls: the call was cancelled before it rang through")
        default: word = nil
        }
        return word.map { " · \($0)" } ?? ""
    }
}
