import SwiftUI

/// Doddy on the voice screen (ADR-299): the same Whole Doddy pose as the island for what is
/// happening, and while he speaks the pack's talking frames in turn. Since ADR-313 he walks in
/// while connecting and runs while a plan's steps run. Talking frames run only while provider audio
/// or the local message read-back is actually playing; neither provider exposes viseme timing, so
/// exact lip sync for generated conversation audio is unavailable. With Reduce Motion the first
/// frame stays still and poses swap without a fade.
/// Hidden with "Hide Doddy's pictures".
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

/// Maps the live provider state to the same character pose on Home and in the transcript screen.
@MainActor
func voiceScreenArt(for controller: VoiceSessionController) -> VoiceScreenArt {
    let phase: VoiceScreenArt.Phase
    if controller.isReadingMessageDraft {
        phase = .speaking
    } else {
        phase = switch controller.phase {
        case .idle, .connecting: .connecting
        case .listening: .listening
        case .thinking: .thinking
        case .speaking: .speaking
        case .ended: .ended
        case .microphoneDenied: .microphoneOff
        case .failed: .failed
        }
    }
    let planRunning = controller.planStatus.map { $0.isRunning && !$0.steps.isEmpty } ?? false
    return .shown(phase, muted: controller.isMuted && controller.isLive,
                  awaitingConfirmation: controller.pendingAction != nil && !controller.isReadingMessageDraft,
                  planRunning: planRunning)
}
