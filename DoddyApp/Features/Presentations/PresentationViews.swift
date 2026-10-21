import DoddyCore
import SwiftUI
import UIKit

/// The card before a presentation is made (ADR-567): every slide exactly as the file will hold it.
struct PresentationCardContent: View {
    let draft: PresentationDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Make this presentation?")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title)
                    .font(.title3.bold())
                if let subtitle = draft.subtitle {
                    Text(subtitle)
                        .foregroundStyle(Theme.secondaryText)
                }
                Text("\(draft.slideCount) slides, with the title slide")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(Array(draft.slides.enumerated()), id: \.offset) { index, slide in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 2)")
                            .font(.footnote.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityLabel("Slide \(index + 2)")
                        Text(slide.title)
                            .font(.body.weight(.semibold))
                    }
                    ForEach(Array(slide.points.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(Theme.orangeCue)
                                .frame(width: 5, height: 5)
                                .accessibilityHidden(true)
                            Text(point)
                                .font(.subheadline)
                        }
                        .padding(.leading, 20)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Text("Doddy makes a PowerPoint file on this iPhone, which Keynote opens. Then you pick Keynote, Files or someone to send it to. Doddy never sends it.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

/// After the file is made: it stays here to open or share again in this conversation.
struct PresentationReadyCard: View {
    let ready: VoiceSessionController.PresentationReady
    let onShare: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your presentation is ready", systemImage: "rectangle.on.rectangle.angled")
                .font(.headline)
            Text("“\(ready.title)” · \(ready.slideCount) slides")
                .foregroundStyle(Theme.secondaryText)
            Text("It's in Doddy's temporary files until iOS clears them. Save it in Keynote or Files to keep it.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Button(action: onShare) {
                Label("Open in Keynote or share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("voice.presentation.share")
            Button("Close", action: onClose)
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// iOS's share sheet for one file: Keynote, Files, AirDrop, Mail and the rest are iOS's choice.
struct FileShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
