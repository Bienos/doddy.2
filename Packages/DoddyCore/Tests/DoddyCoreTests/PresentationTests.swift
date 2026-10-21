import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import XCTest
@testable import DoddyCore

/// make_presentation (ADR-563): the arguments, the limits (refused, never cut), the file name and
/// the .pptx package itself, read back with a small ZIP reader below.
final class PresentationTests: XCTestCase {
    private func parse(_ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: VoiceToolName.makePresentation, parametersJSON: Data(json.utf8))
    }

    private func slides(_ count: Int, points: Int = 2) -> String {
        let one = (0..<count).map { index in
            let list = (0..<points).map { "\"Point \($0 + 1)\"" }.joined(separator: ",")
            return "{\"title\":\"Slide \(index + 1)\",\"points\":[\(list)]}"
        }
        return "[" + one.joined(separator: ",") + "]"
    }

    private func args(title: String = "Our trip", subtitle: String? = nil, slides: String) -> String {
        var object: [String: Any] = ["title": title, "slides": slides]
        if let subtitle { object["subtitle"] = subtitle }
        return String(data: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), encoding: .utf8)!
    }

    private let sample = PresentationDraft(
        title: "Our trip to Kraków", subtitle: "October 2026",
        slides: [
            PresentationSlide(title: "Day 1: Old Town", points: ["Wawel Castle in the morning", "Lunch at the market square"]),
            PresentationSlide(title: "Day 2 & more <fun>", points: ["Kazimierz \"walking\" tour", "Dinner by the river"]),
            PresentationSlide(title: "Thanks", points: []),
        ])

    // MARK: Arguments

    func testSlidesAsJSONTextAreParsed() {
        let request = parse(args(subtitle: " October  2026 ", slides: #"[{"title":"Day 1","points":["Old Town","  Wawel\nCastle "]}]"#))
        XCTAssertEqual(request, .makePresentation(PresentationDraft(
            title: "Our trip", subtitle: "October 2026", slides: [PresentationSlide(title: "Day 1", points: ["Old Town", "Wawel Castle"])])))
    }

    func testSlidesAsAnArrayAreTakenToo() {
        let request = parse(#"{"title":"Plan","slides":[{"title":"Goals","points":["Ship it"]}]}"#)
        XCTAssertEqual(request, .makePresentation(PresentationDraft(title: "Plan", subtitle: nil, slides: [PresentationSlide(title: "Goals", points: ["Ship it"])])))
    }

    func testASlideWithoutPointsIsAllowed() {
        guard case .makePresentation(let draft) = parse(args(slides: #"[{"title":"Questions?"}]"#)) else { return XCTFail() }
        XCTAssertEqual(draft.slides, [PresentationSlide(title: "Questions?", points: [])])
        XCTAssertEqual(draft.slideCount, 2, "the title slide counts")
    }

    func testMissingOrBrokenPartsAreRefused() {
        XCTAssertEqual(parse(#"{"slides":"[{\"title\":\"A\"}]"}"#), .invalid(name: "make_presentation", reason: "missing title"))
        for broken in [#"{"title":"T"}"#, #"{"title":"T","slides":"not json"}"#, #"{"title":"T","slides":"[]"}"#] {
            XCTAssertEqual(parse(broken), .invalid(name: "make_presentation", reason: "slides must be a JSON array with at least one slide"), broken)
        }
        XCTAssertEqual(parse(args(slides: #"[{"points":["x"]}]"#)), .invalid(name: "make_presentation", reason: "slide 1 has no title"))
    }

    func testLimitsAreRefusedNeverCut() {
        XCTAssertEqual(parse(args(slides: slides(16))), .invalid(
            name: "make_presentation", reason: "at most 15 slides after the title slide; make a shorter deck"))
        if case .invalid = parse(args(slides: slides(15, points: 6))) { XCTFail("15 slides of 6 points is allowed") }
        XCTAssertEqual(parse(args(slides: slides(2, points: 7))), .invalid(
            name: "make_presentation", reason: "slide 1 has more than 6 points; split it into two slides"))
        let longPoint = String(repeating: "a", count: 161)
        XCTAssertEqual(parse(args(slides: "[{\"title\":\"A\",\"points\":[\"ok\",\"\(longPoint)\"]}]")), .invalid(
            name: "make_presentation", reason: "point 2 on slide 1 is longer than 160 characters; shorten it"))
        let longTitle = String(repeating: "b", count: 101)
        XCTAssertEqual(parse(args(slides: "[{\"title\":\"\(longTitle)\"}]")), .invalid(
            name: "make_presentation", reason: "slide 1's title is longer than 100 characters"))
    }

    func testTheSlidesTextHasItsOwnBound() {
        XCTAssertEqual(VoiceTextLimits.limit(for: "slides"), PresentationLimits.slidesJSON)
        let huge = String(repeating: "x", count: PresentationLimits.slidesJSON + 1)
        XCTAssertEqual(parse(args(slides: huge)), .invalid(name: "make_presentation", reason: "slides is longer than \(PresentationLimits.slidesJSON) characters"))
    }

    func testRules() {
        let request = VoiceToolRequest.makePresentation(sample)
        XCTAssertEqual(VoiceConnection.serving(VoiceToolName.makePresentation), .presentations)
        XCTAssertEqual(AskFirst.need(for: request), .ownPayloadCard, "the card is the slides themselves")
        XCTAssertTrue(ConnectionPause.applies(to: request))
        if case .refuse = CarProfile.decision(for: request) {} else { XCTFail("needs a tap, so not while driving") }
        XCTAssertEqual(ToolCatalog.descriptor(VoiceToolName.makePresentation)?.approval, .card)
        let row = ActivityRequest.describe(request, calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(row?.app, .presentations)
        XCTAssertEqual(row?.logDetail, "4 slides", "the 30-day log keeps no slide text")
    }

    // MARK: File name and replies

    func testFileName() {
        XCTAssertEqual(sample.fileName, "Our trip to Kraków.pptx")
        XCTAssertEqual(PresentationDraft(title: "Q3/Q4: plan?", subtitle: nil, slides: []).fileName, "Q3 Q4 plan.pptx")
        XCTAssertEqual(PresentationDraft(title: "../..", subtitle: nil, slides: []).fileName, "Presentation.pptx")
        XCTAssertEqual(PresentationDraft(title: String(repeating: "a", count: 80), subtitle: nil, slides: []).fileName.count, 65)
    }

    func testTheReplyNeverClaimsItWasOpenedOrSent() {
        let reply = VoiceToolReply.presentationMade(sample)
        XCTAssertTrue(reply.hasPrefix("made: "))
        XCTAssertTrue(reply.contains("4 slides"))
        XCTAssertTrue(reply.contains("never say it was opened, saved or sent"))
        XCTAssertTrue(reply.contains(ToolData.begin), "the title is the agent's words, so it goes back as data")
        XCTAssertTrue(VoiceToolReply.presentationDeclined.hasPrefix("declined: "))
    }

    // MARK: The file

    func testEscapingKeepsTheXMLWellFormed() {
        XCTAssertEqual(PresentationFile.escape("A & B <c> \"d\" 'e'"), "A &amp; B &lt;c&gt; &quot;d&quot; &apos;e&apos;")
        XCTAssertEqual(PresentationFile.escape("bell\u{07}and\u{0B}tab\t"), "bellandtab\t", "control characters XML can't hold are left out")
        XCTAssertEqual(PresentationFile.escape("Zażółć 🎉"), "Zażółć 🎉")
    }

    func testCRC32MatchesTheStandardCheckValue() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(CRC32.checksum(Data()), 0)
    }

    func testThePackageHasEveryPartAndSlideAndReadsBack() throws {
        let data = try PresentationFile.pptx(sample, created: Date(timeIntervalSince1970: 1_792_000_000))
        let files = try ZipReader.read(data)
        let names = files.map(\.name)
        XCTAssertEqual(names.first, "[Content_Types].xml")
        for part in ["_rels/.rels", "ppt/presentation.xml", "ppt/_rels/presentation.xml.rels", "ppt/theme/theme1.xml",
                     "ppt/slideMasters/slideMaster1.xml", "ppt/slideLayouts/slideLayout1.xml", "docProps/core.xml", "docProps/app.xml"] {
            XCTAssertTrue(names.contains(part), part)
        }
        let slideParts = names.filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
        XCTAssertEqual(slideParts.count, 4)
        XCTAssertEqual(names.filter { $0.hasPrefix("ppt/slides/_rels/") }.count, 4)

        let text = { (name: String) in String(decoding: files.first { $0.name == name }!.data, as: UTF8.self) }
        let types = text("[Content_Types].xml")
        for number in 1...4 { XCTAssertTrue(types.contains("/ppt/slides/slide\(number).xml"), "slide \(number) has a content type") }
        XCTAssertEqual(text("ppt/presentation.xml").components(separatedBy: "<p:sldId ").count - 1, 4)
        XCTAssertTrue(text("ppt/slides/slide1.xml").contains("<a:t>Our trip to Kraków</a:t>"))
        XCTAssertTrue(text("ppt/slides/slide1.xml").contains("<a:t>October 2026</a:t>"))
        XCTAssertTrue(text("ppt/slides/slide3.xml").contains("<a:t>Day 2 &amp; more &lt;fun&gt;</a:t>"))
        XCTAssertTrue(text("ppt/slides/slide3.xml").contains("<a:t>Kazimierz &quot;walking&quot; tour</a:t>"))
        XCTAssertFalse(text("ppt/slides/slide4.xml").contains("Points"), "a slide without points has no empty text box")
        XCTAssertTrue(text("docProps/core.xml").contains("2026-10-14T"))
        XCTAssertTrue(text("docProps/app.xml").contains("<Slides>4</Slides>"))
    }

    func testTheSameDeckGivesTheSameBytes() throws {
        let created = Date(timeIntervalSince1970: 1_792_000_000)
        XCTAssertEqual(try PresentationFile.pptx(sample, created: created), try PresentationFile.pptx(sample, created: created))
    }

    func testEveryPartIsWellFormedXML() throws {
        for part in PresentationFile.parts(sample, created: Date()) {
            let parser = XMLParser(data: Data(part.xml.utf8))
            XCTAssertTrue(parser.parse(), "\(part.path): \(parser.parserError.map(String.init(describing:)) ?? "")")
        }
    }

    func testBodyTextShrinksToFitButNotBelowSixteen() {
        XCTAssertEqual(PresentationFile.bodySize(["Short"]), 2800)
        let full = Array(repeating: String(repeating: "word ", count: 32), count: 6)
        XCTAssertLessThan(PresentationFile.bodySize(full), 2800)
        XCTAssertGreaterThanOrEqual(PresentationFile.bodySize(full), 1600)
        XCTAssertEqual(PresentationFile.titleSlideSize("Short"), 5400)
        XCTAssertEqual(PresentationFile.slideTitleSize(String(repeating: "a", count: 100)), 2400)
    }

    /// Writes a sample deck for checking in Keynote, PowerPoint or LibreOffice:
    /// `DODDY_PPTX_OUT=/path/deck.pptx swift test --filter PresentationTests`.
    func testWritesASampleWhenAsked() throws {
        guard let path = ProcessInfo.processInfo.environment["DODDY_PPTX_OUT"] else { return }
        try PresentationFile.pptx(sample, created: Date()).write(to: URL(fileURLWithPath: path))
        // The fullest slide the limits allow, next to it, to check the text still fits.
        let point = String(repeating: "Long point text ", count: 10).prefix(PresentationLimits.maxPoint)
        let full = PresentationDraft(
            title: String(repeating: "A long presentation title ", count: 4), subtitle: "Every limit at once",
            slides: [PresentationSlide(title: String(repeating: "Slide title ", count: 9).prefix(PresentationLimits.maxSlideTitle).description,
                                       points: Array(repeating: String(point), count: PresentationLimits.maxPoints))])
        try PresentationFile.pptx(full, created: Date()).write(to: URL(fileURLWithPath: path + "-full.pptx"))
    }
}

/// Reads a stored (uncompressed) ZIP the way unzip does: local headers, then each file's bytes,
/// checking every CRC, then the central directory's count.
enum ZipReader {
    struct File { let name: String; let data: Data }
    struct Bad: Error { let reason: String }

    static func read(_ data: Data) throws -> [File] {
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> UInt32 { UInt32(u16(at)) | UInt32(u16(at + 2)) << 16 }
        var files: [File] = []
        var at = 0
        while at + 30 <= bytes.count, u32(at) == 0x0403_4B50 {
            guard u16(at + 8) == 0 else { throw Bad(reason: "not stored") }
            let crc = u32(at + 14), size = Int(u32(at + 18)), nameLength = u16(at + 26), extra = u16(at + 28)
            let name = String(decoding: bytes[(at + 30)..<(at + 30 + nameLength)], as: UTF8.self)
            let start = at + 30 + nameLength + extra
            let body = Data(bytes[start..<(start + size)])
            guard CRC32.checksum(body) == crc else { throw Bad(reason: "CRC of \(name)") }
            files.append(File(name: name, data: body))
            at = start + size
        }
        guard u32(at) == 0x0201_4B50 else { throw Bad(reason: "no central directory after the files") }
        let end = bytes.count - 22
        guard u32(end) == 0x0605_4B50, u16(end + 10) == files.count, Int(u32(end + 16)) == at else {
            throw Bad(reason: "end record doesn't match")
        }
        return files
    }
}
