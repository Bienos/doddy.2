import DoddyCore
import SwiftUI

// The pages under Settings › Phone calls (owner review, 12 Nov 2026: one long list of eight sections
// became three pages and a short hub). Each page takes the hub's `CallsModel`, so what one page
// changes is what the others show; the model only shows what the server reported.
// Decision: docs/decisions/2026-11-12-phone-calls-hub.md.
// Compiled in hosted CI only; NOT RUN on a device.

extension View {
    /// The look every phone-calls page shares: the canvas, a small title bar, and nothing tappable
    /// while the model is talking to the server. Each page sets its own navigation title as a literal, so the
    /// string collector (tools/build_strings_catalog.py) finds it.
    func callsPage(model: CallsModel) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .disabled(model.isWorking)
            .overlay { if model.isWorking { ProgressView() } }
    }
}

/// What the server last said about a change, as the last section of a page.
struct CallsMessage: View {
    let model: CallsModel

    var body: some View {
        if let message = model.message {
            Section {
                Label(message, systemImage: "info.circle")
                    .accessibilityIdentifier("calls.message")
            }
        }
    }
}

// MARK: Call Doddy

/// Doddy's number, whether Doddy knows it's you, and the PIN he asks for on every call.
struct CallDoddyPage: View {
    let model: CallsModel
    @State private var pinInput = ""

    var body: some View {
        Form {
            if let s = model.settings {
                if !s.available.inbound {
                    Section {
                        Text("Doddy's phone line isn't set up on the server yet. Calls start working once it is.")
                    }
                }
                numberSection(s)
                recogniseSection(s)
                pinSection(s)
            }
            CallsMessage(model: model)
        }
        .navigationTitle("Call Doddy")
        .callsPage(model: model)
    }

    @ViewBuilder
    private func numberSection(_ s: CallSettings) -> some View {
        if let number = s.doddyNumber, let url = URL(string: "tel:\(number)") {
            Section {
                StatusRow(title: "Doddy's number", value: number)
                // iPad has no phone; the number above is for calling from a phone (ADR-437).
                if DeviceSupport.hasPhoneCalls {
                    Link("Call Doddy", destination: url)
                        .accessibilityIdentifier("calls.callDoddy")
                }
            }
        }
    }

    @ViewBuilder
    private func recogniseSection(_ s: CallSettings) -> some View {
        Section {
            StatusRow(
                title: "Your number",
                value: s.phoneVerified
                    ? NSLocalizedString("Verified", comment: "Phone calls: the person's number has been checked")
                    : NSLocalizedString("Not verified", comment: "Phone calls: the person's number hasn't been checked"))
            if !s.phoneVerified {
                NavigationLink("Verify my number") { UpdatesSettingsView() }
            }
            Toggle("Answer calls from my number", isOn: Binding(
                get: { s.inboundEnabled },
                set: { on in Task { await model.setInbound(on) } }))
                .disabled(!s.phoneVerified)
                .accessibilityIdentifier("calls.inbound")
        } header: {
            Text("So Doddy knows it's you")
        } footer: {
            if !s.phoneVerified {
                Text("First verify your phone number, so Doddy knows it's you calling.")
            }
        }
    }

    @ViewBuilder
    private func pinSection(_ s: CallSettings) -> some View {
        Section {
            StatusRow(
                title: "PIN",
                value: s.pinLocked
                    ? NSLocalizedString("Locked for a few minutes", comment: "Phone calls: too many wrong PINs")
                    : s.pinSet ? NSLocalizedString("Set", comment: "") : NSLocalizedString("Not set", comment: ""))
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
        } header: {
            Text("Your PIN")
        } footer: {
            Text("On every call, Doddy asks for this PIN before looking at your memories or taking a note, because a caller's number can be faked. After five wrong tries PIN entry locks, for longer each time, and you get a notification.")
        }
    }
}

// MARK: Doddy calls you

/// Whether Doddy may call, the button that makes him call now, and the calls booked for later.
struct DoddyCallsYouPage: View {
    let model: CallsModel

    var body: some View {
        Form {
            if let s = model.settings {
                consentSection(s)
                if !s.phoneVerified {
                    Section {
                        Text("Doddy only calls a number you have verified.")
                        NavigationLink("Verify my number") { UpdatesSettingsView() }
                    }
                }
                if s.available.outbound {
                    scheduledSection(s)
                }
            }
        }
        .navigationTitle("Doddy calls you")
        .callsPage(model: model)
    }

    /// The answer to "Call me now" shows right under the button, not at the bottom of a long page.
    @ViewBuilder
    private func consentSection(_ s: CallSettings) -> some View {
        Section {
            Toggle("Doddy may call me", isOn: Binding(
                get: { s.outboundConsent },
                set: { on in Task { await model.setOutbound(on) } }))
                .disabled(!s.phoneVerified)
                .accessibilityIdentifier("calls.outbound")
            if !s.available.outbound {
                Text("Doddy's phone line isn't set up on the server yet.")
                    .foregroundStyle(Theme.secondaryText)
            } else if s.outboundConsent {
                Button("Call me now") { Task { await model.callMeNow() } }
                    .accessibilityIdentifier("calls.callMeNow")
            }
            if let message = model.message {
                Label(message, systemImage: "info.circle")
                    .accessibilityIdentifier("calls.message")
            }
        } footer: {
            Text(CallConsent.text)
        }
    }

    /// Calls booked for later by voice (ADR-754): when, what Doddy will say, and Cancel while waiting.
    @ViewBuilder
    private func scheduledSection(_ s: CallSettings) -> some View {
        let quiet = s.quietHours ?? .standard
        Section {
            if let problem = model.scheduledProblem {
                Text(problem)
                    .foregroundStyle(Theme.secondaryText)
            } else if model.scheduled.isEmpty {
                Text("None. Ask Doddy, for example “Call me at six about the cake.”")
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(model.scheduled) { call in
                VStack(alignment: .leading, spacing: 4) {
                    Text(DateText.full(call.atDate))
                        .font(.body)
                    if let reason = call.reason {
                        Text(verbatim: "“\(reason)”")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Text(Self.scheduledState(call))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    if call.canCancel {
                        Button("Cancel this call", role: .destructive) { Task { await model.cancel(call) } }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("calls.scheduled.cancel")
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Calls you booked")
        } footer: {
            Text(String(format: NSLocalizedString("Doddy doesn't call in quiet hours (%@–%@ in your iPhone's time zone) unless you allowed it on the call's card. Turning off \"Doddy may call me\" cancels the calls still waiting.", comment: ""), quiet.start, quiet.end))
        }
    }

    /// What happened to a booked call, from the server's state only.
    static func scheduledState(_ call: ScheduledCall) -> String {
        switch call.state {
        case "scheduled": NSLocalizedString("Waiting. Doddy's server will call you then.", comment: "")
        case "placing": NSLocalizedString("Doddy's server is placing this call.", comment: "")
        case "placed": NSLocalizedString("Placed: the phone service accepted the call.", comment: "")
        case "cancelled" where call.errorCode == "cancelled_by_user": NSLocalizedString("You cancelled it.", comment: "")
        case "cancelled": NSLocalizedString("Cancelled: your number or your consent to calls changed.", comment: "")
        case "skipped_quiet_hours": NSLocalizedString("Not called: it was quiet hours in your iPhone's time zone.", comment: "")
        case "missed": NSLocalizedString("Not called: Doddy's server couldn't place it in time.", comment: "")
        case "limit": NSLocalizedString("Not called: Doddy had already tried to call as many times as it may.", comment: "")
        case "failed" where call.errorCode == "not_configured":
            NSLocalizedString("Not called: Doddy's phone line wasn't set up on its server.", comment: "")
        case "failed" where call.errorCode == "reason_unreadable":
            NSLocalizedString("Not called: Doddy's server couldn't read what the call was about.", comment: "")
        case "failed": NSLocalizedString("Not called: the phone service turned it down.", comment: "")
        case "unknown": NSLocalizedString("Not sure: Doddy couldn't confirm whether the call was placed. It won't try again.", comment: "")
        default: NSLocalizedString("Doddy couldn't tell what happened to this call.", comment: "")
        }
    }
}

// MARK: Memory, texts and history

/// The three things that are not about one call: memories Doddy may use on a call, texts to Doddy
/// (ADR-753) and the export of your phone and text history.
struct CallsOptionsPage: View {
    @Environment(MemoryStore.self) private var store
    let model: CallsModel

    var body: some View {
        Form {
            if let s = model.settings {
                memorySection(s)
                textsSection(s)
                historySection
            }
            CallsMessage(model: model)
        }
        .navigationTitle("Memory, texts and history")
        .callsPage(model: model)
        // The export is a file on this iPhone; it goes when you leave the page that made it.
        .onDisappear { model.clearExport() }
    }

    @ViewBuilder
    private func memorySection(_ s: CallSettings) -> some View {
        Section {
            Toggle("Let Doddy use my memories on calls", isOn: Binding(
                get: { s.memoryCopy.enabled },
                set: { on in Task { await model.setMemoryCopy(on, records: store.memories) } }))
                .accessibilityIdentifier("calls.memoryCopy")
            if s.memoryCopy.enabled {
                StatusRow(title: "Memories kept for calls", value: "\(s.memoryCopy.count)")
                if case .failed(let error) = MemoryCopySync.shared.status {
                    Label(String(format: NSLocalizedString("Last update failed: %@", comment: ""), error), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.error)
                }
            }
        } header: {
            Text("Memory on calls")
        } footer: {
            Text("Off by default. When on, an encrypted copy of your memories is kept on the Doddy messaging server so Doddy can answer from them on a call, after your PIN. The server can read this copy in order to answer, so it is not end-to-end encrypted. What Doddy reads out is processed by ElevenLabs. Turning this off deletes the copy.")
        }
    }

    /// Texts to Doddy (ADR-753): the switch is shown as on only once the server says so.
    @ViewBuilder
    private func textsSection(_ calls: CallSettings) -> some View {
        let t = model.textSettings ?? .off
        Section {
            if let number = t.doddyNumber ?? calls.doddyNumber {
                StatusRow(title: "Doddy's number", value: number)
            }
            if model.textSettings == nil, let problem = model.textsProblem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.error)
                Button("Try again") { Task { await model.refresh() } }
            }
            ForEach(t.pauses, id: \.self) { pause in
                Label(pause.localized, systemImage: "pause.circle")
                    .font(.footnote)
            }
            Toggle("Accept texts from my number", isOn: Binding(
                get: { t.inboundEnabled },
                set: { on in Task { await model.setTextsToDoddy(on) } }))
                .disabled(model.textSettings == nil || (!t.inboundEnabled && t.inboundBlocker != nil))
                .accessibilityIdentifier("texts.inbound")
            Text(TextsToDoddyConsent.text)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            if model.textSettings != nil, !t.inboundEnabled, let blocker = t.inboundBlocker {
                Label(blocker.localized, systemImage: "info.circle")
                    .font(.footnote)
            }
        } header: {
            Text("Texts to Doddy")
        } footer: {
            Text("Off by default. Only texts from your verified number count; texts from anyone else are dropped without a reply. Each text waits here as a note, while there's room for 20 notes and up to 30 texts an hour. Doddy does not answer them, and no AI reads them. Texts aren't encrypted between phone networks.")
        }
    }

    private var historySection: some View {
        Section {
            Button("Export phone and text history") { Task { await model.exportHistory() } }
                .accessibilityIdentifier("texts.export")
            if let file = model.historyFile {
                ShareLink(item: file) { Label("Share the export", systemImage: "square.and.arrow.up") }
            }
        } header: {
            Text("Your phone and text history")
        } footer: {
            Text("A file with your calls, the status of texts between you and Doddy, and the notes waiting here. The text of messages isn't in it: Doddy's server erases it once a message is sent. Doddy's server also asks Twilio to delete its records of each call and text, a day later unless the server is set up otherwise. The file is removed from this iPhone when you leave this screen.")
        }
    }
}
