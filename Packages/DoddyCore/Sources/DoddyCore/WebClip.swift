import Foundation

// A page, or a piece of one, clipped from Safari (ADR-353). The extension sends the page's title
// and address, and the text the user had selected if any. Nothing is read from the page unless the
// user clicks the button, and the page's other text is never taken. The clip becomes the words of
// a note waiting in the clip inbox (ADR-352); it is saved only after Save in the Mac app.

public struct WebClip: Equatable, Sendable {
    public static let maxTitle = 300
    public static let maxSelection = 10_000
    public static let maxAddress = 2_000

    /// One line, cleaned.
    public let title: String
    /// Only a web address (http or https with a host); empty otherwise.
    public let address: String
    /// What the user had selected, cleaned; empty when nothing was.
    public let selection: String

    /// Nil when there is nothing to keep: no selection, no title and no usable address.
    public init?(title: String?, address: String?, selection: String?) {
        let cleanTitle = String(ShareInboxItem.clean(title ?? "")
            .split(whereSeparator: \.isNewline).joined(separator: " ").prefix(Self.maxTitle))
        let cleanSelection = String(ShareInboxItem.clean(selection ?? "").prefix(Self.maxSelection))
        var cleanAddress = ShareInboxItem.clean(address ?? "")
        if cleanAddress.count > Self.maxAddress || !ShareInboxItem.isWebLink(cleanAddress) { cleanAddress = "" }
        guard !cleanTitle.isEmpty || !cleanSelection.isEmpty || !cleanAddress.isEmpty else { return nil }
        self.title = cleanTitle
        self.address = cleanAddress
        self.selection = cleanSelection
    }

    /// From the dictionary Safari's native messaging hands the extension handler. Values that
    /// aren't text are ignored; unknown keys are ignored.
    public init?(message: [String: Any]) {
        self.init(title: message["title"] as? String, address: message["url"] as? String, selection: message["selection"] as? String)
    }

    /// The note's words: the selection (or the title when nothing was selected), then the title
    /// after a dash when there was a selection, then the address on its own line.
    public func item(sharedAt: Date, id: UUID = UUID()) -> ShareInboxItem? {
        var body: [String] = []
        if !selection.isEmpty {
            body.append(selection)
            if !title.isEmpty { body.append("\u{2014} \(title)") }
        } else if !title.isEmpty {
            body.append(title)
        }
        return ShareInboxItem.compose(text: body.joined(separator: "\n\n"), link: address.isEmpty ? nil : address, sharedAt: sharedAt, id: id)
    }
}
