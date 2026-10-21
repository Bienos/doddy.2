import Foundation

// Presentations by voice (ADR-567, owner 2026-10-20: "You should be able to do presentations").
// Apple gives apps no way to drive Keynote, so Doddy makes the file itself: "Make me a five-slide
// deck about our trip" becomes a card with every slide's title and points. Nothing is made until
// the user taps Make presentation. Then the app writes a PowerPoint file (.pptx, which Keynote,
// PowerPoint and Google Slides open) on the iPhone and opens the share sheet, where the user picks
// Keynote, Files or someone to send it to. Doddy can't see what they pick, so the agent hears only
// that the file was made and the share sheet opened.
//
// Too long or too many is refused, never cut (review C11): the agent hears which limit and makes
// the deck again, so the card always shows exactly what the file will hold.

extension VoiceToolName {
    public static let makePresentation = "make_presentation"
}

public struct PresentationSlide: Equatable, Sendable {
    public let title: String
    public let points: [String]

    public init(title: String, points: [String]) {
        self.title = title
        self.points = points
    }
}

/// What the agent proposed. The first slide of the file is a title slide made from `title` and
/// `subtitle`; `slides` follow it.
public struct PresentationDraft: Equatable, Sendable {
    public let title: String
    public let subtitle: String?
    public let slides: [PresentationSlide]

    public init(title: String, subtitle: String?, slides: [PresentationSlide]) {
        self.title = title
        self.subtitle = subtitle
        self.slides = slides
    }

    /// Slides in the file, the title slide included.
    public var slideCount: Int { slides.count + 1 }

    /// "Our trip to Kraków.pptx": the title without characters a file name can't hold, at most 60
    /// characters, or "Presentation.pptx".
    public var fileName: String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        let cleaned = title.unicodeScalars.map { forbidden.contains($0) ? " " : String($0) }.joined()
        let words = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // No leading dot (a hidden file) and no trailing dot or space.
        var name = String(words.prefix(60))
        while let first = name.first, first == "." || first.isWhitespace { name.removeFirst() }
        while let last = name.last, last == "." || last.isWhitespace { name.removeLast() }
        return (name.isEmpty ? "Presentation" : name) + ".pptx"
    }
}

public enum PresentationLimits {
    /// Slides after the title slide.
    public static let maxSlides = 15
    public static let maxPoints = 6
    public static let maxSlideTitle = 100
    public static let maxPoint = 160
    /// The `slides` argument is JSON text; bounded as a whole before it is read (review C11).
    public static let slidesJSON = 16_000
}

extension VoiceToolRequest {
    static func parsePresentation(_ args: Arguments, name: String) -> VoiceToolRequest {
        guard let title = args.text("title").map(PresentationText.line), !title.isEmpty else {
            return .invalid(name: name, reason: "missing title")
        }
        let subtitle = args.text("subtitle").map(PresentationText.line).flatMap { $0.isEmpty ? nil : $0 }
        // The slides come as JSON text, like propose_plan's steps; an array is taken as well.
        let raw: Any?
        if let text = args.text("slides") {
            raw = text.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }
        } else {
            raw = args.raw("slides")
        }
        guard let list = raw as? [Any], !list.isEmpty else {
            return .invalid(name: name, reason: "slides must be a JSON array with at least one slide")
        }
        guard list.count <= PresentationLimits.maxSlides else {
            return .invalid(name: name, reason: "at most \(PresentationLimits.maxSlides) slides after the title slide; make a shorter deck")
        }
        var slides: [PresentationSlide] = []
        for (index, item) in list.enumerated() {
            let number = index + 1
            guard let object = item as? [String: Any],
                  let slideTitle = (object["title"] as? String).map(PresentationText.line), !slideTitle.isEmpty else {
                return .invalid(name: name, reason: "slide \(number) has no title")
            }
            guard slideTitle.count <= PresentationLimits.maxSlideTitle else {
                return .invalid(name: name, reason: "slide \(number)'s title is longer than \(PresentationLimits.maxSlideTitle) characters")
            }
            let points = ((object["points"] as? [Any]) ?? []).compactMap { $0 as? String }
                .map(PresentationText.line).filter { !$0.isEmpty }
            guard points.count <= PresentationLimits.maxPoints else {
                return .invalid(name: name, reason: "slide \(number) has more than \(PresentationLimits.maxPoints) points; split it into two slides")
            }
            if let long = points.firstIndex(where: { $0.count > PresentationLimits.maxPoint }) {
                return .invalid(name: name, reason: "point \(long + 1) on slide \(number) is longer than \(PresentationLimits.maxPoint) characters; shorten it")
            }
            slides.append(PresentationSlide(title: slideTitle, points: points))
        }
        return .makePresentation(PresentationDraft(title: title, subtitle: subtitle, slides: slides))
    }
}

/// One line of slide text: line breaks and runs of spaces become one space, the ends are trimmed.
enum PresentationText {
    static func line(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }
}

extension VoiceToolReply {
    public static let presentationDeclined = "declined: the user chose not to make the presentation. Nothing was made."

    /// After the tap: the file was written and read back on the iPhone. The title is the agent's
    /// own words, so it goes back as data (ToolData).
    public static func presentationMade(_ draft: PresentationDraft) -> String {
        "made: the presentation is saved on the user's iPhone as a PowerPoint file that Keynote opens, \(draft.slideCount) slides with the title slide. The share sheet is open so they can open it in Keynote, save it to Files or send it. Doddy can't see what they choose: never say it was opened, saved or sent.\n"
            + ToolData.block(["Title: \"\(ToolData.clean(draft.title))\""])
    }

    public static func presentationFailed(_ reason: String) -> String {
        "failed: the presentation wasn't made (\(reason)). Nothing was saved. Tell the user in one short sentence."
    }
}
