import DoddyCore
import QuickLook
import SwiftUI

/// Files (ADR-633): what used to be Memories at the bottom of Home. Two real sources, nothing invented:
/// the files Doddy made on his server (decks, documents, spreadsheets, PDFs; kept a week, ADR-564), read
/// with this iPhone's own session from `GET /v1/web/documents`, and the recordings on this iPhone
/// (DODDY Capture, ADR-588). A file is downloaded only when it is tapped, then opens in Quick Look, whose
/// Share button saves or sends it. Notes and lists moved to Settings › Doddy's memory.
///
/// Compiled in hosted CI (#195), NOT RUN on a device; the list and download rules are
/// `MadeDocumentsClient` in DoddyCore, tested on Linux.
struct FilesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = MadeDocumentsModel()
    @State private var showRecordings = false
    /// The downloaded file Quick Look shows.
    @State private var preview: URL?

    var body: some View {
        NavigationStack {
            List {
                madeByDoddy
                CallRecapSection(preview: $preview)
                Section {
                    Button { showRecordings = true } label: {
                        Label("Recordings", systemImage: "waveform.circle")
                    }
                    .accessibilityIdentifier("files.recordings")
                } footer: {
                    Text("Meetings and conversations you recorded. Kept on this iPhone.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("files.close")
                }
            }
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .sheet(isPresented: $showRecordings) { RecordingsView() }
            .quickLookPreview($preview)
        }
        .foregroundStyle(Theme.ink)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.canvas)
    }

    @ViewBuilder
    private var madeByDoddy: some View {
        Section {
            switch model.load {
            case .loading:
                ProgressView("Checking…")
                    .accessibilityIdentifier("files.loading")
            case .noAccount:
                Text("Nothing yet. When you ask Doddy to make a document, a deck or a spreadsheet, it shows up here.")
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("files.empty")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.error)
                Button("Try again") { Task { await model.refresh() } }
            case .ready(let list) where list.documents.isEmpty:
                Text("Nothing yet. When you ask Doddy to make a document, a deck or a spreadsheet, it shows up here.")
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("files.empty")
            case .ready(let list):
                ForEach(list.documents) { document in
                    Button {
                        Task { preview = await model.download(document) }
                    } label: {
                        MadeDocumentRow(document: document, downloading: model.downloading == document.id)
                    }
                    .disabled(!document.canOpen || model.downloading != nil)
                    .accessibilityIdentifier("files.document")
                }
            }
            if let problem = model.downloadProblem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.error)
                    .accessibilityIdentifier("files.downloadProblem")
            }
        } header: {
            Text("Made by Doddy")
        } footer: {
            Text("Doddy keeps the files he makes for a week. To keep one, open it and save it with Share.")
        }
    }
}

/// One file Doddy made: what it is, and its state as the server reports it.
struct MadeDocumentRow: View {
    let document: MadeDocument
    let downloading: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(document.canOpen ? Theme.accentText : Theme.secondaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: document.name)
                    .lineLimit(2)
                Text(state)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            if downloading { ProgressView() }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch document.kind {
        case .deck: "rectangle.on.rectangle"
        case .doc: "doc.text"
        case .spreadsheet: "tablecells"
        case .pdf: "doc.richtext"
        case .text: "doc.plaintext"
        case .file: "doc"
        }
    }

    private var state: String {
        switch document.status {
        case .ready:
            String(format: NSLocalizedString("Kept until %@", comment: "Files: a ready file and the day the server deletes it"),
                   document.deleteAfter.formatted(date: .abbreviated, time: .omitted))
        case .working: NSLocalizedString("Doddy is still making this", comment: "")
        case .failed: NSLocalizedString("This one didn't work. Ask Doddy to try again.", comment: "")
        case .interrupted: NSLocalizedString("Stopped before it was finished. Ask Doddy to try again.", comment: "")
        }
    }
}

/// The Files sheet's state. Holds no file text; a downloaded file goes to this app's temporary folder,
/// which iOS clears, and the folder is emptied each time the sheet loads.
@MainActor
@Observable
final class MadeDocumentsModel {
    enum Load: Equatable {
        case loading
        /// This iPhone has never signed in to Doddy's server, so the server has made nothing for it.
        case noAccount
        case failed(String)
        case ready(MadeDocumentList)
    }

    private(set) var load: Load = .loading
    private(set) var downloading: String?
    private(set) var downloadProblem: String?

    private static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MadeByDoddy", isDirectory: true)
    }

    /// `clearingDownloads` is false for the quiet refresh Messages makes while a file is being made, so a file the
    /// person has open in Quick Look is not deleted under them.
    func refresh(clearingDownloads: Bool = true) async {
        if clearingDownloads {
            try? FileManager.default.removeItem(at: Self.folder)
            downloadProblem = nil
        }
        // No session: nothing was ever made for this iPhone, and no sign-in is started just to look.
        guard let client = MadeDocumentsClientFactory.make() else {
            load = .noAccount
            return
        }
        if case .ready = load {} else { load = .loading }
        do {
            set(.ready(try await client.documents()))
        } catch WebLinkError.unauthenticated {
            // A refused session is renewed once; a second refusal is a failure, not another loop.
            guard let renewed = await MadeDocumentsClientFactory.renewed() else {
                fail(NSLocalizedString("Couldn't reach Doddy's server. Try again in a moment.", comment: ""), quietly: !clearingDownloads)
                return
            }
            do { set(.ready(try await renewed.documents())) } catch { fail(Self.text(for: error), quietly: !clearingDownloads) }
        } catch {
            fail(Self.text(for: error), quietly: !clearingDownloads)
        }
    }

    /// Only a list that changed is set (12 Nov 2026): Messages reads this every 6 or 30 seconds, and setting an
    /// unchanged list redrew the whole conversation each time ("to się trochę zacina").
    private func set(_ fresh: Load) {
        if fresh != load { load = fresh }
    }

    /// A background re-read that fails keeps the list it had (11 Nov 2026): replacing it made Messages' file cards
    /// vanish and come back with every poll. A refresh the person asked for still shows the problem.
    private func fail(_ message: String, quietly: Bool) {
        if quietly, case .ready = load { return }
        load = .failed(message)
    }

    /// Doddy is making a file for this person right now (as of the last refresh).
    func isMaking(now: Date) -> Bool {
        guard case .ready(let list) = load else { return false }
        return !ThreadAttachments.inProgress(documents: list.documents, thread: [], now: now).isEmpty
    }

    /// Downloads a ready file and returns where it is, for Quick Look. Nil after a problem, which is shown.
    func download(_ document: MadeDocument) async -> URL? {
        guard document.canOpen, downloading == nil, let client = MadeDocumentsClientFactory.make() else { return nil }
        downloading = document.id
        downloadProblem = nil
        defer { downloading = nil }
        do {
            let data = try await client.file(of: document)
            let directory = Self.folder.appendingPathComponent(document.id, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(document.safeFileName)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch let error as WebLinkError {
            downloadProblem = error == .notFound
                ? NSLocalizedString("Doddy's server doesn't keep this file any more. Ask him to make it again.", comment: "")
                : Self.text(for: error)
        } catch {
            downloadProblem = NSLocalizedString("The file couldn't be saved on this iPhone.", comment: "")
        }
        return nil
    }

    private static func text(for error: any Error) -> String {
        guard let error = error as? WebLinkError else {
            return NSLocalizedString("Couldn't reach Doddy's server. Try again in a moment.", comment: "")
        }
        return switch error {
        case .transport: NSLocalizedString("No connection. Try again when you're online.", comment: "")
        case .rateLimited: NSLocalizedString("Too many tries. Wait a minute and try again.", comment: "")
        case .server(let message): message
        case .notConfigured, .unauthenticated, .notFound, .unreadable:
            NSLocalizedString("Couldn't reach Doddy's server. Try again in a moment.", comment: "")
        }
    }
}

/// The documents client on the same server and session as online accounts (`OnlineAccountsClientFactory`).
enum MadeDocumentsClientFactory {
    /// Nil when the build has no server or this iPhone has no session for it.
    static func make() -> (any MadeDocumentsClient)? {
        // The token is used only with the server that issued it (`BoundSessionToken`).
        guard let url = DeviceSession.serverURL(), KeychainSessionStore.read()?.token(for: url) != nil else { return nil }
        return BackendMadeDocumentsClient(baseURL: url, boundToken: { KeychainSessionStore.read() }, transport: URLSessionTransport.shared)
    }

    /// After the server said `unauthenticated`: a fresh device session, then the client again.
    static func renewed() async -> (any MadeDocumentsClient)? {
        guard let url = DeviceSession.serverURL(), await DeviceSession.renew(server: url) else { return nil }
        return make()
    }
}
