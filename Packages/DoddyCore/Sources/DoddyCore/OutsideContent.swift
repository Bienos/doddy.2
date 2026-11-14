import Foundation

// Text from outside must not be able to steer the tools that run at once (DOD-07: a model proposes, typed code
// validates, scoped tools execute; tool, web, email and document content is data, never instructions).
//
// Since 11 Nov 2026 a handful of tools run with no card because the user asked for them (decision
// 2026-11-11-asked-for-runs-at-once). Most are harmless whatever the agent was told. A few can carry text out of
// the phone or spend money, and an email, a web page or a screen can be written to look like the user's own
// request. This file keeps one small fact per conversation, "text someone else wrote has reached it", and a pure
// rule that turns that fact into a card for exactly those tools. The baseline (`AskFirst.need(for:)`, which
// `voice-agent/tools.json` mirrors) is unchanged: this only ever makes a call ask, never lets one skip a card.

/// What one voice conversation has taken in from outside, and what the user said last. One value per
/// conversation: the app starts each conversation with a new one, so nothing carries over.
public struct OutsideContentSession: Equatable, Sendable {
    /// Longest stretch of the user's last line that is kept for matching.
    public static let maxUserWordsLength = 1_000

    /// An email, a page, a calendar, a file name, a task, the web, the news, places, flights, a leaflet, the
    /// result of an errand, a paid page, or what ElevenLabs reads out of Wikipedia or the weather service.
    public private(set) var otherContentSeen = false
    /// A look at the shared screen was answered: the screen shows other people's content.
    public private(set) var screenContentSeen = false
    /// A look at the screen has run in this conversation, so the person tapped for the first one (or it is
    /// still the first and nothing has run yet).
    public private(set) var screenLookApproved = false
    /// The user's own words, from the speech-to-text of their side of the conversation: only their last line.
    public private(set) var latestUserWords: String?

    public init() {}

    /// Any text from outside, the screen included.
    public var outsideContentSeen: Bool { otherContentSeen || screenContentSeen }

    /// True for a tool whose result is text somebody else wrote. A new online-account tool counts until
    /// someone decides it doesn't. Claude's own writing is not a source: what it was given as material was
    /// already counted when it came into the conversation.
    public static func isSource(_ tool: String) -> Bool {
        if tool == CloudToolName.askClaude || tool == CloudToolName.makeDocument { return false }
        if CloudToolName.all.contains(tool) || ToolCatalog.webLookups.contains(tool) { return true }
        return [VoiceToolName.checkErrands, VoiceToolName.findDeals, PaymentToolName.payForPage].contains(tool)
    }

    /// The app is about to run this tool: it has passed the switches and any card it needed. A source marks the
    /// conversation before its result can reach the agent. A look at the screen also marks the first look as
    /// done, because it only runs after a tap (or after an earlier one).
    public mutating func noteRun(of tool: String) {
        if tool == VoiceToolName.lookAtScreen {
            screenContentSeen = true
            screenLookApproved = true
        } else if Self.isSource(tool) {
            otherContentSeen = true
        }
    }

    /// The provider says the agent called a tool the provider runs itself (the weather and Wikipedia ones,
    /// `ToolCatalog.webLookups`). The app never sees what they return, only that they were called. Any other
    /// name is ignored here: the app notes its own tools when it runs them.
    public mutating func noteRunByProvider(_ tool: String) {
        if ToolCatalog.webLookups.contains(tool) { otherContentSeen = true }
    }

    /// The user's own words arrived (their final transcript). Silence is not a line.
    public mutating func userSaid(_ words: String) {
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        latestUserWords = String(trimmed.prefix(Self.maxUserWordsLength))
    }

    /// True when every item is made only of words the user said in their last line, compared as folded whole
    /// words (case, accents and punctuation don't matter; a number said as a word does not match a digit).
    /// An empty list, an item with no words in it, or no words said at all is never a match: asking is the
    /// safe answer.
    public func userSaidAll(_ items: [String]) -> Bool {
        guard let said = latestUserWords, !items.isEmpty else { return false }
        let spoken = Set(SearchFolding.tokens(said))
        return items.allSatisfy { item in
            let words = SearchFolding.tokens(item)
            return !words.isEmpty && words.allSatisfy(spoken.contains)
        }
    }
}

/// The tools the session rule can hold behind a card. Each one runs at once in the baseline.
public enum OutsideContentRule {
    public static let guardedTools: Set<String> = [
        VoiceToolName.textMe, VoiceToolName.lookAtScreen, VoiceToolName.addToList, VoiceToolName.checkOff,
        CloudToolName.askClaude, CloudToolName.makeDocument,
    ]
}

extension AskFirst {
    /// The ask for this call in this conversation: the baseline (`need(for:)`), then the session rule.
    /// - `text_me`, and `ask_claude` with text from the conversation as material: a tap once text from outside
    ///   has been seen.
    /// - `make_document`: a tap, with the whole brief on the card, once text from outside has been seen. Without
    ///   it a file is made at once, as the owner decided (`2026-11-13-file-being-made-island-note`).
    /// - `look_at_screen`: a tap for the first look in a conversation, and again for any look after text from
    ///   somewhere other than the screen has been seen.
    /// - `add_to_list` and `check_off` on a shared list (`listIsShared`, decided by the app from the list it
    ///   resolved): a tap with the exact items, unless every item is in what the user just said.
    /// A call that already asks keeps its ask. Nothing here runs anything: a tap is still answered through
    /// `AskLedger`, once, for exactly this request.
    public static func need(
        for request: VoiceToolRequest, in session: OutsideContentSession, listIsShared: Bool = false,
        calendar: Calendar = .current, polish: Bool = false
    ) -> Need {
        let baseline = need(for: request, calendar: calendar, polish: polish)
        guard baseline == .runsNow else { return baseline }
        switch request {
        case .textMe(let body):
            guard session.outsideContentSeen else { return baseline }
            return .tapFirst(OutsideContentAsk.textMeCard(body, polish: polish))
        case .cloudTool(let call) where call.name == CloudToolName.makeDocument:
            guard session.outsideContentSeen else { return baseline }
            return .tapFirst(OutsideContentAsk.makeDocumentCard(call, polish: polish))
        case .cloudTool(let call) where call.name == CloudToolName.askClaude:
            guard session.outsideContentSeen, OutsideContentAsk.material(of: call) != nil else { return baseline }
            return .tapFirst(OutsideContentAsk.askClaudeCard(call, polish: polish))
        case .lookAtScreen:
            guard !session.screenLookApproved || session.otherContentSeen else { return baseline }
            return .tapFirst(ScreenLookSpeech.askCard(polish: polish))
        case .addToList(let list), .checkOff(let list):
            guard listIsShared, !session.userSaidAll(list.items) else { return baseline }
            let adding: Bool
            if case .addToList = request { adding = true } else { adding = false }
            return .tapFirst(OutsideContentAsk.sharedListCard(list, adding: adding, polish: polish))
        default:
            return baseline
        }
    }
}

/// The cards the session rule shows. They carry exactly what would be sent or changed, in English or Polish
/// (the same lines in the same order), and only a tap answers them.
public enum OutsideContentAsk {
    /// How much of a text taken from the conversation is shown on a card; its full length is always said.
    public static let previewLength = 300

    /// The arguments' text, trimmed; nil when missing or blank.
    static func text(_ call: CloudToolCall, _ key: String) -> String? {
        guard case .string(let value)? = call.arguments[key] else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The text the agent copied from the conversation to work on, if any.
    static func material(of call: CloudToolCall) -> String? { text(call, "material") }

    private static func preview(_ text: String) -> String {
        let flat = ToolData.clean(text)
        return flat.count > previewLength ? String(flat.prefix(previewLength)) + "\u{2026}" : flat
    }

    private static func quoted(_ text: String, polish: Bool) -> String {
        polish ? "\u{201E}\(text)\u{201D}" : "\u{201C}\(text)\u{201D}"
    }

    private static func materialLine(_ material: String, polish: Bool) -> String {
        let count = material.count
        let body = quoted(preview(material), polish: polish)
        return polish
            ? "Tekst z tej rozmowy, \(count) znaków: \(body)"
            : "Text taken from this conversation, \(count) characters: \(body)"
    }

    private static func reason(polish: Bool) -> String {
        polish
            ? "Doddy czytał w tej rozmowie tekst z zewnątrz (e-mail, stronę lub Twój ekran), więc pyta najpierw. Sprawdź słowa."
            : "Doddy has read text from outside in this conversation (an email, a web page or your screen), so he asks first. Check the words."
    }

    public static func textMeCard(_ body: String, polish: Bool) -> AskCard {
        AskCard(
            title: polish ? "Wysłać ten SMS na Twój numer?" : "Text this to your own number?",
            lines: [
                quoted(body, polish: polish),
                polish
                    ? "Zostanie wysłany z numeru Doddy’ego tylko na Twój zweryfikowany numer."
                    : "It is sent from Doddy's number to your own verified number only.",
                reason(polish: polish),
            ],
            confirmLabel: polish ? "Wyślij" : "Send it")
    }

    public static func askClaudeCard(_ call: CloudToolCall, polish: Bool) -> AskCard {
        var lines: [String] = []
        if let request = text(call, "request") {
            lines.append((polish ? "Twoja prośba: " : "Your request: ") + quoted(preview(request), polish: polish))
        }
        if let material = material(of: call) { lines.append(materialLine(material, polish: polish)) }
        lines.append(polish
            ? "Trafia na serwer Doddy’ego i do Anthropic (Claude), który pisze odpowiedź."
            : "It goes to Doddy's server and to Anthropic (Claude), which writes the answer.")
        lines.append(reason(polish: polish))
        return AskCard(
            title: polish ? "Wysłać to do Claude?" : "Send this to Claude?", lines: lines,
            confirmLabel: polish ? "Tak, zapytaj Claude" : "Yes, ask Claude")
    }

    public static func makeDocumentCard(_ call: CloudToolCall, polish: Bool) -> AskCard {
        let kinds: [String: (en: String, pl: String)] = [
            "deck": ("Presentation", "Prezentacja"), "doc": ("Word document", "Dokument Word"),
            "spreadsheet": ("Excel sheet", "Arkusz Excel"), "pdf": ("PDF", "PDF"), "text": ("Text", "Tekst"),
        ]
        let said = text(call, "kind")
        let kind = said.flatMap { kinds[$0] }.map { polish ? $0.pl : $0.en } ?? said ?? (polish ? "Plik" : "File")
        var lines = [kind + (text(call, "title").map { ": " + quoted(preview($0), polish: polish) } ?? "")]
        if let request = text(call, "request") {
            lines.append((polish ? "Co ma zawierać: " : "What it should contain: ") + quoted(preview(request), polish: polish))
        }
        if let material = material(of: call) { lines.append(materialLine(material, polish: polish)) }
        lines.append(polish
            ? "Plik powstaje na serwerze Doddy’ego, z pomocą Anthropic (Claude); dostaniesz go, gdy będzie gotowy. Nic nie jest nikomu wysyłane."
            : "The file is made on Doddy's server with Anthropic (Claude), and you get it when it is ready. Nothing is sent to anyone.")
        return AskCard(
            title: polish ? "Przygotować ten plik?" : "Make this file?", lines: lines,
            confirmLabel: polish ? "Tak, przygotuj" : "Yes, make it")
    }

    public static func sharedListCard(_ request: ListVoiceRequest, adding: Bool, polish: Bool) -> AskCard {
        let name = quoted(request.list, polish: polish)
        let note = polish
            ? "Ta lista jest udostępniona: każdy, kto na niej jest, zobaczy zmianę."
            : "This list is shared: everyone on it sees the change."
        switch (adding, polish) {
        case (true, false): return AskCard(title: "Add to \(name), a shared list?", lines: request.items + [note], confirmLabel: "Add")
        case (true, true): return AskCard(title: "Dodać do udostępnionej listy \(name)?", lines: request.items + [note], confirmLabel: "Dodaj")
        case (false, false): return AskCard(title: "Tick off on \(name), a shared list?", lines: request.items + [note], confirmLabel: "Tick off")
        case (false, true): return AskCard(title: "Odhaczyć na udostępnionej liście \(name)?", lines: request.items + [note], confirmLabel: "Odhacz")
        }
    }
}
