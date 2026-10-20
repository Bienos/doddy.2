import DoddyCore
import SwiftUI

/// Plain list of what is actually built, from the capability catalog.
struct CapabilitiesSheet: View {
    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    /// The ink storyboard has played (ADR-380).
    @State private var inkPlayed = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Off the page and into a real street (the pack's 040, ADR-380).
                    PanelStoryView(story: .ink, played: $inkPlayed, height: 220)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    Text(CapabilityIntroduction.text(for: environment.capabilities))
                        .accessibilityIdentifier("capabilities.introduction")
                }
                KeysExampleSection()
                Section("What's built") {
                    ForEach(Capability.allCases, id: \.self) { capability in
                        StatusRow(
                            title: capability.displayName,
                            value: StatusCopy.text(for: environment.capabilities.status(of: capability)))
                    }
                }
            }
            .navigationTitle("What I can do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// "Where are my keys?" (ADR-380): the pack's keys storyboard (041) as a worked example, never
/// as the user's data. It only works for something the user told Doddy, so the captions say so.
private struct KeysExampleSection: View {
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false

    private static let count = PanelStory.keys.panelCount

    @ViewBuilder
    private func caption(_ panel: Int) -> some View {
        switch panel {
        case 1: Text("The keys aren't on the hook.")
        case 2: Text("You ask Doddy where they are.")
        case 3: Text("Doddy looks through what you told it.")
        case 4: Text("You'd saved “keys under the sofa cushion”.")
        case 5: Text("There they are.")
        default: Text("Found, from your own note.")
        }
    }

    var body: some View {
        Section {
            if !hideCharacterArt {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(1...PanelStory.keys.panelCount, id: \.self) { panel in
                        VStack(alignment: .leading, spacing: 6) {
                            Image(decorative: PanelStory.keys.assetName(panel))
                                .resizable()
                                .scaledToFill()
                                .frame(height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.separator, lineWidth: 1))
                            caption(panel)
                                .font(.footnote)
                        }
                    }
                }
                .doddyArtMarker("doddy.story.keys")
                .padding(.vertical, 4)
            } else {
                // Pictures hidden: the same story in words.
                ForEach(1...Self.count, id: \.self) { panel in
                    caption(panel)
                }
            }
            Text("Doddy can only find what you told it. It can't see your home or track your things.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        } header: {
            Text("An example: lost keys")
        }
    }
}
