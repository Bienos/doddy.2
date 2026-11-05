import Foundation

/// The email card (owner, 22 Oct 2026, ADR-597): a server preview for an email (Gmail or Outlook
/// draft, send, reply) laid out as To, Subject and the text, instead of a list of lines. The
/// server writes these previews as `To: …`, then `Subject: …` or a reply's `Re: …`, then the body,
/// then any notes ("It is sent at once from your Gmail and can't be taken back."). Every line is
/// shown exactly as the server sent it; only the `To: ` and `Subject: ` prefixes become labels.
/// Anything else gives nil and the card lists the lines as before.
public struct EmailPreviewLayout: Equatable, Sendable {
    public let to: String
    public let subject: String
    public let body: String
    public let notes: [String]

    public static func parse(_ lines: [String]) -> EmailPreviewLayout? {
        guard lines.count >= 3, lines[0].hasPrefix("To: ") else { return nil }
        let to = String(lines[0].dropFirst("To: ".count))
        let subject: String
        if lines[1].hasPrefix("Subject: ") {
            subject = String(lines[1].dropFirst("Subject: ".count))
        } else if lines[1].lowercased().hasPrefix("re:") {
            subject = lines[1]
        } else {
            return nil
        }
        guard !to.isEmpty else { return nil }
        return EmailPreviewLayout(to: to, subject: subject, body: lines[2], notes: Array(lines.dropFirst(3)))
    }
}
