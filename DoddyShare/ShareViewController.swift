import DoddyCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Save to Doddy" in the Share Sheet (ADR-311). Shows what another app shared and, after
/// "Send to Doddy", leaves it in the App Group for the app, which opens the capture screen with
/// it. This extension saves no note, opens no database and uses no network.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        // Item providers aren't Sendable: they are read off the main actor and only the strings come
        // back. Nothing on the main actor touches `items` after this, so handing them over is safe.
        nonisolated(unsafe) let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let model = model
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
        /// A product link was left for the Shopping screen's "Check this" card (docs/implementation/SHOPPING.md).
        case sentForPriceCheck
        case failed
    }

    private(set) var phase: Phase = .loading
    /// An earlier share the app hasn't picked up yet; sending replaces it.
    private(set) var replacesWaiting = false

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
        guard ShareInboxFile.isAvailable else { phase = .notSetUp; return }
        replacesWaiting = ShareInboxFile.hasWaitingItem
        phase = ShareInboxItem.compose(text: text, link: link, sharedAt: .now).map(Phase.ready) ?? .nothing
    }

    /// True when what was shared holds a web address the Shopping screen can take as a product link.
    var canCheckPrice: Bool {
        guard case .ready(let item) = phase else { return false }
        return SharedShopPage.parse(item.text) != nil
    }

    /// Leaves the shared text and link for the Shopping screen's "Check this" card, in a file of its own. Nothing is
    /// read from the shop and nothing is sent from here: this extension has no network.
    func sendForPriceCheck() {
        guard canCheckPrice, case .ready(let item) = phase else { return }
        do {
            try ShareInboxFile.write(item, slot: .priceCheck)
            phase = .sentForPriceCheck
        } catch {
            phase = .failed
        }
    }

    func send() {
        guard case .ready(let item) = phase else { return }
        do {
            try ShareInboxFile.write(item)
            phase = .sent
        } catch {
            phase = .failed
        }
    }
}

struct ShareView: View {
    let model: ShareModel
    let close: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Save to Doddy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case .ready = model.phase {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send to Doddy") { model.send() }.accessibilityIdentifier("share.send")
                    }
                } else if model.phase != .loading {
                    ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) }
                }
                if model.canCheckPrice {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Check the price") { model.sendForPriceCheck() }.accessibilityIdentifier("share.checkPrice")
                    }
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .ready(let item):
            Text(item.text).font(.body).lineLimit(12)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            Text("Doddy opens this on the capture screen next time you open the app. Nothing is saved until you tap Save there.")
                .font(.footnote).foregroundStyle(.secondary)
            if model.replacesWaiting {
                Text("This replaces something you shared earlier that isn't saved yet.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .nothing:
            Text("There's no text or web link here that Doddy can keep. Nothing was saved.")
        case .notSetUp:
            Text("Sharing to Doddy isn't set up in this version of the app. Nothing was saved. You can use the Save to Doddy shortcut instead.")
        case .sent:
            Label("Ready in Doddy", systemImage: "checkmark.circle").font(.headline)
            Text("Open Doddy to check it and tap Save. It isn't saved yet.")
                .foregroundStyle(.secondary)
        case .sentForPriceCheck:
            Label("Ready to check in Doddy", systemImage: "checkmark.circle").font(.headline)
            Text("Open Doddy: the Shopping screen has this link ready. Nothing is read or sent until you tap the buttons there.")
                .foregroundStyle(.secondary)
        case .failed:
            Text("That couldn't be handed to Doddy. Nothing was saved. Try again.")
        }
    }
}
