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

    @State private var preview = VoicePreviewPlayer()

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
                NavigationLink {
                    VoiceChoiceView(voiceRaw: $voiceRaw, speed: voiceStyle.speed, preview: preview)
                } label: {
                    StatusRow(title: "Voice", value: Self.name(voiceStyle.voice))
                }
                .accessibilityIdentifier("settings.voice.choice")
                Picker("Speed", selection: $speedRaw) {
                    ForEach(SpeakingSpeed.allCases, id: \.self) { Text(Self.label($0)).tag($0.rawValue) }
                }
                Picker("Expressiveness", selection: $expressivenessRaw) {
                    ForEach(Expressiveness.allCases, id: \.self) { Text(Self.label($0)).tag($0.rawValue) }
                }
                Button {
                    preview.toggle(voiceStyle)
                } label: {
                    Label(
                        preview.playing == voiceStyle.voice ? "Stop sample" : "Hear \(Self.name(voiceStyle.voice))",
                        systemImage: preview.playing == voiceStyle.voice ? "stop.circle.fill" : "play.circle.fill")
                }
                .accessibilityIdentifier("settings.voice.preview")
                if let problem = preview.problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.error)
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
                Text("Applies from your next voice conversation. The sample is Doddy's hello in English and Polish at your speed; expressiveness is only heard in a conversation. All voices speak both languages; Wiktor is a native Polish speaker. Voices are candidates while Doddy's final voice is chosen.")
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
        .onChange(of: speedRaw) { _, _ in preview.stop() }
        .onDisappear { preview.stop() }
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
        case .wiktor: "Warm and engaging"
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

/// Settings → Voice and personality → Voice. Each row has a play button for that voice's bundled
/// sample (at the chosen speed) and selects the voice when tapped (ADR-122).
struct VoiceChoiceView: View {
    @Binding var voiceRaw: String
    let speed: SpeakingSpeed
    let preview: VoicePreviewPlayer

    private var selected: VoiceChoice { VoiceChoice(rawValue: voiceRaw) ?? .doddy }

    var body: some View {
        List {
            Section {
                ForEach(VoiceChoice.allCases, id: \.self) { choice in
                    row(choice)
                }
            } footer: {
                Text("Tap a face to hear Doddy's hello in that voice, in English and Polish. All voices speak both; Wiktor is a native Polish speaker. Your choice applies from the next conversation.")
            }
            if let problem = preview.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.error)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { preview.stop() }
    }

    private func row(_ choice: VoiceChoice) -> some View {
        let isPlaying = preview.playing == choice
        let name = PersonalityView.name(choice)
        return HStack(spacing: 14) {
            Button {
                preview.toggle(VoiceStyle(voice: choice, speed: speed, expressiveness: .natural))
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Text(String(name.prefix(1)))
                        .font(.title3.bold())
                        .foregroundStyle(Theme.ink)
                        .frame(width: 52, height: 52)
                        .background(choice == .doddy ? Theme.orangeCue : Theme.quietSurface, in: Circle())
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isPlaying ? Theme.ink : Theme.canvas)
                        .frame(width: 24, height: 24)
                        .background(isPlaying ? Theme.orangeCue : Theme.ink, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.canvas, lineWidth: 2))
                        .offset(x: 3, y: 3)
                }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isPlaying ? "Stop \(name) sample" : "Play \(name) sample")
            .accessibilityIdentifier("settings.voice.play.\(choice.rawValue)")

            Button {
                voiceRaw = choice.rawValue
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(name).font(.headline).foregroundStyle(Theme.ink)
                            if choice == .doddy {
                                Text("Default").font(.caption.weight(.semibold)).foregroundStyle(Theme.accentText)
                            } else if choice == .wiktor {
                                Text("Polish native").font(.caption.weight(.semibold)).foregroundStyle(Theme.accentText)
                            }
                        }
                        Text(isPlaying ? "Playing sample…" : PersonalityView.detail(choice))
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    if choice == selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.ink)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityAddTraits(choice == selected ? .isSelected : [])
            .accessibilityIdentifier("settings.voice.select.\(choice.rawValue)")
        }
        .padding(.vertical, 6)
    }
}
