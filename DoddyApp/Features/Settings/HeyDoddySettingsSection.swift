import DoddyCore
import SwiftUI

/// Settings → "Hey Doddy" (ADR-254, ADR-472). Off unless turned on. There is nothing to bring: the
/// phrase is heard by Apple's speech recognition on this iPhone, so only the microphone and speech
/// recognition need allowing. The status line is the listener's own state, so it never says
/// "Listening" when it isn't.
struct HeyDoddySettingsSection: View {
    @AppStorage(PreferenceKey.heyDoddyOn) private var isOn = false
    @AppStorage(PreferenceKey.nickname) private var nickname = ""
    @Environment(ProfileStore.self) private var profiles
    @State private var listener = WakeWordListener.shared
    @State private var isWorking = false

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
            Text(explanation)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityIdentifier("settings.heyDoddy.note")
        } header: {
            Text("Hey Doddy")
        }
    }

    private var explanation: String {
        "When you say \u{201C}Hey Doddy\u{201D}, a conversation starts and the Dynamic Island says \u{201C}\(greeting)\u{201D} (the name comes from Doddy's personality, then About you). "
            + "Turn it on and allow the microphone and speech recognition; that's all. "
            + "The microphone can only start while Doddy is open. It then keeps listening when you leave the app, with iOS's orange microphone dot and the island showing, until you tap Stop listening on the island, turn this off, Low Power Mode comes on, a call or another app takes the microphone, or iOS closes Doddy. After a restart, open Doddy again. "
            + "Doddy hears the phrase with Apple's speech recognition on this iPhone; what it hears isn't kept or sent, and an iPhone that can't recognize English on the device doesn't listen at all rather than send sound to Apple. Only after the wake word does sound go to OpenAI, or ElevenLabs if you switch Home's voice to it, as when you tap Talk. "
            + "It uses battery, because speech recognition keeps running, and it can wake up by mistake (TV, similar words) or miss you: a conversation that hears nothing from you ends after \(Int(WakeGate.silentWakeTimeout)) seconds, and after \(WakeGate.maxWakeUpsPerHour) wake-ups in an hour it rests until the hour has passed. Each conversation counts toward the OpenAI or ElevenLabs usage."
    }
}
