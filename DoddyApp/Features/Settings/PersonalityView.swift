import DoddyCore
import SwiftUI

// Settings › Voice and personality is one page (12 Nov 2026, decision `2026-11-12-settings-one-voice-page`): before,
// Settings › Voice opened a second page for these, and both were called "Voice". The page is `VoiceSettingsView`; these
// two views are the parts of it that are about how Doddy sounds and comes across. They apply from the next voice
// conversation; the rules stay fixed.

/// How he sounds in his one voice (speed and expressiveness; the voice itself is not a choice, decision
/// `2026-11-12-one-voice`), the language he starts in, and what he calls you.
struct VoiceStyleSections: View {
    @AppStorage(PreferenceKey.voiceSpeed) private var speedRaw = VoiceStyle.doddyDefault.speed.rawValue
    @AppStorage(PreferenceKey.voiceExpressiveness) private var expressivenessRaw = VoiceStyle.doddyDefault.expressiveness.rawValue
    @AppStorage(PreferenceKey.voiceLanguage) private var languageRaw = ConversationLanguage.default.rawValue
    @AppStorage(PreferenceKey.nickname) private var nickname = ""

    var body: some View {
        Group {
            Section {
                Picker("Speed", selection: $speedRaw) {
                    ForEach(SpeakingSpeed.allCases, id: \.self) { Text(PersonalitySections.label($0)).tag($0.rawValue) }
                }
                Picker("Expressiveness", selection: $expressivenessRaw) {
                    ForEach(Expressiveness.allCases, id: \.self) { Text(PersonalitySections.label($0)).tag($0.rawValue) }
                }
                Picker("Starts in", selection: $languageRaw) {
                    ForEach(ConversationLanguage.allCases, id: \.self) { Text(PersonalitySections.label($0)).tag($0.rawValue) }
                }
                .accessibilityIdentifier("settings.voice.language")
                Text("Doddy follows you if you switch language while you talk.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } header: {
                Text("Voice")
            } footer: {
                Text("Applies from your next voice conversation. \"Starts in\" sets the language Doddy greets you in; on Automatic he starts in English. Either way he follows whichever European language you speak, and switches when you do.")
            }

            Section {
                TextField("Your name or nickname", text: $nickname)
                    .textContentType(.nickname)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("settings.nickname")
                if !nickname.trimmingCharacters(in: .whitespaces).isEmpty && Nickname.clean(nickname) == nil {
                    Label(String(format: NSLocalizedString("Use letters only, up to %lld characters. Doddy won't use this until it's a plain name.", comment: ""), Nickname.maxLength),
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.error)
                }
            } header: {
                Text("What Doddy calls you")
            } footer: {
                Text("Optional. When set, it's sent to ElevenLabs with each voice conversation so Doddy can use it now and then. Leave it empty to send nothing.")
            }
        }
    }
}

/// How he comes across: three quick picks, four style dials and what never changes.
struct PersonalitySections: View {
    @AppStorage(PreferenceKey.personalityHumour) private var humourRaw = PersonalitySettings.doddyDefault.humour.rawValue
    @AppStorage(PreferenceKey.personalityLength) private var lengthRaw = PersonalitySettings.doddyDefault.length.rawValue
    @AppStorage(PreferenceKey.personalityFormality) private var formalityRaw = PersonalitySettings.doddyDefault.formality.rawValue
    @AppStorage(PreferenceKey.personalityMood) private var moodRaw = PersonalitySettings.doddyDefault.mood.rawValue

    private var current: PersonalitySettings {
        PersonalitySettings(humour: humourRaw, length: lengthRaw, formality: formalityRaw, mood: moodRaw)
    }

    var body: some View {
        Group {
            Section {
                presetButton("Doddy's default", detail: "Subtle humour, brief, casual, grounded", .doddyDefault)
                presetButton("Focused", detail: "No jokes, brief, neutral, calm", .focused)
                presetButton("Playful", detail: "Playful, balanced length, casual, lively", .playful)
            } header: {
                Text("How he comes across")
            } footer: {
                Text("Doddy is a practical, curious mate who spots small hassles, answers first and admits when he got something wrong. Pick how he comes across.")
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
                Text("Applies from your next voice conversation. Mood changes how Doddy sounds, not what he feels: he's a character and doesn't have moods.")
            }
            .accessibilityIdentifier("settings.personality.dials")

            Section("Always the same") {
                Text("Whatever you pick, Doddy answers your question first, says when he isn't sure, only repeats notes you actually saved, asks before saving anything, never jokes about serious things and never makes fun of you.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
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
        case .doddyDefault: NSLocalizedString("Default", comment: "")
        case .focused: NSLocalizedString("Focused", comment: "")
        case .playful: NSLocalizedString("Playful", comment: "")
        default: NSLocalizedString("Custom", comment: "")
        }
    }

    /// "Automatic", "English", or the language's own name with English after it: "Deutsch (German)".
    static func label(_ value: ConversationLanguage) -> String {
        guard let native = value.nativeName, let english = value.englishName else { return NSLocalizedString("Automatic", comment: "") }
        return native == english ? native : "\(native) (\(english))"
    }

    static func label(_ value: SpeakingSpeed) -> String {
        switch value {
        case .slower: NSLocalizedString("Slower", comment: "")
        case .normal: NSLocalizedString("Normal", comment: "")
        case .faster: NSLocalizedString("Faster", comment: "")
        }
    }

    static func label(_ value: Expressiveness) -> String {
        switch value {
        case .steady: NSLocalizedString("Steady", comment: "")
        case .natural: NSLocalizedString("Natural", comment: "")
        case .expressive: NSLocalizedString("Expressive", comment: "")
        }
    }

    static func label(_ value: HumourLevel) -> String {
        switch value {
        case .off: "Off"
        case .subtle: NSLocalizedString("Subtle", comment: "")
        case .playful: NSLocalizedString("Playful", comment: "")
        }
    }

    static func label(_ value: ReplyLength) -> String {
        switch value {
        case .brief: NSLocalizedString("Brief", comment: "")
        case .balanced: NSLocalizedString("Balanced", comment: "")
        case .detailed: NSLocalizedString("Detailed", comment: "")
        }
    }

    static func label(_ value: Formality) -> String {
        switch value {
        case .casual: NSLocalizedString("Casual", comment: "")
        case .neutral: NSLocalizedString("Neutral", comment: "")
        case .formal: NSLocalizedString("Formal", comment: "")
        }
    }

    static func label(_ value: Mood) -> String {
        switch value {
        case .calm: NSLocalizedString("Calm", comment: "")
        case .grounded: NSLocalizedString("Grounded", comment: "")
        case .lively: NSLocalizedString("Lively", comment: "")
        }
    }
}
