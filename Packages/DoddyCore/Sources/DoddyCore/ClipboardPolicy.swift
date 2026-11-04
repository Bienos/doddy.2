import Foundation

/// Text copied out of Doddy (ADR-724). The clipboard is shared with every other app, and with the
/// person's other devices through Universal Clipboard, so a note copied from Doddy is put there for
/// this iPhone only (`UIPasteboard` option `localOnly`) and only for a short while. The translator
/// (review H10) and the BLIK card (ADR-510) already copy this way; a note's copy now does too.
public enum ClipboardPolicy {
    /// How long a copied note stays on the clipboard: two minutes, enough to switch app and paste.
    public static let noteLifetime: TimeInterval = 120

    /// When a note copied at `copiedAt` leaves the clipboard.
    public static func noteExpiry(copiedAt: Date) -> Date {
        copiedAt.addingTimeInterval(noteLifetime)
    }
}
