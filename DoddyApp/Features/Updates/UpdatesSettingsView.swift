import DoddyCore
import SwiftUI

/// Settings → Notifications and texts: turn on updates from Doddy, one at a time. Needs the
/// Doddy messaging server (`server/messaging`).
struct UpdatesSettingsView: View {
    @State private var model = UpdatesModel()
    @AppStorage(PreferenceKey.messagingServerURL) private var serverURL = ""
    @State private var numberInput = ""
    @State private var codeInput = ""
    @State private var confirmDelete = false

    var body: some View {
        Form {
            if !model.isServerConfigured {
                Section {
                    Text("Updates need a Doddy messaging server, and none is connected in this build yet. Nothing is sent anywhere until one is.")
                }
            } else {
                notificationsSection
                textsSection
                if let test = model.lastTest {
                    Section("Last test") {
                        StatusRow(title: test.channel == .push ? "Notification" : "Text", value: test.userFacingText)
                            .accessibilityIdentifier("updates.lastTest")
                    }
                }
                Section {
                    Button("Delete my Doddy messaging data", role: .destructive) { confirmDelete = true }
                    Text("Removes your anonymous server account, this iPhone's notification token, your phone number, queued updates, call settings, notes from calls and any memory copy for calls. Memories on this iPhone are not affected.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            if let message = model.message {
                Section {
                    Label(message, systemImage: "info.circle")
                        .accessibilityIdentifier("updates.message")
                }
            }

            Section("What is shared") {
                Text("To send updates, the Doddy messaging server keeps an anonymous account ID for this iPhone, its notification token and, if you add it, your phone number and SMS consent. The text of an update is kept only until it is sent. Apple delivers notifications; Twilio sends texts and checks your number. Your memories stay on this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }

            Section("Server (development)") {
                TextField("https://…", text: $serverURL)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit { Task { await model.reconnect() } }
                    .accessibilityIdentifier("updates.serverURL")
                if !serverURL.isEmpty && ServerConfig.validated(serverURL) == nil {
                    Text("Use an https address with no path, like https://doddy-messaging.onrender.com.")
                        .font(.footnote)
                        .foregroundStyle(Theme.error)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Notifications and texts")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isWorking)
        .overlay { if model.isWorking { ProgressView() } }
        .task { await model.refresh() }
        .confirmationDialog("Delete your Doddy messaging data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await model.deleteServerAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Notifications and texts stop. Your memories on this iPhone stay.")
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            switch model.pushState {
            case .unknown:
                StatusRow(title: "Notifications", value: "Checking…")
            case .off:
                StatusRow(title: "Notifications", value: "Off")
                Button("Turn on notifications") { Task { await model.turnOnPush() } }
                    .accessibilityIdentifier("updates.pushOn")
            case .on:
                StatusRow(title: "Notifications", value: "On for this iPhone")
                Button("Send a test notification") { Task { await model.sendTest(.push) } }
                Button("Turn off notifications") { Task { await model.turnOffPush() } }
            case .deniedInSettings:
                StatusRow(title: "Notifications", value: "Blocked in iOS Settings")
                Text("You turned notifications off for Doddy in iOS Settings. Turn them on there to get updates.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var textsSection: some View {
        Section("Text messages") {
            if let number = model.phone.phone {
                StatusRow(title: "Your number", value: number)
                if model.phone.optedOut {
                    Text("You replied STOP, so texts are blocked by the carrier. Text START to Doddy's number to allow them again.")
                        .font(.footnote)
                } else {
                    Toggle("Texts from Doddy", isOn: Binding(
                        get: { model.phone.smsEnabled },
                        set: { on in Task { await model.setTexts(on: on) } }))
                        .accessibilityIdentifier("updates.smsToggle")
                    Text(SMSConsent.text)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    if model.phone.smsEnabled {
                        Button("Send a test text") { Task { await model.sendTest(.sms) } }
                    }
                }
                Button("Remove this number", role: .destructive) { Task { await model.removePhone() } }
            } else {
                switch model.phoneStep {
                case .enterNumber:
                    TextField("Phone number, e.g. +48 500 100 200", text: $numberInput)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .accessibilityIdentifier("updates.phone")
                    Button("Text me a code") { Task { await model.sendCode(to: numberInput) } }
                        .disabled(numberInput.isEmpty)
                    Text("Twilio sends a one-time code to check the number is yours. Texts with updates only start after you turn them on.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                case .enterCode(let phone):
                    Text("Enter the code sent to \(phone).")
                    TextField("Code", text: $codeInput)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .accessibilityIdentifier("updates.code")
                    Button("Confirm") { Task { await model.confirm(code: codeInput); codeInput = "" } }
                        .disabled(codeInput.count < 4)
                    Button("Use a different number") { model.cancelVerification() }
                }
            }
        }
    }
}
