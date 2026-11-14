import DoddyCore
import SwiftUI

/// "Share" on a file Doddy made (owner, 10 Nov 2026: "wyślij mi to do plików albo wiadomości"). The tap
/// downloads the file to this iPhone and opens iOS's share sheet: Save to Files, Messages, Mail or any other
/// app. The person picks where it goes and sends it; Doddy sends nothing. Used on the voice card, in
/// Messages and in Files.
struct MadeFileShareButton: View {
    /// The link Doddy's server made for the file (`/v1/documents/<id>?…`).
    let link: URL
    @State private var files = MadeDocumentsModel()
    @State private var shared: SharedFile?
    @State private var working = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await share() }
            } label: {
                HStack {
                    Label("Share", systemImage: "square.and.arrow.up")
                    if working {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(working)
            .accessibilityHint(Text("Save it to Files or send it in Messages, Mail or another app. You choose where it goes."))
            .accessibilityIdentifier("file.share")
            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .sheet(item: $shared) { file in
            FileShareSheet(url: file.url)
                .presentationDetents([.medium, .large])
        }
    }

    private func share() async {
        working = true
        problem = nil
        defer { working = false }
        await files.refresh(clearingDownloads: false)
        guard case .ready(let list) = files.load else {
            if case .failed(let text) = files.load { problem = text } else {
                problem = NSLocalizedString("Couldn't reach Doddy's server. Try again in a moment.", comment: "")
            }
            return
        }
        switch MadeFileShare.lookup(link: link, in: list.documents, now: Date()) {
        case .ready(let document):
            if let url = await files.download(document) {
                shared = SharedFile(url: url)
            } else {
                problem = files.downloadProblem
            }
        case .making:
            problem = NSLocalizedString("Doddy is still making it. Try again in a minute.", comment: "Share on a file that isn't ready")
        case .failed:
            problem = NSLocalizedString("Doddy couldn't finish this file. Ask him to make it again.", comment: "")
        case .gone:
            problem = NSLocalizedString("Doddy's server doesn't keep this file any more. Ask him to make it again.", comment: "")
        }
    }

    private struct SharedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }
}
