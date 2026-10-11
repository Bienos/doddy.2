import DoddyCore
import SwiftUI
import Translation

/// Translate text without internet (ADR-346). On iOS 18 and later, Apple's on-device translation;
/// iOS asks to download a language pair the first time. Nothing is sent to Doddy or ElevenLabs,
/// and nothing is kept: the text is gone when the screen closes.
struct TextTranslateScreen: View {
    var body: some View {
        if #available(iOS 18.0, *) {
            TextTranslateView()
        } else {
            ContentUnavailableView {
                Label("Needs iOS 18", systemImage: "translate")
            } description: {
                Text("Translating text on the iPhone without internet needs iOS 18 or later.")
            }
        }
    }
}

@available(iOS 18.0, *)
private struct TextTranslateView: View {
    @State private var source = VoiceSessionController.ownerLanguage.code
    @State private var target = TextTranslation.defaultTarget(for: VoiceSessionController.ownerLanguage.code)
    @State private var text = ""
    @State private var result: String?
    @State private var problem: String?
    @State private var configuration: TranslationSession.Configuration?
    @State private var pending: String?

    private var languages: [TranslatorLanguage] { TextTranslation.languages(first: VoiceSessionController.ownerLanguage.code) }

    var body: some View {
        Form {
            Section {
                Picker("Translate from", selection: $source) {
                    ForEach(languages) { Text($0.label).tag($0.code) }
                }
                Button {
                    (source, target) = (target, source)
                    if let result { text = result; self.result = nil }
                } label: {
                    Label("Swap languages", systemImage: "arrow.up.arrow.down")
                }
                .frame(minHeight: 44)
                Picker("Translate into", selection: $target) {
                    ForEach(languages) { Text($0.label).tag($0.code) }
                }
            }
            Section {
                TextField("Type or paste text", text: $text, axis: .vertical)
                    .lineLimit(3...10)
                    .accessibilityIdentifier("translateText.input")
                Button("Translate") { Task { await translate() } }
                    .frame(minHeight: 44)
                    .disabled(text.allSatisfy(\.isWhitespace))
                    .accessibilityIdentifier("translateText.go")
            }
            if let result {
                Section("Translation") {
                    Text(result).textSelection(.enabled)
                    Button { UIPasteboard.general.string = result } label: { Label("Copy", systemImage: "doc.on.doc") }
                        .frame(minHeight: 44)
                }
            }
            if let problem { Section { Text(problem).foregroundStyle(Theme.error) } }
            Section {
                Text("Translated by Apple on this iPhone, so it works without internet once iOS has downloaded the two languages. It may contain mistakes; for anything important, check with a person. Nothing is sent to Doddy and nothing is kept.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
        .navigationTitle("Translate text")
        .translationTask(configuration) { session in
            guard let line = pending else { return }
            pending = nil
            do {
                let response = try await session.translate(line)
                result = response.targetText
                problem = nil
            } catch {
                problem = NSLocalizedString("iOS couldn't translate it. If it asked to download languages, try again once they're downloaded.", comment: "")
            }
        }
    }

    private func translate() async {
        switch TextTranslation.check(text, from: source, to: target) {
        case .failure(.empty): return
        case .failure(.tooLong):
            problem = String(format: NSLocalizedString("Keep it under %lld characters.", comment: ""), TextTranslation.maxLength)
        case .failure(.sameLanguage):
            problem = NSLocalizedString("Pick two different languages.", comment: "")
        case .success(let line):
            let from = Locale.Language(identifier: source), to = Locale.Language(identifier: target)
            if await LanguageAvailability().status(from: from, to: to) == .unsupported {
                problem = NSLocalizedString("Apple's on-device translation doesn't offer this pair yet. Doddy's voice translator can do it when you're online.", comment: "")
                return
            }
            result = nil
            problem = nil
            pending = line
            if configuration?.source == from, configuration?.target == to {
                configuration?.invalidate()
            } else {
                configuration = TranslationSession.Configuration(source: from, target: to)
            }
        }
    }
}
