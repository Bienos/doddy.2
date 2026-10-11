import SwiftUI

/// The welcome's picture (ADR-299): the four panels of the owner's page-turn storyboard
/// (038_trans_page_v01): a notebook on a desk, its page turning, the drawn street behind it,
/// and Doddy waving hello. Played once, as cross-fades, then it stays on the wave. It is not
/// the opening (ADR-225), which still plays first; this only replaces the welcome's still.
/// With Reduce Motion only the last panel shows. Decorative: hidden from VoiceOver, and with
/// "Hide Doddy's pictures".
struct StorybookView: View {
    static let pageCount = 4
    /// Seconds each panel holds before the next fades in.
    static let hold = 1.1

    /// Set once the pages have turned, so going back to the welcome doesn't play them again.
    @Binding var played: Bool
    var height: CGFloat = 280
    @State private var page = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false

    var body: some View {
        if !hideCharacterArt {
            let shown = reduceMotion || played ? Self.pageCount : page
            ZStack {
                ForEach(1...Self.pageCount, id: \.self) { index in
                    Image(decorative: "Storybook_page_\(index)")
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
            .task {
                guard !reduceMotion, !played else { return }
                for next in 2...Self.pageCount {
                    try? await Task.sleep(for: .seconds(Self.hold))
                    if Task.isCancelled { return }
                    page = next
                }
                played = true
            }
        }
    }
}
