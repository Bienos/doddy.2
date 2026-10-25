import DoddyCore
import Foundation
import Observation
import UIKit

/// Opens a file bubble the way the iPhone opens any file (ADR-654, owner, 25 Oct 2026: "jak
/// najbardziej systemowy interfejs, żeby otwierał w domyślnych rzeczach"): the file is downloaded
/// with this iPhone's own session and shown in Quick Look, whose Share button offers Keynote,
/// Files, AirDrop, Mail and every app that opens that kind of file, and "Open in…" for a .pptx.
/// Doddy builds no viewer of his own for it.
///
/// Before this, a tap opened the signed link in Safari, which shows the same preview but in a
/// browser, with the link in the address bar. That is still the fallback: when the app has no
/// session, the link isn't a document's, or the download fails (the file may still be being made,
/// or gone after a week: the link's page says which, in words).
///
/// NOT COMPILED here (needs the app target); the link rule is `ThreadDocument.madeDocument`, tested in DoddyCore.
@MainActor
@Observable
final class ThreadFileOpener {
    /// The downloaded file Quick Look shows (`.quickLookPreview`).
    var preview: URL?
    /// The link of the file being downloaded, for a spinner on its bubble.
    private(set) var opening: URL?

    func open(_ document: ThreadDocument) async {
        guard opening == nil else { return }
        guard let made = document.madeDocument(now: Date()), MadeDocumentsClientFactory.make() != nil else {
            _ = await UIApplication.shared.open(document.url)
            return
        }
        opening = document.url
        defer { opening = nil }
        if let url = await MadeDocumentsModel().download(made) {
            preview = url
        } else {
            _ = await UIApplication.shared.open(document.url)
        }
    }
}
