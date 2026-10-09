import DoddyCore
import SwiftUI

/// Guided Back Tap setup: each step has a button that opens the exact screen to change, the
/// remaining taps written out, and a tap test at the end. Doddy cannot see Settings or
/// Shortcuts; it only knows when its own Open Doddy action opened it.
struct BackTapSetupView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PreferenceKey.lastOpenedByShortcut) private var lastOpenedByShortcut: Double = 0
    @AppStorage(PreferenceKey.tapTestStartedAt) private var tapTestStartedAt: Double = 0
    @AppStorage(PreferenceKey.backTapConfirmedAt) private var backTapConfirmedAt: Double = 0
    @State private var linkProblem: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Two taps on the back of your iPhone open Doddy.")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("Four steps. Each button below takes you to the exact place to change; come back here after each one.")
                            .foregroundStyle(Theme.secondaryText)
                    }

                    if let linkProblem {
                        ProblemView(message: linkProblem)
                    }

                    makeShortcutStep
                    openBackTapStep
                    chooseShortcutStep
                    tapTestStep

                    Text("iOS doesn't let apps change Back Tap or see what it's set to, so you make the change and Doddy only checks that its shortcut opened it. You can skip this; Doddy works the same without it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(24)
            }
            .background(Theme.canvas)
            .navigationTitle("Set up Back Tap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .accessibilityIdentifier("backTapSetup")
    }

    // MARK: Steps

    private var makeShortcutStep: some View {
        StepCard(number: 1, title: "Make the “\(BackTapSetup.shortcutName)” shortcut") {
            LinkButton(title: "New shortcut in Shortcuts", systemImage: "square.on.square") {
                open(.newShortcut)
            }
            .accessibilityIdentifier("backTap.newShortcut")
            Instructions(lines: [
                "Tap **Search Actions**, type **Open Doddy** and tap Doddy's **Open Doddy** action.",
                "Tap the name at the top, choose **Rename** and call it **\(BackTapSetup.shortcutName)**.",
                "Tap **Done**.",
            ])
            Text("Use Doddy's Open Doddy action, not the general Open App action: only Doddy's own action lets the test in step 4 notice it.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            LinkButton(title: "Try the shortcut", systemImage: "play") { open(.runShortcut) }
                .accessibilityIdentifier("backTap.tryShortcut")
            Label {
                Text(lastOpenedByShortcut > 0
                     ? "The shortcut last opened Doddy \(Self.relative(lastOpenedByShortcut))."
                     : "Not run yet. If Shortcuts says it can't find it, check the name is exactly “\(BackTapSetup.shortcutName)”.")
            } icon: {
                Image(systemName: lastOpenedByShortcut > 0 ? "checkmark.circle" : "circle.dashed")
            }
            .font(.footnote)
            .foregroundStyle(lastOpenedByShortcut > 0 ? Theme.confirmed : Theme.secondaryText)
        }
    }

    private var openBackTapStep: some View {
        StepCard(number: 2, title: "Open Back Tap settings") {
            LinkButton(title: "Open Back Tap settings", systemImage: "gearshape") { open(.backTapSettings) }
                .accessibilityIdentifier("backTap.openSettings")
            Text("If Settings opens on a different page, go to **\(BackTapSetup.settingsPath.dropFirst().joined(separator: " → "))**. Back Tap is near the bottom of Touch.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var chooseShortcutStep: some View {
        StepCard(number: 3, title: "Choose the shortcut") {
            Instructions(lines: [
                "Tap **Double Tap**.",
                "Scroll down to **Shortcuts** and tap **\(BackTapSetup.shortcutName)**. A tick appears next to it.",
                "Come back to Doddy.",
            ])
            Text("Prefer three taps? Use **Triple Tap** instead; the test works the same.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var tapTestStep: some View {
        StepCard(number: 4, title: "Test it") {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                tapTest(now: context.date)
            }
        }
    }

    @ViewBuilder
    private func tapTest(now: Date) -> some View {
        let state = TapTestState.evaluate(
            testStartedAt: Self.date(tapTestStartedAt), lastShortcutOpenAt: Self.date(lastOpenedByShortcut), now: now)
        switch state {
        case .notStarted:
            if backTapConfirmedAt > 0 {
                Label("You confirmed \(Self.relative(backTapConfirmedAt)) that a double tap opens Doddy.", systemImage: "checkmark.circle")
                    .foregroundStyle(Theme.confirmed)
                Button("Test again") { startTest() }
                    .buttonStyle(SecondaryButtonStyle())
            } else {
                Button("Start the tap test") { startTest() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("backTap.startTest")
            }
        case .waiting:
            Instructions(lines: [
                "Swipe up to go to the Home Screen.",
                "Double-tap the back of your iPhone, near the camera.",
                "Doddy should open right here.",
            ])
            Button("Cancel test") { tapTestStartedAt = 0 }
                .buttonStyle(SecondaryButtonStyle())
        case .openedByShortcut(let at):
            Text("The \(BackTapSetup.shortcutName) shortcut just opened Doddy (\(at.formatted(date: .omitted, time: .shortened))). Was that your double tap?")
            Button("Yes, my double tap opened it") {
                backTapConfirmedAt = at.timeIntervalSince1970
                tapTestStartedAt = 0
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("backTap.confirm")
            Button("No, I opened it another way") { startTest() }
                .buttonStyle(SecondaryButtonStyle())
        case .timedOut:
            Text("Doddy wasn't opened by the shortcut. Check that:")
            Instructions(lines: [
                "the shortcut uses Doddy's **Open Doddy** action (step 1, Try the shortcut),",
                "**Double Tap** shows a tick next to **\(BackTapSetup.shortcutName)** (step 2),",
                "your case isn't too thick for taps to register.",
            ])
            Button("Try again") { startTest() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: Actions

    private func startTest() {
        tapTestStartedAt = Date().timeIntervalSince1970
    }

    /// Opens the first URL iOS accepts. iOS can accept a Settings URL and still show another
    /// page, which is why step 2 always shows the path too.
    private func open(_ link: BackTapSetup.Link) {
        linkProblem = nil
        open(link.candidates[...])
    }

    private func open(_ urls: ArraySlice<URL>) {
        guard let url = urls.first else {
            linkProblem = "iPhone didn't open that. Open the Settings or Shortcuts app yourself and follow the steps below."
            return
        }
        openURL(url) { accepted in
            guard !accepted else { return }
            Task { @MainActor in open(urls.dropFirst()) }
        }
    }

    private static func date(_ seconds: Double) -> Date? {
        seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }

    private static func relative(_ seconds: Double) -> String {
        Date(timeIntervalSince1970: seconds).formatted(.relative(presentation: .named))
    }
}

// MARK: Components

private struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(number)")
                    .font(.headline)
                    .frame(minWidth: 28, minHeight: 28)
                    .background(Theme.quietSurface, in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .accessibilityLabel("Step \(number): \(title)")
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.separator, lineWidth: 1))
    }
}

private struct LinkButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(SecondaryButtonStyle(tint: Theme.accentText))
        .accessibilityHint("Opens another app")
    }
}

/// Numbered sub-steps; `**bold**` marks the exact labels shown on screen.
private struct Instructions: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1).")
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryText)
                    Text(.init(line))
                }
            }
        }
    }
}
