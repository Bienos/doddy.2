import DoddyCore
import SwiftUI

/// Written Double Back Tap guide (design v1.2 "Two taps. A little help."). Voice guidance
/// isn't built: nothing listens during setup. Doddy can't see the user's screen or read the
/// Back Tap setting, so every step moves on the user's own report.
struct SetupGuideView: View {
    let step: SetupStep

    @Environment(ProfileStore.self) private var profiles

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: SetupWelcomeView(go: { go($0) }, setUpLater: { setUpLater() })
                case .shortcut: SetupShortcutView(go: { go($0) }, setUpLater: { setUpLater() })
                case .test: SetupTestView(go: { go($0) }, finish: { finish(testPassed: $0) }, setUpLater: { setUpLater() })
                default:
                    // New identity per page: each card starts at the top, and VoiceOver resets.
                    SetupWalkthroughView(step: step, go: { go($0) }, setUpLater: { setUpLater() })
                        .id(step)
                }
            }
            .frame(maxHeight: .infinity)
            if let problem = profiles.progressSaveProblem {
                ProblemView(message: problem)
                    .font(.footnote)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
        }
    }

    private func go(_ next: SetupStep) {
        Task { await profiles.updateProgress { $0.guiding(to: next, at: .now) } }
    }

    private func setUpLater() {
        Task { await profiles.setUpLater() }
    }

    private func finish(testPassed: Bool) {
        Task { await profiles.finishSetup(testPassed: testPassed) }
    }
}

private struct SetUpLaterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack { Text("Set this up later"); Image(systemName: "arrow.right") }
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .foregroundStyle(Theme.secondaryText)
        .accessibilityIdentifier("setup.later")
    }
}

// MARK: Welcome

private struct SetupWelcomeView: View {
    let go: (SetupStep) -> Void
    let setUpLater: () -> Void

    var body: some View {
        OnboardingPage {
            OnboardingLabel(text: "A quick way to find me")
            Text("Two taps.\nA little help.")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("First, let's make Doddy easy to reach. I'll walk you through Double Back Tap, one step at a time: double-tap the back of your iPhone and Doddy opens.")

            CandidateCharacterView(assetName: "Doddy_waving")
                .frame(maxWidth: .infinity)

            CalloutView(
                title: "Written steps, at your pace",
                message: "Voice guidance isn't built yet, so nothing listens during setup. You change the setting yourself in the Settings app; Doddy can't change it for you.")

            Button { go(.shortcut) } label: {
                HStack { Text("Show me how"); Spacer(); Image(systemName: "arrow.right") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("setup.start")

            SetUpLaterButton(action: setUpLater)
        }
    }
}

// MARK: Shortcut

private struct SetupShortcutView: View {
    let go: (SetupStep) -> Void
    let setUpLater: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var showHelp = false

    var body: some View {
        OnboardingPage {
            OnboardingLabel(text: "First, the shortcut")
            Text("Give those taps a destination.")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Back Tap runs a shortcut. Create a personal shortcut named **Open Doddy** in the Shortcuts app, and it can appear in the Back Tap list.")

            NumberedSteps(items: [
                "Open Shortcuts and create a new shortcut.",
                "Add Doddy's **Open Doddy** action. If you can't find it, use the **Open App** action and choose Doddy.",
                "Name the shortcut **Open Doddy**, save it and run it once.",
            ])

            Button {
                openURL(URL(string: "shortcuts://create-shortcut")!)
            } label: {
                HStack { Text("Open Shortcuts"); Spacer(); Image(systemName: "arrow.up.forward.app") }
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("setup.openShortcuts")

            DisclosureGroup("I can't find the action", isExpanded: $showHelp) {
                Text("In the shortcut editor, search the actions for \"Doddy\". Doddy's action appears after Doddy has been opened at least once. If it still isn't there, search for \"Open App\" and choose Doddy; that works for Back Tap too.")
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 4)
            }
            .accessibilityIdentifier("setup.shortcutHelp")

            Button { go(.openSettings) } label: {
                HStack { Text("I created the shortcut"); Spacer(); Image(systemName: "arrow.right") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("setup.shortcutDone")

            Text("Doddy can't see whether the shortcut exists. Tapping the button is your report.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)

            HStack {
                Button("Back") { go(.welcome) }
                    .accessibilityIdentifier("setup.previous")
                Spacer()
            }
            SetUpLaterButton(action: setUpLater)
        }
    }
}

// MARK: Settings walkthrough

/// One card per Settings page. The user taps where they are; the card says what to do there.
private struct SetupWalkthroughView: View {
    let step: SetupStep
    let go: (SetupStep) -> Void
    let setUpLater: () -> Void

    private var copy: SetupPageCopy? { SetupGuideCopy.page(step) }
    private var number: Int { (SetupStep.walkthrough.firstIndex(of: step) ?? 0) + 1 }

    var body: some View {
        OnboardingPage {
            OnboardingLabel(text: "Settings walkthrough · step \(number) of \(SetupStep.walkthrough.count)")
            if let copy {
                Text(copy.title)
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(copy.path)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityLabel("Where: \(copy.path)")
                DoddySaysCard(text: copy.instruction)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Tell Doddy where you are")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(SetupStep.walkthrough, id: \.self) { page in
                    if let report = SetupGuideCopy.page(page)?.report {
                        Button { go(page) } label: {
                            HStack {
                                Text(report)
                                Spacer()
                                if page == step {
                                    Image(systemName: "checkmark").accessibilityHidden(true)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(
                                page == step ? Theme.quietSurface : .clear,
                                in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.separator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(page == step ? .isSelected : [])
                        .accessibilityIdentifier("setup.report.\(page.rawValue)")
                    }
                }
            }

            if step == .doubleTap {
                Button { go(.test) } label: {
                    HStack { Text("I chose Open Doddy"); Spacer(); Image(systemName: "arrow.right") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("setup.next")
            } else if let next = step.next, let nextCopy = SetupGuideCopy.page(next) {
                Button { go(next) } label: {
                    HStack { Text("Done. \(nextCopy.report)"); Spacer(); Image(systemName: "arrow.right") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("setup.next")
            }

            HStack {
                if let previous = step.previous {
                    Button("Previous step") { go(previous) }
                        .accessibilityIdentifier("setup.previous")
                }
                Spacer()
            }

            Text("Full path: \(SetupGuideCopy.fullPath)")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)

            SetUpLaterButton(action: setUpLater)
        }
    }
}

// MARK: Test

/// A real-world check. Doddy can tell whether its Open Doddy action ran during the test, but
/// never whether a double tap started it, so the user is asked.
private struct SetupTestView: View {
    let go: (SetupStep) -> Void
    let finish: (Bool) -> Void
    let setUpLater: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var window: TapTestWindow?
    @State private var cameBack = false
    @State private var showTroubleshooting = false

    private var receipts: OpenDoddyReceipts { .shared }
    private var receivedDuringTest: Bool { window?.accepts(receiptAt: receipts.lastReceivedAt) ?? false }

    var body: some View {
        OnboardingPage {
            OnboardingLabel(text: "A small real-world check")
            Text("Try your two taps.")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)

            NumberedSteps(items: [
                "Go to the Home Screen.",
                "Double-tap the back of your iPhone, near the camera.",
                "If Back Tap is set up, Open Doddy brings you back here.",
            ])

            CandidateCharacterView(assetName: "Doddy_listening", size: 140)
                .frame(maxWidth: .infinity)

            if cameBack {
                CalloutView(
                    title: "Welcome back.",
                    message: receivedDuringTest
                        ? "Your Open Doddy shortcut ran just now. Doddy can't tell what started it. Was it your double tap?"
                        : "Doddy can't tell how it was opened. If your shortcut uses Open App, that's expected. Did your double tap bring you here?")
                    .accessibilityIdentifier("setup.testReturned")
            }

            Button { finish(true) } label: {
                HStack { Text("Yes, a double tap opened Doddy"); Spacer(); Image(systemName: "checkmark") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("setup.testWorked")

            Button { showTroubleshooting.toggle() } label: {
                Text("It didn't work")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("setup.testFailed")

            if showTroubleshooting {
                VStack(alignment: .leading, spacing: 12) {
                    Text("A few things to check")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    NumberedSteps(items: [
                        "In Back Tap → Double Tap, make sure Open Doddy has a tick.",
                        "Run the Open Doddy shortcut once in the Shortcuts app.",
                        "Tap firmly twice, near the camera. Some thick cases block Back Tap.",
                    ])
                    Button("Go back to the Back Tap steps") { go(.backTap) }
                        .accessibilityIdentifier("setup.testBackToSteps")
                }
                .padding(16)
                .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
            }

            Button("Finish without testing") { finish(false) }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("setup.testSkip")

            HStack {
                Button("Previous step") { go(.doubleTap) }
                    .accessibilityIdentifier("setup.previous")
                Spacer()
            }
            SetUpLaterButton(action: setUpLater)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // The test starts when the user leaves Doddy; older receipts don't count.
                window = TapTestWindow(startedAt: .now)
                cameBack = false
            case .active:
                if window != nil { cameBack = true }
            default:
                break
            }
        }
    }
}

/// Numbered list that reads correctly with VoiceOver and large text.
struct NumberedSteps: View {
    let items: [LocalizedStringKey]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1).")
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                    Text(item)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
