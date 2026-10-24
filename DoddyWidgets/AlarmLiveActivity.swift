#if canImport(AlarmKit)
import AlarmKit
import AppIntents
import DoddyCore
import SwiftUI
import WidgetKit

/// AlarmKit's Live Activity for Doddy, on the Lock Screen and in the Dynamic Island. AlarmKit
/// draws the ringing screen itself; this draws the time in between:
/// - a voice timer (ADR-611): the label, the countdown ticking on its own (no app updates, so it
///   never stutters), Pause or Resume, and Stop; when it rings, "Time's up" and Stop;
/// - a snoozed alarm (ADR-283): the minutes until it rings again, as before.
/// Doddy is on the cream card like his other Lock Screen cards (ADR-323), unless his pictures are
/// hidden (ADR-331).
@available(iOS 26.0, *)
struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<DoddyAlarmMetadata>.self) { context in
            Group {
                if context.attributes.metadata?.kind == .timer {
                    TimerLockScreenView(attributes: context.attributes, state: context.state)
                } else {
                    HStack(spacing: 12) {
                        WidgetPose(pose: .yawnStretch, height: 64)
                        Label("Snoozed", systemImage: "zzz")
                            .font(.headline)
                        Spacer()
                        AlarmCountdownText(state: context.state)
                            .font(.title2.monospacedDigit())
                    }
                    .padding()
                }
            }
            .doddyCreamLockScreen()
        } dynamicIsland: { context in
            context.attributes.metadata?.kind == .timer ? Self.timerIsland(context) : Self.snoozeIsland(context)
        }
    }

    private static func snoozeIsland(_ context: ActivityViewContext<AlarmAttributes<DoddyAlarmMetadata>>) -> DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                if WidgetDoddyArt.isHidden {
                    Image(systemName: "alarm")
                } else {
                    IslandPoseView(pose: .yawnStretch, maxSize: CGSize(width: 44, height: 52))
                        .padding(.leading, 6)
                }
            }
            DynamicIslandExpandedRegion(.trailing) { AlarmCountdownText(state: context.state).monospacedDigit() }
            DynamicIslandExpandedRegion(.bottom) { Text("Snoozed").font(.caption) }
        } compactLeading: {
            Image(systemName: "zzz")
        } compactTrailing: {
            AlarmCountdownText(state: context.state).monospacedDigit().frame(maxWidth: 44)
        } minimal: {
            Image(systemName: "alarm")
        }
    }

    private static func timerIsland(_ context: ActivityViewContext<AlarmAttributes<DoddyAlarmMetadata>>) -> DynamicIsland {
        let timer = TimerCard(attributes: context.attributes, state: context.state)
        return DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                if WidgetDoddyArt.isHidden {
                    Image(systemName: "timer")
                        .font(.title2)
                        .foregroundStyle(Color.islandOrange)
                        .padding(.leading, 8)
                } else {
                    IslandPoseView(pose: timer.pose, maxSize: CGSize(width: 44, height: 52))
                        .padding(.leading, 6)
                }
            }
            DynamicIslandExpandedRegion(.trailing) {
                AlarmCountdownText(state: context.state)
                    .font(.title.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.islandOrange)
                    .padding(.trailing, 8)
            }
            DynamicIslandExpandedRegion(.bottom) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timer.eyebrow)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.islandSecondary)
                        timer.title
                            .font(.headline)
                            .foregroundStyle(Color.islandCream)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    TimerButtons(card: timer)
                }
                .padding(.horizontal, 8)
            }
        } compactLeading: {
            Image(systemName: timer.isPaused ? "pause.fill" : "timer")
                .foregroundStyle(Color.islandOrange)
        } compactTrailing: {
            AlarmCountdownText(state: context.state)
                .monospacedDigit()
                .foregroundStyle(Color.islandOrange)
                .frame(maxWidth: 52)
        } minimal: {
            Image(systemName: timer.isPaused ? "pause.fill" : "timer")
                .foregroundStyle(Color.islandOrange)
        }
        .keylineTint(Color.islandOrange)
    }
}

/// What a timer's card shows in its current state, in the words the app set it with.
@available(iOS 26.0, *)
private struct TimerCard {
    let attributes: AlarmAttributes<DoddyAlarmMetadata>
    let state: AlarmPresentationState

    var language: NotificationLanguage {
        attributes.metadata?.language.flatMap(NotificationLanguage.init(rawValue:)) ?? .current
    }

    var isPaused: Bool {
        if case .paused = state.mode { return true }
        return false
    }

    var isRinging: Bool {
        if case .alert = state.mode { return true }
        return false
    }

    /// Waiting, sitting it out while paused, or celebrating when it is done.
    var pose: IslandPose {
        if isRinging { return .fistpump }
        return isPaused ? .crosslegged : .leaning
    }

    var eyebrow: String {
        let timer = TimerCopy.title(label: nil, language).uppercased()
        if isPaused { return "\(timer) · \(TimerCopy.paused(language).uppercased())" }
        return timer
    }

    /// The label the user asked for (or "Timer"); "Time's up" while it rings.
    @ViewBuilder var title: some View {
        if isRinging {
            Text(TimerCopy.notificationTitle(language))
        } else if let countdown = attributes.presentation.countdown {
            Text(countdown.title)
        } else {
            Text(TimerCopy.title(label: nil, language))
        }
    }
}

/// Pause or Resume, and Stop, as the island's pills. While it rings only Stop (Repeat is on
/// AlarmKit's own ringing screen).
@available(iOS 26.0, *)
private struct TimerButtons: View {
    let card: TimerCard

    var body: some View {
        let id = card.state.alarmID
        HStack(spacing: 6) {
            if !card.isRinging {
                if card.isPaused {
                    Button(intent: ResumeDoddyTimerIntent(alarmID: id)) {
                        IslandPillLabel(title: TimerCopy.button(.resume, card.language), systemImage: "play.fill", prominent: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(intent: PauseDoddyTimerIntent(alarmID: id)) {
                        IslandPillLabel(title: TimerCopy.button(.pause, card.language), systemImage: "pause.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            Button(intent: StopDoddyTimerIntent(alarmID: id)) {
                IslandPillLabel(title: TimerCopy.button(.stop, card.language), systemImage: "stop.fill", prominent: card.isRinging)
            }
            .buttonStyle(.plain)
        }
    }
}

/// The Lock Screen card of a timer: Doddy, the label, the time left and the buttons.
@available(iOS 26.0, *)
private struct TimerLockScreenView: View {
    let attributes: AlarmAttributes<DoddyAlarmMetadata>
    let state: AlarmPresentationState

    var body: some View {
        let card = TimerCard(attributes: attributes, state: state)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                if WidgetDoddyArt.isHidden {
                    Image(systemName: "timer")
                        .font(.title)
                        .foregroundStyle(Color("AccentText"))
                        .frame(width: 44, height: 64)
                } else {
                    WidgetPose(pose: card.pose, height: 64)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.eyebrow)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color("SecondaryText"))
                    card.title
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color("Ink"))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                AlarmCountdownText(state: state)
                    .font(.title.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color("AccentText"))
            }
            TimerButtons(card: card)
        }
        .padding(16)
    }
}

/// The time left: ticking on its own while it counts down, still while paused, and nothing once
/// it rings (AlarmKit's own screen is up then).
@available(iOS 26.0, *)
private struct AlarmCountdownText: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            // Never a backwards range, even if this draws after the time was due (ADR-331).
            Text(timerInterval: Date.now...max(Date.now, countdown.fireDate), countsDown: true)
        case .paused(let paused):
            let left = max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)
            Text(Duration.seconds(left).formatted(.time(pattern: left >= 3_600 ? .hourMinuteSecond : .minuteSecond)))
        default:
            Image(systemName: "alarm")
        }
    }
}
#endif
