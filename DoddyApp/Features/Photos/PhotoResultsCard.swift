import DoddyCore
import SwiftUI
import UIKit

/// The photos a voice search found (ADR-569): the counts, and the newest pictures as small squares.
/// Shown on this screen only; Doddy's voice hears the counts and times, never the pictures.
struct PhotoResultsCard: View {
    let results: VoiceSessionController.PhotoResults
    let onClose: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 4)]

    var body: some View {
        let summary = results.summary
        VStack(alignment: .leading, spacing: 12) {
            Label("Your photos", systemImage: "photo.on.rectangle")
                .font(.headline)
            Text(results.request.text(calendar: .current))
                .foregroundStyle(Theme.secondaryText)
            Text("\(summary.photos) photos · \(summary.videos) videos")
                .font(.subheadline.weight(.semibold))
            if summary.limited {
                Text("You let Doddy see only some of your photos, so there may be more.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            if !results.identifiers.isEmpty {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(results.identifiers, id: \.self) { identifier in
                        PhotoThumbnail(identifier: identifier)
                    }
                }
                if summary.photos + summary.videos > results.identifiers.count {
                    Text("The newest \(results.identifiers.count) are shown here.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Text("These stay on this iPhone. Doddy's voice hears only how many there are and when they were taken.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            if let url = URL(string: "photos-redirect://") {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Label("Open Photos", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("voice.photos.open")
            }
            Button("Close", action: onClose)
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice.photoResults")
    }
}

/// One small square picture, drawn from the copy on this iPhone.
private struct PhotoThumbnail: View {
    let identifier: String
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
            .task(id: identifier) {
                image = await PhotoLibrarySearch.thumbnail(identifier, side: 180)
            }
    }
}
