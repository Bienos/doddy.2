import DoddyCore
import UIKit

/// Copying a note's words, or a Messages bubble's, to the clipboard (ADR-724). Every other app can read the general clipboard, and
/// Universal Clipboard sends it to the person's other devices, so a copy from Doddy is for this iPhone
/// only and leaves the clipboard after two minutes (`ClipboardPolicy`, tested in DoddyCore). The
/// translator's copy (review H10) and the BLIK card's (ADR-510) are made the same way. Only writes: what
/// Doddy reads from the clipboard (a pasted key, a parcel number) is not changed.
@MainActor
enum NoteClipboard {
    static func copy(_ text: String, now: Date = .now) {
        UIPasteboard.general.setItems(
            [["public.utf8-plain-text": text]],
            options: [.localOnly: true, .expirationDate: ClipboardPolicy.noteExpiry(copiedAt: now)])
    }
}
