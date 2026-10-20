import DoddyCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings → "Hey Doddy" (ADR-254). Off unless turned on. Needs the user's own Picovoice
/// AccessKey and "Hey Doddy" keyword file from the Picovoice Console; neither is part of the app.
/// The status line is the listener's own state, so it never says "Listening" when it isn't.
struct HeyDoddySettingsSection: View {
    @AppStorage(PreferenceKey.heyDoddyOn) private var isOn = false
    @AppStorage(PreferenceKey.nickname) private var nickname = ""
    @Environment(ProfileStore.self) private var profiles
    @State private var listener = WakeWordListener.shared
    @State private var keyDraft = ""
    @State private var hasKey = WakeAccessKeyStore.isSaved
    @State private var fileName = WakeKeywordStore.importedName
    @State private var hasFile = WakeKeywordStore.exists
    @State private var problem: String?
    @State private var choosingFile = false
    @State private var isWorking = false
    /// One tap is enough (ADR-328): the keyword file is in the app and the key is here or comes
    /// from the token server. Then the Picovoice fields are only for someone using their own.
    @State private var oneTap = WakeOneTapSetup.isReady
    @State private var showOwnSetup = false

    private var greeting: String {
        WakeGreeting.line(name: WakeGreeting.name(nickname: nickname, profileName: profiles.profile.value(.name)))
    }

    var body: some View {
        Section {
            Toggle("Listen for \u{201C}Hey Doddy\u{201D}", isOn: Binding(
                get: { isOn },
                set: { on in
                    isWorking = true
                    Task {
                        if on { await listener.turnOn() } else { listener.turnOff() }
                        isWorking = false
                    }
                }))
                .disabled(isWorking)
                .accessibilityIdentifier("settings.heyDoddy.toggle")
            StatusRow(title: "Now", value: listener.state.summary)
                .accessibilityIdentifier("settings.heyDoddy.status")
            if isOn && FocusFilterState.shared.settings.pausesHeyDoddy {
                Label("Paused by your Focus. It listens again when that Focus ends.", systemImage: "moon")
                    .font(.footnote)
                    .accessibilityIdentifier("settings.heyDoddy.focusPaused")
            }
            if let keyProblem = listener.keyProblem {
                Label(keyProblem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.error)
                    .accessibilityIdentifier("settings.heyDoddy.keyProblem")
            }
            if hasKey || hasFile || (isOn && !oneTap) {
                setup
            } else if oneTap {
                DisclosureGroup("Use my own Picovoice key and file", isExpanded: $showOwnSetup) { setup }
                    .accessibilityIdentifier("settings.heyDoddy.ownSetup")
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.error)
                    .accessibilityIdentifier("settings.heyDoddy.problem")
            }
            Text(explanation)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityIdentifier("settings.heyDoddy.note")
        } header: {
            Text("Hey Doddy")
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.data]) { result in
            importFile(result)
        }
    }

    @ViewBuilder
    private var setup: some View {
        if hasKey {
            StatusRow(title: "Picovoice AccessKey", value: "Saved on this iPhone")
            Button("Remove AccessKey", role: .destructive) {
                WakeAccessKeyStore.delete()
                hasKey = false
                listener.setupChanged()
            }
        } else {
            SecureField("Picovoice AccessKey", text: $keyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("settings.heyDoddy.accessKey")
            Button("Save AccessKey") { saveKey() }
                .disabled(keyDraft.allSatisfy(\.isWhitespace))
        }
        if hasFile {
            StatusRow(title: "Keyword file", value: fileName ?? "Added")
            Button("Remove keyword file", role: .destructive) {
                WakeKeywordStore.delete()
                hasFile = false
                fileName = nil
                listener.setupChanged()
            }
        } else {
            Button("Choose the \u{201C}Hey Doddy\u{201D} keyword file (.ppn)") { choosingFile = true }
                .accessibilityIdentifier("settings.heyDoddy.chooseFile")
        }
        Link("Open the Picovoice Console", destination: URL(string: "https://console.picovoice.ai/")!)
    }

    private var explanation: String {
        "When you say \u{201C}Hey Doddy\u{201D}, a conversation starts and the Dynamic Island says \u{201C}\(greeting)\u{201D} (the name comes from Doddy's personality, then About you). "
            + (oneTap
                ? "Sign in once with Apple by tapping Talk to Doddy first. Then turn this on and allow the microphone; Doddy gets the wake word key using your protected voice session and keeps it on this iPhone. "
                : "To set it up, make a free Picovoice account, copy your AccessKey, and train the wake phrase \u{201C}Hey Doddy\u{201D} for iOS in English; download the .ppn file to this iPhone and choose it here. ")
            + "The microphone can only start while Doddy is open. It then keeps listening when you leave the app, with iOS's orange microphone dot and the island showing, until you tap Stop listening on the island, turn this off, Low Power Mode comes on, a call or another app takes the microphone, or iOS closes Doddy. After a restart, open Doddy again. "
            + "It listens on this iPhone; what it hears isn't kept or sent. Picovoice gets the AccessKey to check it. Only after the wake word does sound go to ElevenLabs, or OpenAI if you switch Home's voice to it, as when you tap Talk. "
            + "It uses battery, and it can wake up by mistake (TV, similar words): a conversation that hears nothing from you ends after \(Int(WakeGate.silentWakeTimeout)) seconds, and after \(WakeGate.maxWakeUpsPerHour) wake-ups in an hour it rests until the hour has passed. Each conversation counts toward the OpenAI or ElevenLabs usage."
    }

    private func saveKey() {
        problem = nil
        guard let key = WakeAccessKey.clean(keyDraft) else {
            problem = "That doesn't look like a Picovoice AccessKey. Copy it again from the Picovoice Console."
            return
        }
        guard WakeAccessKeyStore.save(key) else {
            problem = "The AccessKey wasn't saved. Try again."
            return
        }
        keyDraft = ""
        hasKey = true
        listener.setupChanged()
    }

    private func importFile(_ result: Result<URL, Error>) {
        problem = nil
        switch result {
        case .success(let url):
            do throws(WakeKeywordStore.ImportError) {
                try WakeKeywordStore.importFile(from: url)
                hasFile = true
                fileName = WakeKeywordStore.importedName
                listener.setupChanged()
            } catch {
                problem = error.message
            }
        case .failure:
            problem = WakeKeywordStore.ImportError.unreadable.message
        }
    }
}
