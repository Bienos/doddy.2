import Foundation

/// One message in Doddy's Messages thread (owner, 22 Oct 2026, ADR-582): the chat inside the app,
/// like a normal phone's messages. Doddy writes to the user and the user writes to Doddy; Doddy
/// also sends things there: files he made and infographics. Everything is kept on this iPhone.
public struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    public enum Sender: String, Codable, Sendable {
        case user, doddy
    }

    public enum Content: Codable, Equatable, Sendable {
        case text(String)
        case file(ChatFile)
        case infographic(ChatInfographic)
        /// A document made somewhere else (Claude's files, ADR-564): only its address is kept;
        /// nothing is downloaded to this iPhone.
        case link(ChatLink)
    }

    public let id: UUID
    public let sentAt: Date
    public let sender: Sender
    public let content: Content

    public init(id: UUID = UUID(), sentAt: Date = Date(), sender: Sender, content: Content) {
        self.id = id
        // Kept to whole seconds: the file stores the time as ISO 8601 without fractions, and the
        // read-back that proves a message was kept compares the whole message (ChatLogFile).
        self.sentAt = Date(timeIntervalSince1970: sentAt.timeIntervalSince1970.rounded(.down))
        self.sender = sender
        self.content = content
    }

    /// The words of a text message; nil for a file or an infographic.
    public var text: String? {
        if case .text(let text) = content { return text }
        return nil
    }
}

/// A file Doddy made (a presentation, a document, a sheet, a PDF) or the user attached. The file
/// itself lives next to the thread; `relativePath` is inside that folder, never absolute.
public struct ChatFile: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case presentation, document, spreadsheet, pdf, image, other
    }

    public let name: String
    public let kind: Kind
    public let bytes: Int
    public let relativePath: String

    public init(name: String, kind: Kind, bytes: Int, relativePath: String) {
        self.name = name
        self.kind = kind
        self.bytes = bytes
        self.relativePath = relativePath
    }

    /// The kind a file name's extension says, for files that arrive with only a name.
    public static func kind(forFileName name: String) -> Kind {
        switch (name as NSString).pathExtension.lowercased() {
        case "pptx", "ppt", "key": .presentation
        case "docx", "doc", "pages", "txt", "md": .document
        case "xlsx", "xls", "csv", "numbers": .spreadsheet
        case "pdf": .pdf
        case "png", "jpg", "jpeg", "heic", "gif": .image
        default: .other
        }
    }
}

/// A link to a document Claude is making or made (ADR-564, ADR-594). It opens in the browser.
public struct ChatLink: Codable, Equatable, Sendable {
    public let title: String
    /// "deck", "doc", "spreadsheet", "pdf" or "text", as the server named it.
    public let kind: String
    public let url: URL

    public init(title: String, kind: String, url: URL) {
        self.title = title
        self.kind = kind
        self.url = url
    }
}

/// An infographic Doddy drew from numbers he was given: a title, a headline figure and bars.
/// Every value shown is a figure the sender supplied; the app only lays them out.
public struct ChatInfographic: Codable, Equatable, Sendable {
    public struct Row: Codable, Equatable, Sendable {
        public let label: String
        /// For the bar's length only.
        public let value: Double
        /// What is written beside the bar, exactly as given ("820 zł").
        public let display: String

        public init(label: String, value: Double, display: String) {
            self.label = label
            self.value = value
            self.display = display
        }
    }

    public let title: String
    public let headline: String
    public let rows: [Row]
    public let footnote: String?

    public init(title: String, headline: String, rows: [Row], footnote: String? = nil) {
        self.title = title
        self.headline = headline
        self.rows = rows
        self.footnote = footnote
    }

    /// One day of steps from Motion & Fitness (ADR-568), as a card (ADR-594). Every figure is the
    /// number the iPhone reported; only its layout and thousands spacing are the app's. No bars:
    /// steps, distance and floors are different units, so none is drawn against another.
    public static func steps(
        _ totals: StepTotals, dayName: String, stepsWord: String, distanceLabel: String, floorsLabel: String, source: String
    ) -> ChatInfographic {
        var rows: [Row] = []
        if let meters = totals.distanceMeters {
            let tens = (meters / 10).rounded() * 10
            rows.append(Row(label: distanceLabel, value: 0, display: tens >= 1000 ? String(format: "%.1f km", tens / 1000) : "\(Int(tens)) m"))
        }
        if let floors = totals.floorsUp { rows.append(Row(label: floorsLabel, value: 0, display: "\(floors)")) }
        return ChatInfographic(title: dayName, headline: "\(spaced(totals.steps)) \(stepsWord)", rows: rows, footnote: source)
    }

    /// 6240 becomes "6 240" (a no-break space), as the Polish card reads it.
    static func spaced(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0, i % 3 == 0 { out.append("\u{00A0}") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }

    /// Each bar's share of the longest, 0 to 1, in order. Negative or empty data gives zeros.
    public var barFractions: [Double] {
        let longest = rows.map { max(0, $0.value) }.max() ?? 0
        guard longest > 0 else { return rows.map { _ in 0 } }
        return rows.map { max(0, $0.value) / longest }
    }
}
