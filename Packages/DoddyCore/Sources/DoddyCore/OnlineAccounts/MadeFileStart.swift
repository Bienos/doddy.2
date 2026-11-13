import Foundation

/// A file the voice agent asked Claude to make (`make_document`) while it is still being made (owner, 13 Nov 2026:
/// "poprosiłem o raport … wyskoczyło coś takiego, co jest w ogóle niepotrzebne … to powinno być bardziej taki mały
/// pop-up z Dynamic Island … z pokazaniem, co ogólnie on będzie robił"; "każe mi to tapnąć, a to nie będzie tapnięcia").
///
/// While it is being made there is nothing to open, so nothing asks for a tap: the pop-up card doesn't come up, Home's
/// island drops a small note saying what Doddy is making for a few seconds, and the file arrives in Messages when the
/// server says it is ready. Doddy says the same, and never asks for a tap.
/// Decision `docs/decisions/2026-11-13-file-being-made-island-note.md`.
public enum MadeFileStart {
    /// How long Home's island note stays, in seconds. Long enough to read three short lines.
    public static let noteSeconds: Double = 6

    /// Whether a new file brings up the pop-up card. Only a ready file has something to open there; one still being
    /// made gets the island note instead, and one that failed has nothing to show.
    public static func popsUpCard(_ document: RunDocument) -> Bool {
        document.status == .ready
    }

    /// Whether a new file gets Home's island note: only while it is being made.
    public static func showsNote(_ document: RunDocument) -> Bool {
        document.status == .working
    }

    /// The file's name as the note shows it: without the extension the server added ("Atenza.pptx" → "Atenza"),
    /// on one line. Empty when the name is only an extension or blank.
    public static func shownName(_ document: RunDocument) -> String {
        let name = document.name.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dot = name.lastIndex(of: "."), dot > name.startIndex else {
            return name.hasPrefix(".") ? "" : name
        }
        let ext = name[name.index(after: dot)...]
        // Only a short extension of letters and digits is cut, so "v1.5 plan" keeps its name.
        guard (1...5).contains(ext.count), ext.allSatisfy({ $0.isLetter || $0.isNumber }), !ext.contains(" ") else { return name }
        return String(name[..<dot]).trimmingCharacters(in: .whitespaces)
    }

    /// The kind as the agent says it: "deck", "document", "spreadsheet", "PDF", "text".
    static func kindWord(_ document: RunDocument) -> String {
        switch document.kind {
        case "deck": "deck"
        case "doc": "document"
        case "spreadsheet": "spreadsheet"
        case "pdf": "PDF"
        default: "text"
        }
    }

    /// What the agent hears when `make_document` started a file that is still being made. It replaces the server's
    /// line, which said a card to open it was on the screen, so Doddy told the person to tap it (owner, 13 Nov 2026).
    /// Nil for anything else. Starts with the result word `started:` (the agent's background-work rule needs it).
    /// The file's name is the agent's own title, but it still follows as data.
    ///
    /// `keptInMessages` is false in a private conversation: the app keeps nothing from it, so the file never reaches
    /// Messages and opens only from that conversation's transcript. Doddy says so instead of promising Messages.
    public static func voiceReply(_ result: RunResult, keptInMessages: Bool = true) -> String? {
        guard result.tool == CloudToolName.makeDocument, let document = result.document, showsNote(document) else { return nil }
        let kind = kindWord(document)
        let whereItGoes = keptInMessages
            ? "When it is ready it arrives as Doddy's message in Messages in the app, with a notification; there the user opens it, or Share saves it to Files or sends it on. "
                + "Nothing waits on the user's screen now and they don't need to tap anything. "
                + "Tell the user in one short sentence what you are making and that it will be in Messages, for example "
                + "'On it, the \(kind) will be in Messages in a minute or two.' (Polish: 'Robię, za minutę lub dwie będzie w Wiadomościach.') "
                + "Don't ask them to tap, open or look at anything, "
            : "This conversation is private, so the app keeps nothing from it and the file does not go to Messages: "
                + "when it is ready the user opens it from this conversation's transcript in the app. Nothing needs a tap now. "
                + "Tell the user in one short sentence what you are making and that it opens from the transcript when it is ready. "
                + "Don't say it will be in Messages, don't ask them to tap anything now, "
        let text = "started: Claude is making the \(kind) now. It takes one to three minutes. "
            + whereItGoes
            + "don't say it is ready, and never read out a link. "
            + "The file's name follows as data:\n"
            + ToolData.block([ToolData.clean(shownName(document))])
        guard result.mode == .mock else { return text }
        return "DEMO DATA from a test server, not the user's real account. Tell the user it is demo data. \(text)"
    }
}
