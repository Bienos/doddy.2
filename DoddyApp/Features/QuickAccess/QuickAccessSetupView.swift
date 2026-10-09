import DoddyCore
import SwiftUI
import UIKit

/// Guided Double Back Tap setup (design v1.2 "Two taps. A little help."), as step cards.
/// Doddy can't change or see iPhone Settings: the steps follow what the user reports, and the
/// tap test records "tested by you" only after a shortcut really arrived and the user confirmed
/// it was Back Tap.
struct QuickAccessSetupView: View {
    private enum Stage: Equatable {
        case intro, shortcut, step(Int), test, done
    }

    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PreferenceKey.backTapTestedAt) private var backTapTestedAt = 0.0
    @State private var stage: Stage = .intro

    private let steps = BackTapGuide.settingsSteps

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch stage {
                case .intro: intro
                case .shortcut: shortcut
                case .step(let index): guide(index)
                case .test: test
                case .done: done
                }
            }
            .padding(24)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
        .navigationTitle("A little setup help")
        .navigationBarTitleDisplayMode(.inline)
        // A test left armed would swallow the next "Talk to Doddy".
        .onDisappear { router.shortcutTest.reset() }
        .onChange(of: router.shortcutTest.phase) { _, phase in
            if case .received = phase { UIAccessibility.post(notification: .announcement, argument: "The shortcut reached Doddy.") }
        }
    }

    // MARK: Stages

    private var intro: some View {
        Group {
            MiniLabel("A quick way to find me")
            Text("Two taps.\nA little help.")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Let's make Doddy easy to reach. I'll walk you through Double Back Tap, one step at a time. Then double-tapping the back of your iPhone opens a conversation.")
                .foregroundStyle(Theme.secondaryText)
            CandidateCharacterView(assetName: "Doddy_waving", size: 140)
                .frame(maxWidth: .infinity)
            Button { stage = .shortcut } label: {
                HStack { Text("Set up Double Back Tap"); Spacer(); Image(systemName: "arrow.right") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("setup.start")
            Text("You choose the shortcut in iPhone Settings. Doddy can't change or see your settings.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)

            otherWays
        }
    }

    private var otherWays: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Other quick ways")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 12)
            WayRow(icon: "mic", title: "Siri", detail: "Say “Talk to Doddy”, “Save to Doddy” or “Ask Doddy”.")
            WayRow(icon: "button.horizontal.top.press", title: "Action Button",
                   detail: "iPhone 15 Pro and later: Settings → Action Button → Shortcut → Doddy → Talk to Doddy.")
            WayRow(icon: "switch.2", title: "Control Center",
                   detail: "iOS 18 and later: open Control Center, tap +, Add a Control, then choose Doddy.")
        }
    }

    private var shortcut: some View {
        Group {
            MiniLabel("First, the shortcut")
            Text("Give those taps a destination.")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Text(BackTapGuide.makeShortcut.instruction)
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Open Shortcuts and tap +.")
                Text("2. Search for Doddy and add **Talk to Doddy**.")
                Text("3. Tap Done. The shortcut is called Talk to Doddy.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
            Button {
                if let url = URL(string: "shortcuts://create-shortcut") { UIApplication.shared.open(url) }
            } label: {
                HStack { Text("Open Shortcuts"); Spacer(); Image(systemName: "arrow.up.forward.app") }
            }
            .buttonStyle(SecondaryButtonStyle())
            Button { stage = .step(0) } label: {
                HStack { Text(BackTapGuide.makeShortcut.report); Spacer(); Image(systemName: "arrow.right") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("setup.shortcutDone")
            Text("Can't find Talk to Doddy? Add the Open App action instead, choose Doddy, and name the shortcut Talk to Doddy. Doddy can't see your shortcuts, so this button is your report.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func guide(_ index: Int) -> some View {
        let step = steps[index]
        let isLast = index == steps.count - 1
        return Group {
            MiniLabel("Step \(index + 1) of \(steps.count)")
            Text(step.title)
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Text(step.route)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            VStack(alignment: .leading, spacing: 6) {
                Text("Doddy")
                    .font(.footnote.bold())
                    .foregroundStyle(Theme.accentText)
                Text(step.instruction)
            }
            .padding(.leading, 14)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.orangeCue).frame(width: 3) }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 8) {
                MiniLabel("Tell Doddy where you are")
                ForEach(Array(steps.enumerated()), id: \.element.id) { offset, other in
                    Button(other.report) { stage = .step(offset) }
                        .buttonStyle(ChipButtonStyle(isSelected: offset == index))
                        .accessibilityAddTraits(offset == index ? .isSelected : [])
                }
            }

            Button { stage = isLast ? .test : .step(index + 1) } label: {
                HStack { Text(isLast ? "I chose Talk to Doddy" : "Next step"); Spacer(); Image(systemName: "arrow.right") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("setup.next")
            HStack {
                Button("Previous step") { stage = index == 0 ? .shortcut : .step(index - 1) }
                Spacer()
                Button("Go to the tap test") { stage = .test }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.accentText)
            Text("Guidance follows what you tell Doddy. Doddy can't see your screen or open these Settings pages.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var test: some View {
        Group {
            MiniLabel("A small real-world check")
            Text("Try your two taps.")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Tap Start the test, then double-tap the back of your iPhone. The shortcut should reach Doddy here instead of starting a conversation.")
            CandidateCharacterView(assetName: "Doddy_listening", size: 120)
                .frame(maxWidth: .infinity)

            switch router.shortcutTest.phase {
            case .idle, .confirmedBackTap:
                Button { router.shortcutTest.start() } label: {
                    HStack { Text("Start the test"); Spacer(); Image(systemName: "hand.tap") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("setup.startTest")
            case .waiting:
                Callout(title: "Waiting for the shortcut…",
                        detail: "Double-tap the back of your iPhone now. Nothing happens until a shortcut reaches Doddy.")
                    .accessibilityIdentifier("setup.waiting")
                Button("Stop the test") { router.shortcutTest.reset() }
                    .buttonStyle(SecondaryButtonStyle())
            case .received:
                Callout(title: "The shortcut reached Doddy.",
                        detail: "iOS doesn't tell Doddy what ran it. Did you use Double Back Tap?")
                    .accessibilityIdentifier("setup.received")
                Button {
                    router.shortcutTest.confirmBackTap()
                    if case .confirmedBackTap(let date) = router.shortcutTest.phase {
                        backTapTestedAt = date.timeIntervalSince1970
                        stage = .done
                    }
                } label: {
                    HStack { Text("Yes, I used Double Back Tap"); Spacer(); Image(systemName: "checkmark") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("setup.confirmBackTap")
                Button("I ran it another way") {
                    router.shortcutTest.reset()
                    stage = .step(0)
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            HStack {
                Button("It didn't work, show the steps") {
                    router.shortcutTest.reset()
                    stage = .step(0)
                }
                Spacer()
                Button("Finish later") { dismiss() }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.accentText)
            Text("A shortcut arriving shows it reached Doddy. Only you know it was Back Tap.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var done: some View {
        Group {
            Label("Tested by you", systemImage: "checkmark.seal")
                .font(.headline)
                .foregroundStyle(Theme.confirmed)
            Text("An easier way to say hey.")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Text("The shortcut reached Doddy and you confirmed it was Double Back Tap. Double-tap the back of your iPhone whenever you want to talk.")
            CandidateCharacterView(assetName: "Doddy_waving", size: 140)
                .frame(maxWidth: .infinity)
            Button { dismiss() } label: {
                HStack { Text("Done"); Spacer(); Image(systemName: "checkmark") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("setup.done")
        }
    }
}

// MARK: Small pieces

private struct MiniLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1)
            .foregroundStyle(Theme.secondaryText)
    }
}

private struct Callout: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(Theme.secondaryText)
        }
        .padding(.leading, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.orangeCue).frame(width: 3) }
        .accessibilityElement(children: .combine)
    }
}

private struct WayRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ChipButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                Capsule()
                    .strokeBorder(Theme.separator, lineWidth: 1)
                    .background(isSelected || configuration.isPressed ? Theme.quietSurface : .clear, in: Capsule()))
            .contentShape(Capsule())
    }
}
