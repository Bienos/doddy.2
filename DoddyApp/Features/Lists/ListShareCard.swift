import DoddyCore
import SwiftUI
import UniformTypeIdentifiers

/// A list as a picture to share (ADR-313): its name and what is left on it, on Doddy's cream
/// paper, with Doddy waving. The same words as "Share as text" (open items only), drawn only when
/// a share target asks for it. Doddy is left off with "Hide Doddy's pictures".
struct ListShareCard: Transferable, Sendable {
    static let maxItems = 15

    let name: String
    let items: [String]
    let showsDoddy: Bool

    init(list: DoddyList, defaults: UserDefaults = .standard) {
        name = list.name
        items = list.open.map(\.text)
        showsDoddy = !defaults.bool(forKey: PreferenceKey.hideCharacterArt)
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in
            try await card.png()
        }
    }

    @MainActor
    func png() throws -> Data {
        let renderer = ImageRenderer(content: ListShareCardView(card: self).environment(\.colorScheme, .light))
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}

/// The picture itself: fixed light colours, so it looks the same wherever it is sent.
struct ListShareCardView: View {
    let card: ListShareCard
    private let paper = Color(red: 0xFF / 255, green: 0xF7 / 255, blue: 0xE9 / 255)
    private let ink = Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x15 / 255)
    private let secondary = Color(red: 0x65 / 255, green: 0x5F / 255, blue: 0x56 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                Text(card.name)
                    .font(.system(size: 28, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 12)
                if card.showsDoddy {
                    IslandPoseView(pose: .wave, maxSize: CGSize(width: 60, height: 96), edged: false)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                if card.items.isEmpty {
                    Text("Nothing left.").foregroundStyle(secondary)
                }
                ForEach(Array(card.items.prefix(ListShareCard.maxItems).enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "square").font(.system(size: 15))
                        Text(item).font(.system(size: 18))
                    }
                }
                if card.items.count > ListShareCard.maxItems {
                    Text("and \(card.items.count - ListShareCard.maxItems) more").foregroundStyle(secondary)
                }
            }
            Text("From Doddy").font(.system(size: 13, weight: .medium)).foregroundStyle(secondary)
        }
        .foregroundStyle(ink)
        .padding(28)
        .frame(width: 380, alignment: .leading)
        .background(paper)
    }
}
