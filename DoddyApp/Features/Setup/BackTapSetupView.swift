import DoddyCore
import SwiftUI
import UIKit

/// Guided Double Back Tap setup (design v1.2, "Two taps. A little help."). Step cards follow the
/// page the user reports; the tap test waits for Doddy's own shortcut to open the app, then asks
/// the user how they triggered it. Nothing here reads iOS Settings or assigns anything.
struct BackTapSetupView: View {
    let model: BackTapSetupModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .padding(24)
            }
            .background(Theme.canvas)
            .navigationTitle("A little setup help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .foregroundStyle(Theme.ink)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .notStarted, .deferred:
            intro
        case .shortcutPreparation:
            shortcutPreparation
        case .guiding(let index):
            guide(stepIndex: index)
        case .testing(let window):
            test(window)
        case .receiptReceived(_, let receivedAt):
            received(at: receivedAt)
        case .userReportedTested(let at):
            done(at: at)
        }
    }

    // MARK: Screens

    private var intro: some View {
        Group {
            miniLabel("A quick way to find me")
            Text("Two taps.\nA little help.")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("First, let's make Doddy easy to reach. I'll walk you through Double Back Tap, one step at a time.")
            CandidateCharacterView(assetName: "Doddy_approaching")
                .frame(maxWidth: .infinity)
            Button {
                model.send(.start)
            } label: {
                HStack { Text("Set up Double Back Tap"); Spacer(); Image(systemName: "arrow.right") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("setup.start")
            Button("Set this up later") {
                model.send(.deferSetup)
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("setup.later")
            hint("You choose the shortcut in iPhone Settings. Doddy can't change your phone's settings and can't see what they are set to.")
        }
    }

    private var shortcutPreparation: some View {
        Group {
            miniLabel("First, the shortcut")
            Text("Give those taps a destination.")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Back Tap runs a shortcut from the Shortcuts app, so create a personal one named \(BackTapGuide.shortcutName).")
            VStack(alignment: .leading, spacing: 12) {
                numbered(1, "Open the Shortcuts app and tap the plus button.")
                numbered(2, "Search for Doddy and add \"Talk to Doddy\". If it isn't offered, add \"Open App\" and choose Doddy.")
                numbered(3, "Name the shortcut \(BackTapGuide.shortcutName), tap Done, then run it once.")
            }
            callout("If Back Tap already lists \"Talk to Doddy\" on your iPhone, you can choose that there instead of creating one.")
            Button {
                model.send(.shortcutReady)
            } label: {
                HStack { Text("I created the shortcut"); Spacer(); Image(systemName: "arrow.right") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("setup.shortcutReady")
            Button("Set this up later") {
                model.send(.deferSetup)
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())
            hint("Doddy can't check whether the shortcut exists. This button is your report.")
        }
    }

    private func guide(stepIndex: Int) -> some View {
        let steps = BackTapGuide.steps
        let step = steps[min(max(stepIndex, 0), steps.count - 1)]
        let isLast = stepIndex >= steps.count - 1
        return Group {
            miniLabel("Settings walkthrough")
            Text(step.title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(step.route)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            doddySays(step.instruction)

            if stepIndex == 0 {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Label("Open iPhone Settings", systemImage: "gear")
                }
                .buttonStyle(SecondaryButtonStyle())
                hint("This opens Doddy's own page in Settings. Tap Settings at the top left to reach the main list.")
            }

            if !isLast {
                miniLabel("Tell Doddy where you are")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(Array(BackTapGuide.reportableSteps.enumerated()), id: \.element.id) { index, reportable in
                        Button(reportable.reportLabel) {
                            model.send(.report(page: reportable.id))
                        }
                        .buttonStyle(ChipButtonStyle(isSelected: index == stepIndex))
                    }
                }
            }

            Button {
                model.send(isLast ? .startTest(now: .now) : .next)
            } label: {
                HStack { Text(isLast ? "Start the tap test" : "Next step"); Spacer(); Image(systemName: "arrow.right") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier(isLast ? "setup.startTest" : "setup.next")
            Button("Previous step") { model.send(.previous) }
                .buttonStyle(SecondaryButtonStyle())
            if !isLast {
                Button("Skip ahead to the tap test") { model.send(.startTest(now: .now)) }
                    .font(.footnote)
                    .foregroundStyle(Theme.accentText)
            }
            hint("Guidance follows what you report, not your screen. Doddy can't see Settings and can't assign Back Tap for you.")
        }
    }

    private func test(_ window: BackTapTestWindow) -> some View {
        Group {
            miniLabel("A small real-world check")
            Text("Try your two taps.")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Go to your Home Screen, then double-tap the back of your iPhone. The shortcut should bring you back to Doddy.")
            CandidateCharacterView(assetName: "Doddy_approaching")
                .frame(maxWidth: .infinity)
            TimelineView(.periodic(from: window.startedAt, by: 1)) { context in
                if window.isActive(at: context.date) {
                    let remaining = max(0, Int(window.expiresAt.timeIntervalSince(context.date).rounded(.up)))
                    callout("Waiting for your shortcut. The test stays open for \(remaining) more seconds.")
                        .accessibilityIdentifier("setup.waiting")
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        callout("The test timed out. Nothing was marked as set up.")
                        Button {
                            model.send(.startTest(now: .now))
                        } label: {
                            HStack { Text("Start the test again"); Spacer(); Image(systemName: "arrow.clockwise") }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
            Button("It didn't work, show me the steps") {
                model.send(.report(page: BackTapGuide.steps[BackTapGuide.chooseShortcutStepIndex].id))
            }
            .buttonStyle(SecondaryButtonStyle())
            Button("Finish setup later") {
                model.send(.deferSetup)
                dismiss()
            }
            .font(.footnote)
            .foregroundStyle(Theme.accentText)
            hint("A received shortcut proves the route reached Doddy. You then say whether Double Back Tap triggered it.")
        }
    }

    private func received(at date: Date) -> some View {
        Group {
            miniLabel("Your shortcut reached Doddy")
            Text("That worked.")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Doddy's shortcut ran at \(date.formatted(date: .omitted, time: .shortened)). Did Double Back Tap trigger it, or did you run the shortcut another way?")
            Button {
                model.send(.confirmDoubleTap(now: .now))
            } label: {
                HStack { Text("Yes, I used Double Back Tap"); Spacer(); Image(systemName: "checkmark") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("setup.confirmTap")
            Button("I ran it another way") { model.send(.otherTrigger) }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("setup.otherTrigger")
            hint("Only you can tell which gesture ran it. iOS doesn't report that to apps.")
        }
    }

    private func done(at date: Date) -> some View {
        Group {
            CandidateCharacterView(assetName: "Doddy_listening")
                .frame(maxWidth: .infinity)
            Label("Tested by you · \(DateText.full(date))", systemImage: "checkmark.seal")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.confirmed)
            Text("An easier way to say hey.")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Double-tap the back of your iPhone to start talking to Doddy. \"Talk to Doddy\" also works with Siri, in the Shortcuts app and from the Action Button on iPhones that have one.")
            hint("This is your report. iOS doesn't tell apps what Back Tap is set to, so Doddy hasn't verified it and never will claim to.")
            Button {
                dismiss()
            } label: {
                HStack { Text("Done"); Spacer(); Image(systemName: "checkmark") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("setup.done")
            Button("Go through the steps again") { model.send(.revisit) }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: Pieces

    private func miniLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .kerning(1.2)
            .foregroundStyle(Theme.secondaryText)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
    }

    private func callout(_ text: String) -> some View {
        Text(text)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func doddySays(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.orangeCue)
                .frame(width: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Doddy")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                Text(text)
                    .font(.title3)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func numbered(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number).")
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Selectable report chip ("I'm in Touch"). The selected state is shown by weight and fill, not colour alone.
struct ChipButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isSelected ? .subheadline.weight(.semibold) : .subheadline)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                Capsule()
                    .strokeBorder(isSelected ? Theme.ink : Theme.separator, lineWidth: isSelected ? 1.5 : 1)
                    .background(isSelected || configuration.isPressed ? Theme.quietSurface : .clear, in: Capsule()))
            .contentShape(Capsule())
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
