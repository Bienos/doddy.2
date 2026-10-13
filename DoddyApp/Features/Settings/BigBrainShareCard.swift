import SwiftUI
import UniformTypeIdentifiers

/// Doddy's "Big brain. Small body." card as a picture to share (ADR-444): the owner's card, with the
/// lettering set as text and the art from the owner's own picture (`ShareDoddy_big_brain`). It holds
/// nothing the person saved. 400 × 210 pt drawn at 3×, so 1200 × 630 px, the same as the site's
/// link-preview card (`tools/share_card/big_brain.html`).
struct BigBrainShareCard: Transferable, Sendable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in
            try await card.png()
        }
    }

    @MainActor
    func png() throws -> Data {
        let renderer = ImageRenderer(content: BigBrainShareCardView().environment(\.colorScheme, .light))
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}

/// The picture itself: fixed light colours, so it looks the same wherever it is sent. System type
/// only; no display font is bundled (CLAUDE.md). The words stay English in every language, like
/// the site's card: the tagline is not translated literally (BRAND_GUIDELINES 3.8).
struct BigBrainShareCardView: View {
    private let paper = Color(red: 0xFF / 255, green: 0xF7 / 255, blue: 0xE9 / 255)
    private let ink = Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x15 / 255)
    private let orange = Color(red: 0xF5 / 255, green: 0x8A / 255, blue: 0x24 / 255)

    /// "Your mate in your pocket." with "mate" underlined in orange.
    private var tagline: AttributedString {
        var mate = AttributedString("mate")
        mate.underlineStyle = Text.LineStyle(pattern: .solid, color: orange)
        return AttributedString("Your ") + mate + AttributedString(" in your pocket.")
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            paper
            Image("ShareDoddy_big_brain")
                .resizable()
                .scaledToFit()
                .frame(width: 188, height: 181)
                .padding(.trailing, 11)
                .padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "Big brain.")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                Text(verbatim: "Small body.")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(orange)
                    .rotationEffect(.degrees(-2), anchor: .leading)
                Capsule()
                    .fill(orange)
                    .frame(width: 140, height: 3)
                    .rotationEffect(.degrees(-1), anchor: .leading)
                    .padding(.top, 8)
                Spacer(minLength: 0)
                Text(verbatim: "DODDY")
                    .font(.system(size: 26, weight: .heavy))
                Text(tagline)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.top, 2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 180, alignment: .leading)
            .padding(.leading, 26)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(ink)
        .frame(width: 400, height: 210)
    }
}
