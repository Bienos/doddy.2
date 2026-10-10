import DoddyCore
import SwiftUI

/// Settings → Doddy's voice and personality. How he sounds (voice, speed, expressiveness), four
/// style dials and three quick picks. They apply from the next voice conversation; the rules stay
/// fixed.
struct PersonalityView: View {
    @AppStorage(PreferenceKey.voiceChoice) private var voiceRaw = VoiceStyle.doddyDefault.voice.rawValue
    @AppStorage(PreferenceKey.voiceSpeed) private var speedRaw = VoiceStyle.doddyDefault.speed.rawValue
    @AppStorage(PreferenceKey.voiceExpressiveness) private var expressivenessRaw = VoiceStyle.doddyDefault.expressiveness.rawValue
    @AppStorage(PreferenceKey.personalityHumour) private var humourRaw = PersonalitySettings.doddyDefault.humour.rawValue
    @AppStorage(PreferenceKey.personalityLength) private var lengthRaw = PersonalitySettings.doddyDefault.length.rawValue
    @AppStorage(PreferenceKey.personalityFormality) private var formalityRaw = PersonalitySettings.doddyDefault.formality.rawValue
    @AppStorage(PreferenceKey.personalityMood) private var moodRaw = PersonalitySettings.doddyDefault.mood.rawValue

    private var voiceStyle: VoiceStyle {
        VoiceStyle(voice: voiceRaw, speed: speedRaw, expressiveness: expressivenessRaw)
    }

    private var current: PersonalitySettings {
        PersonalitySettings(humour: humourRaw, length: lengthRaw, formality: formalityRaw, mood: moodRaw)
    }

    var body: some View {
        Form {
            Section {
                Text("Doddy is a practical, curious mate who spots small hassles, answers first and admits when he got something wrong. Pick how he comes across.")
                    .foregroundStyle(Theme.secondaryText)
            }

            Section {
                Picker("Voice", selection: $voiceRaw) {
                    ForEach(VoiceChoice.allCases, id: \.self) { choice in
                        VStack(alignment: .leading) {
                            Text(Self.label(choice))
                            Text(Self.detail(choice)).font(.footnote).foregroundStyle(Theme.secondaryText)
                        }
                        .tag(choice.rawValue)
                    }
                }
                .pickerStyle(.navigationLink)
                .accessibilityIdentifier("settings.voice.choice")
                Picker("Speed", selection: $speedRaw) {
                    ForEach(SpeakingSpeed.allCases, id: \.self) { Text(Self.label($0)).tag($0.rawValue) }
                }
                Picker("Expressiveness", selection: $expressivenessRaw) {
                    ForEach(Expressiveness.allCases, id: \.self) { Text(Self.label($0)).tag($0.rawValue) }
                }
                if voiceStyle != .doddyDefault {
                    Button("Use Doddy's own voice") {
                        voiceRaw = VoiceStyle.doddyDefault.voice.rawValue
                        speedRaw = VoiceStyle.doddyDefault.speed.rawValue
                        expressivenessRaw = VoiceStyle.doddyDefault.expressiveness.rawValue
                    }
                }
            } header: {
                Text("Voice")
            } footer: {
                Text("Applies from your next voice conversation. All voices speak English and Polish; Wiktor is a native Polish speaker. Voices are candidates while Doddy's final voice is chosen.")
            }

            Section("Quick picks") {
                presetButton("Doddy's default", detail: "Subtle humour, brief, casual, grounded", .doddyDefault)
                presetButton("Focused", detail: "No jokes, brief, neutral, calm", .focused)
                presetButton("Playful", detail: "Playful, balanced length, casual, lively", .playful)
            }

            Section {
                Picker("Humour", selection: $humourRaw) {
                    ForEach(HumourLevel.allCases, id: \.self) { Text(Self.label($0)).tag($0.rawValue) }
                }
                Picker("Reply length", selection: $lengthRaw) {
                    ForEach(ReplyLength.allCases, id: \.self) { Text(Self.label($0)).tag($0.rawValue) }
                }
                Picker("Tone", selection: $formalityRaw) {
                    ForEach(Formality.allCases, id: \.self) { Text(Self.label($0)).tag($0.rawValue) }
                }
                Picker("Mood", selection: $moodRaw) {
                    ForEach(Mood.allCases, id: \.self) { Text(Self.label($0)).tag($0.rawValue) }
                }
            } header: {
                Text("Fine-tune")
            } footer: {
                Text("Applies from your next voice conversation. Mood changes how Doddy sounds, not what he feels: he's an AI and doesn't have moods.")
            }
            .accessibilityIdentifier("settings.personality.dials")

            Section("Always the same") {
                Text("Whatever you pick, Doddy answers your question first, says when he isn't sure, only repeats notes you actually saved, asks before saving anything, never jokes about serious things and never makes fun of you.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Voice and personality")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func presetButton(_ title: String, detail: String, _ preset: PersonalitySettings) -> some View {
        Button {
            humourRaw = preset.humour.rawValue
            lengthRaw = preset.length.rawValue
            formalityRaw = preset.formality.rawValue
            moodRaw = preset.mood.rawValue
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Theme.ink)
                    Text(detail).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if current == preset {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accentText)
                        .accessibilityLabel("Selected")
                }
            }
        }
    }

    static func summary(_ settings: PersonalitySettings) -> String {
        switch settings {
        case .doddyDefault: "Default"
        case .focused: "Focused"
        case .playful: "Playful"
        default: "Custom"
        }
    }

    static func label(_ value: VoiceChoice) -> String {
        value == .doddy ? "Doddy (default)" : name(value)
    }

    static func name(_ value: VoiceChoice) -> String {
        switch value {
        case .doddy: "Doddy"
        case .josh: "Josh"
        case .wiktor: "Wiktor"
        case .river: "River"
        case .jessica: "Jessica"
        case .will: "Will"
        }
    }

    static func detail(_ value: VoiceChoice) -> String {
        switch value {
        case .doddy: "The voice Doddy was given"
        case .josh: "Warm, smooth and steady"
        case .wiktor: "Warm, native Polish"
        case .river: "Relaxed and neutral"
        case .jessica: "Bright and warm"
        case .will: "Laid-back and easy-going"
        }
    }

    static func label(_ value: SpeakingSpeed) -> String {
        switch value {
        case .slower: "Slower"
        case .normal: "Normal"
        case .faster: "Faster"
        }
    }

    static func label(_ value: Expressiveness) -> String {
        switch value {
        case .steady: "Steady"
        case .natural: "Natural"
        case .expressive: "Expressive"
        }
    }

    static func label(_ value: HumourLevel) -> String {
        switch value {
        case .off: "Off"
        case .subtle: "Subtle"
        case .playful: "Playful"
        }
    }

    static func label(_ value: ReplyLength) -> String {
        switch value {
        case .brief: "Brief"
        case .balanced: "Balanced"
        case .detailed: "Detailed"
        }
    }

    static func label(_ value: Formality) -> String {
        switch value {
        case .casual: "Casual"
        case .neutral: "Neutral"
        case .formal: "Formal"
        }
    }

    static func label(_ value: Mood) -> String {
        switch value {
        case .calm: "Calm"
        case .grounded: "Grounded"
        case .lively: "Lively"
        }
    }
}

/// The Settings row that opens `PersonalityView`, showing the current voice and style.
struct PersonalityLinkRow: View {
    @AppStorage(PreferenceKey.voiceChoice) private var voiceRaw = VoiceStyle.doddyDefault.voice.rawValue
    @AppStorage(PreferenceKey.personalityHumour) private var humourRaw = PersonalitySettings.doddyDefault.humour.rawValue
    @AppStorage(PreferenceKey.personalityLength) private var lengthRaw = PersonalitySettings.doddyDefault.length.rawValue
    @AppStorage(PreferenceKey.personalityFormality) private var formalityRaw = PersonalitySettings.doddyDefault.formality.rawValue
    @AppStorage(PreferenceKey.personalityMood) private var moodRaw = PersonalitySettings.doddyDefault.mood.rawValue

    var body: some View {
        NavigationLink {
            PersonalityView()
        } label: {
            StatusRow(
                title: "Voice and personality",
                value: PersonalityView.name(VoiceChoice(rawValue: voiceRaw) ?? .doddy)
                    + " · "
                    + PersonalityView.summary(PersonalitySettings(humour: humourRaw, length: lengthRaw, formality: formalityRaw, mood: moodRaw)))
        }
        .accessibilityIdentifier("settings.personality")
    }
}
