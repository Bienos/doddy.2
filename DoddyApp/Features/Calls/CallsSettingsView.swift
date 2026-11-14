import DoddyCore
import SwiftUI

/// Settings → Phone calls (owner review, 12 Nov 2026: it was one list of eight sections). A short hub:
/// notes waiting for you at the top, then one row for each thing a phone can do with Doddy (call him,
/// let him call you, have him call a business for you), one row for memory, texts and the export, and
/// your recent calls. The pages are in `CallsPages.swift`; they share this view's model.
/// Decision: docs/decisions/2026-11-12-phone-calls-hub.md.
struct CallsSettingsView: View {
    @Environment(MemoryStore.self) private var store
    @State private var model = CallsModel()

    var body: some View {
        Form {
            if !model.isServerConfigured {
                Section {
                    Text("Phone calls aren't available in this version of Doddy yet.")
                }
            } else if let settings = model.settings {
                content(settings)
            } else if !model.isWorking {
                Section { Button("Try again") { Task { await model.refresh() } } }
            }

            CallsMessage(model: model)
        }
        .navigationTitle("Phone calls")
        .callsPage(model: model)
        .task {
            await model.refresh()
            // Recaps of calls to Doddy's phone line waiting on the server (decision 2026-11-09-conversation-recaps).
            await RecapKeeper.rememberPhoneCalls(store: store)
        }
    }

    @ViewBuilder
    private func content(_ s: CallSettings) -> some View {
        notesSection

        Section {
            NavigationLink {
                CallDoddyPage(model: model)
            } label: {
                SettingsRow(icon: "phone.fill", title: "Call Doddy", value: callDoddyValue(s))
            }
            .accessibilityIdentifier("calls.callDoddy.row")
            NavigationLink {
                DoddyCallsYouPage(model: model)
            } label: {
                SettingsRow(icon: "phone.arrow.down.left", title: "Doddy calls you", value: doddyCallsYouValue(s))
            }
            .accessibilityIdentifier("calls.doddyCallsYou")
            NavigationLink {
                CallCasesView()
            } label: {
                SettingsRow(icon: "phone.arrow.up.right", title: "Calls for you")
            }
            .accessibilityIdentifier("calls.callCases")
        } footer: {
            Text("Call Doddy when you need him, let him call you, or have him call someone for you after you approve a card.")
        }

        Section {
            NavigationLink {
                CallsOptionsPage(model: model)
            } label: {
                SettingsRow(icon: "slider.horizontal.3", title: "Memory, texts and history")
            }
            .accessibilityIdentifier("calls.options")
        }

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

    /// What the first row says about calling Doddy: only what the server reported.
    private func callDoddyValue(_ s: CallSettings) -> String {
        if !s.available.inbound || !s.phoneVerified { return NSLocalizedString("Needs setup", comment: "Phone calls: a step is missing") }
        return s.inboundEnabled ? NSLocalizedString("On", comment: "") : NSLocalizedString("Off", comment: "")
    }

    private func doddyCallsYouValue(_ s: CallSettings) -> String {
        if !s.available.outbound || !s.phoneVerified { return NSLocalizedString("Needs setup", comment: "Phone calls: a step is missing") }
        return s.outboundConsent ? NSLocalizedString("On", comment: "") : NSLocalizedString("Off", comment: "")
    }

    /// Notes Doddy wrote down during calls, or kept from your texts. They wait here until you decide.
    @ViewBuilder
    private var notesSection: some View {
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
                        Text(noteOrigin(note))
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
    }

    /// Where a waiting note came from: a call, or your text word for word (ADR-753).
    private func noteOrigin(_ note: CallNote) -> String {
        let when = DateText.full(note.createdDate)
        if note.fromText { return String(format: NSLocalizedString("From your text · %@", comment: ""), when) }
        return String(format: NSLocalizedString("Said on a call · %@", comment: ""), when)
    }

    /// How a call went, as Twilio reported it to Doddy's server (ADR-750). Nothing is added while
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
