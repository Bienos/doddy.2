import DoddyCore
import Foundation
import XCTest

final class MarkdownExportTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    func testEachNoteIsAHeadingAQuoteAndItsProvenance() throws {
        let note = try MemoryRecord(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!, rawText: "Gate code 4821",
                                    source: .explicitVoice, category: .place, capturedAt: t0)
        let text = MarkdownExport.markdown([note], exportedAt: t0.addingTimeInterval(60))
        XCTAssertEqual(text, """
            # Doddy memories

            Exported 2025-10-09T08:54:20Z · 1 note

            ## 2025-10-09T08:53:20Z · place

            > Gate code 4821

            Source: explicit_voice · ID: `11111111-2222-3333-4444-555555555555`

            """)
    }

    func testWordsAreVerbatimWithMarkdownCharactersAndBlankLinesKept() throws {
        let raw = "# not a heading\n*stars* and _underscores_\n\n  indented line\r\nlast"
        let note = try MemoryRecord(id: UUID(), rawText: raw, source: .explicitText, capturedAt: t0)
        let text = MarkdownExport.markdown([note], exportedAt: t0)
        XCTAssertTrue(text.contains("> # not a heading\n> *stars* and _underscores_\n>\n>   indented line\n> last"),
                      "every line quoted, nothing escaped or trimmed, blank line kept inside the quote")
    }

    func testCorrectedNoteCarriesItsOriginalAndEveryNoteIsListed() throws {
        let corrected = try MemoryRecord(id: UUID(), rawText: "Keys in the blue tin", source: .explicitText, capturedAt: t0)
            .correcting(to: "Keys in the red tin", at: t0.addingTimeInterval(3600))
        let legacy = try MemoryRecord(id: UUID(), rawText: "Old note", source: .importedLegacyUnknown, capturedAt: nil)
        let text = MarkdownExport.markdown([corrected, legacy], exportedAt: t0)
        XCTAssertTrue(text.contains("> Keys in the red tin"))
        XCTAssertTrue(text.contains("Corrected: 2025-10-09T09:53:20Z"))
        XCTAssertTrue(text.contains("Original wording:\n\n> Keys in the blue tin"))
        XCTAssertTrue(text.contains("## date unavailable · other"), "an unknown date is stated, never invented")
        XCTAssertTrue(text.contains("2 notes"))
        XCTAssertTrue(MarkdownExport.markdown([], exportedAt: t0).contains("0 notes"))
    }
}
