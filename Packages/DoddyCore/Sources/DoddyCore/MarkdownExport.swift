import Foundation

/// Markdown export of the saved notes, for pasting into Notes, Obsidian and similar apps (ADR-203).
/// Every note's words go in verbatim as a block quote (one `> ` per line); nothing is escaped,
/// trimmed or cut, so what is in the file is exactly what was saved. A note that was corrected
/// also carries its original wording. Same data as `MemoryExport.plainText`, newest first as given.
public enum MarkdownExport {
    public static func markdown(_ records: [MemoryRecord], exportedAt: Date) -> String {
        let iso = ISO8601DateFormatter()
        let count = records.count == 1 ? "1 note" : "\(records.count) notes"
        var lines = ["# Doddy memories", "", "Exported \(iso.string(from: exportedAt)) · \(count)", ""]
        for record in records {
            let saved = record.capturedAt.map(iso.string(from:)) ?? "date unavailable"
            lines.append("## \(saved) · \(record.category.rawValue)")
            lines.append("")
            lines += quote(record.currentText)
            lines.append("")
            var details = ["Source: \(record.source.rawValue)"]
            if record.userEdited {
                details.append("Corrected: \(record.updatedAt.map(iso.string(from:)) ?? "date unavailable")")
            }
            details.append("ID: `\(record.id.uuidString)`")
            lines.append(details.joined(separator: " · "))
            if record.userEdited {
                lines.append("")
                lines.append("Original wording:")
                lines.append("")
                lines += quote(record.rawText)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Each line of `text` as a block-quote line. An empty line becomes a bare `>` so the quote
    /// stays one block. Splits on `\n`, `\r\n` and a lone `\r`: Swift treats `\r\n` as ONE
    /// character, so splitting on `\n` alone would leave a Windows-style note in a single line.
    private static func quote(_ text: String) -> [String] {
        text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" })
            .map { $0.isEmpty ? ">" : "> \($0)" }
    }
}
