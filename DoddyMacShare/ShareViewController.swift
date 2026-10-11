import AppKit
import DoddyCore
import SwiftUI
import UniformTypeIdentifiers

/// "Save to Doddy" in the Mac Share menu (ADR-352). Shows what another app shared and, after
/// "Send to Doddy", leaves it as a clip in the Mac clip inbox (App Group folder) for the Mac app,
/// which lists the waiting clips and saves one only when the user presses Save there. This
/// extension saves no note, opens no database and uses no network.
final class ShareViewController: NSViewController {
    private let model = ShareModel()

    /// Room for the text and the buttons; the Share menu shows the extension at about this size.
    private static let contentSize = NSSize(width: 420, height: 260)

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: Self.contentSize))
        preferredContentSize = Self.contentSize
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = NSHostingController(rootView: ShareView(
            model: model,
            cancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
            },
            close: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        ))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.width, .height]
        view.addSubview(host.view)
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let model = model
        // Item providers aren't Sendable: they are read off the main actor and only the strings come back.
        Task.detached {
            let shared = await ShareModel.extract(items)
            await model.show(text: shared.text, link: shared.link)
        }
    }
}

@MainActor
@Observable
final class ShareModel {
    enum Phase: Equatable {
        case loading
        case ready(ShareInboxItem)
        case nothing
        case notSetUp
        case sent
        case full
        case failed
    }

    private(set) var phase: Phase = .loading

    /// The shared text and the first web link. A file's address is never taken as a link.
    nonisolated static func extract(_ items: sending [NSExtensionItem]) async -> (text: String?, link: String?) {
        var text = items.compactMap { $0.attributedContentText?.string }.first { !$0.isEmpty }
        var link: String?
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if link == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, !url.isFileURL {
                link = url.absoluteString
            } else if text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let shared = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                text = shared
            }
        }
        return (text, link)
    }

    func show(text: String?, link: String?) {
        guard ClipInboxLocation.isAvailable else { phase = .notSetUp; return }
        phase = ShareInboxItem.compose(text: text, link: link, sharedAt: .now).map(Phase.ready) ?? .nothing
    }

    /// Leaves the clip in the inbox. "Sent" only after the clip was written and read back.
    func send() {
        guard case .ready(let item) = phase else { return }
        do {
            switch try ClipInboxLocation.inbox?.add(item) {
            case .added: phase = .sent
            case .full: phase = .full
            case nil: phase = .failed
            }
        } catch {
            phase = .failed
        }
    }
}

struct ShareView: View {
    let model: ShareModel
    let cancel: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Save to Doddy")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            buttons
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 420, minHeight: 260)
    }

    @ViewBuilder private var buttons: some View {
        HStack {
            Spacer()
            switch model.phase {
            case .loading:
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("share.cancel")
            case .ready:
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("share.cancel")
                Button("Send to Doddy") { model.send() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("share.send")
            case .nothing, .notSetUp, .sent, .full, .failed:
                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("share.done")
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .ready(let item):
            Text(item.text).font(.body).lineLimit(12)
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            Text("Doddy keeps this in its list of waiting clips on your Mac. Nothing is saved until you press Save there.")
                .font(.footnote).foregroundStyle(.secondary)
        case .nothing:
            Text("There's no text or web link here that Doddy can keep. Nothing was saved.")
        case .notSetUp:
            Text("Sharing to Doddy isn't set up in this version of the app. Nothing was saved.")
        case .sent:
            Label("Ready in Doddy", systemImage: "checkmark.circle").font(.headline)
            Text("Open Doddy to check it and press Save. It isn't saved yet.")
                .foregroundStyle(.secondary)
        case .full:
            Text(String(format: NSLocalizedString("Doddy already has %lld clips waiting. Open Doddy and save or discard some, then try again. Nothing was saved.", comment: ""), ClipInbox.maxWaiting))
        case .failed:
            Text("That couldn't be handed to Doddy. Nothing was saved. Try again.")
        }
    }
}
