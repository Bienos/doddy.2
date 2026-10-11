import Foundation

// Importing notes (ADR-231). The user picks files in the Files app: the notes Google Keep exports
// through Google Takeout (one JSON file per note) or plain text and Markdown files. Each becomes
// a candidate shown in full on a review screen; nothing is saved until the user taps Import, and
// only the candidates they keep ticked. The words are kept exactly as in the file (Keep's title
// goes above its text, with a blank line). Keep checklists become Doddy lists, ticked items stay
// ticked. Imported notes are marked "Imported from a file" and dated only when the file says
// when the note was made. Photos, recordings and labels in a Keep note are not imported, and the
// screen says so. Nothing is read from the internet; the files are read once, on this iPhone.

public enum NoteImport {
    /// Files larger than this are refused before they are read.
    public static let maxFileBytes = 2 * 1024 * 1024
    /// At most this many files at once.
    public static let maxFiles = 1_000

    public enum Origin: String, Equatable, Sendable {
        case googleKeep
        case textFile
    }

    public struct ListPart: Equatable, Sendable {
        public let name: String
        public let open: [String]
        public let ticked: [String]

        public init(name: String, open: [String], ticked: [String]) {
            self.name = name
            self.open = open
            self.ticked = ticked
        }

        public var count: Int { open.count + ticked.count }
    }

    public enum Content: Equatable, Sendable {
        case note(String)
        case list(ListPart)
    }

    /// Why a candidate can't be imported (or is unticked to start with, for `alreadySaved`).
    public enum Problem: Equatable, Sendable {
        case unreadable
        case notAKeepNote
        case notText
        case fileTooLarge
        case empty
        case inTrash
        case tooLong(length: Int)
        case listNameTooLong
        case tooManyItems
        case listNameTaken(String)
        /// The same words are already a note in Doddy, or earlier in this import.
        case alreadySaved
    }

    public struct Candidate: Equatable, Identifiable, Sendable {
        public let id: UUID
        public let fileName: String
        public let origin: Origin
        public let content: Content?
        /// When the note was made, as the file says. Nil when it doesn't say.
        public let createdAt: Date?
        public let problem: Problem?
        /// What the file had that isn't imported, e.g. "2 attachments", "labels".
        public let leftOut: [String]

        public init(
            id: UUID = UUID(), fileName: String, origin: Origin, content: Content?, createdAt: Date?,
            problem: Problem?, leftOut: [String] = []
        ) {
            self.id = id
            self.fileName = fileName
            self.origin = origin
            self.content = content
            self.createdAt = createdAt
            self.problem = problem
            self.leftOut = leftOut
        }

        /// Can be ticked on the review screen. A note already in Doddy can, but starts unticked.
        public var canImport: Bool { content != nil && (problem == nil || problem == .alreadySaved) }
        /// Ticked when the review screen opens.
        public var startsTicked: Bool { content != nil && problem == nil }

        func with(problem: Problem?) -> Candidate {
            Candidate(id: id, fileName: fileName, origin: origin, content: content, createdAt: createdAt, problem: problem, leftOut: leftOut)
        }
    }

    public static func isTextFile(_ fileName: String) -> Bool {
        ["txt", "md", "markdown", "text"].contains((fileName as NSString).pathExtension.lowercased())
    }

    public static func isKeepFile(_ fileName: String) -> Bool {
        (fileName as NSString).pathExtension.lowercased() == "json"
    }

    /// One picked file. A text file is one note, or one note per paragraph if asked.
    public static func read(fileName: String, data: Data, splitParagraphs: Bool = false) -> [Candidate] {
        if data.count > maxFileBytes {
            return [Candidate(fileName: fileName, origin: isKeepFile(fileName) ? .googleKeep : .textFile, content: nil, createdAt: nil, problem: .fileTooLarge)]
        }
        if isKeepFile(fileName) { return [keep(data, fileName: fileName)] }
        return text(data, fileName: fileName, splitParagraphs: splitParagraphs)
    }

    // MARK: Google Keep (Takeout)

    private struct KeepNote: Decodable {
        struct Item: Decodable {
            let text: String?
            let isChecked: Bool?
        }
        struct Label: Decodable { let name: String? }
        struct Attachment: Decodable { let filePath: String? }

        let title: String?
        let textContent: String?
        let listContent: [Item]?
        let isTrashed: Bool?
        let createdTimestampUsec: Int64?
        let labels: [Label]?
        let attachments: [Attachment]?
    }

    public static func keep(_ data: Data, fileName: String) -> Candidate {
        guard let note = try? JSONDecoder().decode(KeepNote.self, from: data),
              note.textContent != nil || note.listContent != nil || note.title != nil else {
            return Candidate(fileName: fileName, origin: .googleKeep, content: nil, createdAt: nil, problem: .notAKeepNote)
        }
        var leftOut: [String] = []
        if let count = note.attachments?.count, count > 0 { leftOut.append(count == 1 ? "1 attachment" : "\(count) attachments") }
        if note.labels?.isEmpty == false { leftOut.append("labels") }
        let created = note.createdTimestampUsec.flatMap { $0 > 0 ? Date(timeIntervalSince1970: Double($0) / 1_000_000) : nil }
        let title = (note.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let content: Content
        if let items = note.listContent {
            let open = items.filter { $0.isChecked != true }.compactMap { $0.text.flatMap(ListText.cleaned) }
            let ticked = items.filter { $0.isChecked == true }.compactMap { $0.text.flatMap(ListText.cleaned) }
            if title.isEmpty {
                // A checklist with no title can't be a list without a made-up name: it comes in as
                // a note, one item per line, ticked items marked ✓, shown on the review screen.
                content = .note((open + ticked.map { "✓ " + $0 }).joined(separator: "\n"))
            } else {
                content = .list(ListPart(name: title, open: open, ticked: ticked))
            }
        } else {
            let body = (note.textContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            content = .note([title, body].filter { !$0.isEmpty }.joined(separator: "\n\n"))
        }
        let candidate = Candidate(fileName: fileName, origin: .googleKeep, content: content, createdAt: created, problem: nil, leftOut: leftOut)
        if note.isTrashed == true { return candidate.with(problem: .inTrash) }
        return candidate.with(problem: problem(for: content))
    }

    // MARK: Text and Markdown files

    public static func text(_ data: Data, fileName: String, splitParagraphs: Bool) -> [Candidate] {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        guard let text = String(data: bytes, encoding: .utf8) else {
            return [Candidate(fileName: fileName, origin: .textFile, content: nil, createdAt: nil, problem: .notText)]
        }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = splitParagraphs ? paragraphs(normalized) : [normalized.trimmingCharacters(in: .whitespacesAndNewlines)]
        let notes = parts.filter { !$0.isEmpty }
        guard !notes.isEmpty else {
            return [Candidate(fileName: fileName, origin: .textFile, content: nil, createdAt: nil, problem: .empty)]
        }
        return notes.map { note in
            Candidate(fileName: fileName, origin: .textFile, content: .note(note), createdAt: nil, problem: problem(for: .note(note)))
        }
    }

    /// Paragraphs are separated by one or more blank lines.
    static func paragraphs(_ text: String) -> [String] {
        var result: [String] = [], current: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.allSatisfy(\.isWhitespace) {
                if !current.isEmpty { result.append(current.joined(separator: "\n")) }
                current = []
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { result.append(current.joined(separator: "\n")) }
        return result.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func problem(for content: Content) -> Problem? {
        switch content {
        case .note(let text):
            do { try MemoryTextValidator.validate(text) } catch {
                if case .tooLong(let length, _) = error { return .tooLong(length: length) }
                return .empty
            }
            return nil
        case .list(let list):
            if list.name.count > ListLimits.nameLength { return .listNameTooLong }
            if list.count > ListLimits.itemsPerList || (list.open + list.ticked).contains(where: { !ListText.fitsItemLength($0) }) {
                return .tooManyItems
            }
            return nil
        }
    }

    // MARK: Checking against what's saved

    /// Notes already in Doddy (or earlier in this import) are marked `alreadySaved` and start
    /// unticked; a list whose name is taken can't be imported.
    public static func checked(_ candidates: [Candidate], notes: [MemoryRecord], listNames: [String]) -> [Candidate] {
        var seenNotes = Set(notes.filter { $0.source != .sampleFixture }.flatMap { [DuplicateNote.key($0.currentText), DuplicateNote.key($0.rawText)] })
        var seenLists = Set(listNames.map(ListMatch.key))
        return candidates.map { candidate in
            guard candidate.problem == nil, let content = candidate.content else { return candidate }
            switch content {
            case .note(let text):
                let key = DuplicateNote.key(text)
                if !key.isEmpty, seenNotes.contains(key) { return candidate.with(problem: .alreadySaved) }
                seenNotes.insert(key)
            case .list(let list):
                let key = ListMatch.key(list.name)
                if seenLists.contains(key) { return candidate.with(problem: .listNameTaken(list.name)) }
                seenLists.insert(key)
            }
            return candidate
        }
    }

    /// The note to save, exactly as reviewed. A creation date in the future is dropped.
    public static func record(for candidate: Candidate, now: Date) -> MemoryRecord? {
        guard candidate.canImport, case .note(let text)? = candidate.content else { return nil }
        let date = candidate.createdAt.flatMap { $0 <= now ? $0 : nil }
        return try? MemoryRecord(id: UUID(), rawText: text, source: .importedFile, capturedAt: date)
    }

    /// "12 notes and 2 lists", for the button and the receipt.
    public static func summary(notes: Int, lists: Int) -> String {
        let n = notes == 1 ? "1 note" : "\(notes) notes"
        let l = lists == 1 ? "1 list" : "\(lists) lists"
        switch (notes, lists) {
        case (_, 0): return n
        case (0, _): return l
        default: return "\(n) and \(l)"
        }
    }
}
