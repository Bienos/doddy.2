import SwiftUI

/// The welcome's picture (ADR-299): the four panels of the owner's page-turn storyboard
/// (038_trans_page_v01): a notebook on a desk, its page turning, the drawn street behind it,
/// and Doddy waving hello. Played once, as cross-fades, then it stays on the wave. It is not
/// the opening (ADR-225), which still plays first; this only replaces the welcome's still.
struct StorybookView: View {
    /// Set once the pages have turned, so going back to the welcome doesn't play them again.
    @Binding var played: Bool
    var height: CGFloat = 280

    var body: some View {
        PanelStoryView(story: .page, played: $played, height: height)
    }
}

/// One of the pack's storyboards (`PanelStory`, ADR-380), played once as cross-fades and then
/// left on its last panel. With Reduce Motion only the last panel shows. Decorative: hidden from
/// VoiceOver, and with "Hide Doddy's pictures".
struct PanelStoryView: View {
    let story: PanelStory
    /// Set once the panels have played, so coming back to the screen doesn't play them again.
    @Binding var played: Bool
    var height: CGFloat = 280
    @State private var panel = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false

    var body: some View {
        if !hideCharacterArt {
            let shown = reduceMotion || played ? story.panelCount : panel
            ZStack {
                ForEach(1...story.panelCount, id: \.self) { index in
                    Image(decorative: story.assetName(index))
                        .resizable()
                        .scaledToFit()
                        .opacity(index <= shown ? 1 : 0)
                }
            }
            .frame(height: textSize.isAccessibilitySize ? min(height, 180) : height)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.separator, lineWidth: 1))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: shown)
            .accessibilityHidden(true)
            .doddyArtMarker("doddy.story.\(story.rawValue)")
            .task {
                guard !reduceMotion, !played else { return }
                for next in 2...story.panelCount {
                    try? await Task.sleep(for: .seconds(story.hold))
                    if Task.isCancelled { return }
                    panel = next
                }
                played = true
            }
        }
    }
}
