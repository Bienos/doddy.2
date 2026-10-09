import AppIntents
import DoddyCore

/// App Shortcuts: available in Siri, Spotlight and the Shortcuts app as soon as Doddy is
/// installed. Back Tap and the Action Button reach them through Shortcuts; Doddy can't assign
/// or inspect those settings.
struct DoddyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TalkToDoddyIntent(),
            phrases: ["Talk to \(.applicationName)", "Start talking to \(.applicationName)"],
            shortTitle: "Talk to Doddy",
            systemImageName: "waveform")
        AppShortcut(
            intent: SaveToDoddyIntent(),
            phrases: ["Save to \(.applicationName)", "Save a note in \(.applicationName)"],
            shortTitle: "Save to Doddy",
            systemImageName: "square.and.pencil")
        AppShortcut(
            intent: AskDoddyIntent(),
            phrases: ["Ask \(.applicationName)", "Search \(.applicationName)"],
            shortTitle: "Ask Doddy",
            systemImageName: "magnifyingglass")
    }
}

/// Saves exactly the given text. Runs without opening the app; "Saved" is reported only after
/// the store confirmed the committed write, otherwise Shortcuts shows the error.
struct SaveToDoddyIntent: AppIntent {
    static var title: LocalizedStringResource { "Save to Doddy" }
    static var description: IntentDescription {
        IntentDescription("Saves a note in Doddy on this iPhone, exactly as given. You can correct or delete it in the app.")
    }

    @Parameter(title: "Note", requestValueDialog: IntentDialog("What should Doddy keep?"))
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$text) to Doddy")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        do {
            // Recorded as typed text: the app receives text and can't tell whether Siri dictated it.
            let record = try await AppServices.store.save(text: text, category: .other)
            return .result(value: record.currentText, dialog: IntentDialog(stringLiteral: ShortcutReply.saved(record)))
        } catch {
            throw ShortcutFailure(message: UserFacingError.message(for: error))
        }
    }
}

/// Local lexical recall over saved notes. Reads back stored text only; no AI, nothing sent.
struct AskDoddyIntent: AppIntent {
    static var title: LocalizedStringResource { "Ask Doddy" }
    static var description: IntentDescription {
        IntentDescription("Looks through the notes you saved in Doddy and reads back the ones that match. It answers only from your saved notes.")
    }

    @Parameter(title: "Question", requestValueDialog: IntentDialog("What should I look for?"))
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Doddy about \(\.$question)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        do {
            let reply = ShortcutReply.ask(try await AppServices.store.recall(question))
            return .result(value: reply, dialog: IntentDialog(stringLiteral: reply))
        } catch {
            throw ShortcutFailure(message: UserFacingError.message(for: error))
        }
    }
}

/// Shown by Siri/Shortcuts when an intent fails.
struct ShortcutFailure: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }
}
