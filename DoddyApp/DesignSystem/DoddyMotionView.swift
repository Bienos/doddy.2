import SwiftUI

/// Doddy moving (ADR-313): one of the pack's strips (`DoddyMotion`), frame by frame. A loop runs
/// while it is on screen; a once-only strip plays from when it appears and then rests on its last
/// frame (the timeline stops). With Reduce Motion one still frame shows instead. In dark
/// appearance the outline gets the island's thin cream edge. Decorative: hidden from VoiceOver,
/// and with "Hide Doddy's pictures".
struct DoddyMotionView: View {
    let motion: DoddyMotion
    var height: CGFloat = 96
    /// The box's width; nil: the strip's own width at this height.
    var width: CGFloat?
    /// False: the still frame only, without playing (ADR-323), e.g. an entry undone earlier.
    var playing = true
    @State private var start = Date()
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false

    var body: some View {
        if !hideCharacterArt {
            let box = motion.figure
            let size = CGSize(width: width ?? height * CGFloat(box.width / box.height) / 1.5, height: height)
            Group {
                if reduceMotion || !playing || motion.frames.count == 1 {
                    frame(motion.stillFrame, size)
                } else {
                    TimelineView(.animation(minimumInterval: motion.frameDuration, paused: finished)) { context in
                        frame(finished ? motion.stillFrame : motion.frame(at: context.date.timeIntervalSince(start)), size)
                    }
                }
            }
            .accessibilityHidden(true)
            .doddyArtMarker("doddy.motion.\(motion.rawValue)")
            .task(id: motion) {
                start = Date()
                finished = false
                guard !motion.loops else { return }
                try? await Task.sleep(for: .seconds(motion.duration))
                if !Task.isCancelled { finished = true }
            }
        }
    }

    private func frame(_ number: Int, _ size: CGSize) -> some View {
        IslandFigureView(assetName: motion.assetName(number), figure: motion.figure, maxSize: size,
                         edged: colorScheme == .dark)
    }
}
