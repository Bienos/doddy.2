import SwiftUI

/// Doddy on the voice screen (ADR-299): the same Whole Doddy pose as the island for what is
/// happening, and while he speaks the pack's talking frames in turn. Since ADR-313 he walks in
/// while connecting and runs while a plan's steps run. The frames only follow
/// the conversation's "speaking" state; they are not synced to the audio. With Reduce Motion
/// the first frame stays still and poses swap without a fade. Decorative: the status text
/// beside him says the same thing. Hidden with "Hide Doddy's pictures".
struct VoiceDoddyView: View {
    let art: VoiceScreenArt
    var height: CGFloat = 96
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false

    var body: some View {
        if !hideCharacterArt {
            // The animation sits on a container that stays, so the swap between poses fades
            // (on the view that changes identity it would never see `art` change).
            ZStack {
                figure
                    .id(art)
                    .transition(.opacity)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: art)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var figure: some View {
        // A fixed width, so the status text beside him doesn't move when the pose changes.
        let size = CGSize(width: height * 0.8, height: height)
        let edged = colorScheme == .dark
        switch art {
        case .pose(let pose):
            IslandPoseView(pose: pose, maxSize: size, edged: edged)
        case .motion(let motion):
            // Walking while connecting, running while a plan runs (ADR-313).
            DoddyMotionView(motion: motion, height: size.height, width: size.width)
        case .talking:
            if reduceMotion {
                IslandFigureView(assetName: VoiceScreenArt.talkingAssetName(1), figure: VoiceScreenArt.talkingFigure,
                                 maxSize: size, edged: edged)
            } else {
                TimelineView(.periodic(from: .now, by: VoiceScreenArt.talkingFrameDuration)) { context in
                    let frame = VoiceScreenArt.talkingFrame(at: context.date.timeIntervalSinceReferenceDate)
                    IslandFigureView(assetName: VoiceScreenArt.talkingAssetName(frame), figure: VoiceScreenArt.talkingFigure,
                                     maxSize: size, edged: edged)
                }
            }
        }
    }
}
