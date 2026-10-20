import DoddyCore
import SwiftUI
import UIKit

/// "Ways to open Doddy": Double Back Tap, the Action Button, a Control Center or Lock Screen control
/// and Siri, each one short screen away. Only Double Back Tap gets the guided test (its three steps
/// are one screen, and the test waits for Doddy's own shortcut to open the app, then asks how the
/// user triggered it). Nothing here reads iOS Settings, assigns anything or sees a control.
struct OpenDoddyWaysView: View {
    let model: BackTapSetupModel
    @Environment(\.dismiss) private var dismiss
    @State private var screen: Screen = .ways
    /// The phone storyboard has played (ADR-380), so coming back to the list doesn't replay it.
    @State private var phonePlayed = false

    private enum Screen: Equatable {
        case ways
        case detail(OpenDoddyWay)
        case backTapSteps
        case done
    }

    private var device: OpenDoddyDevice { DeviceSupport.openDoddyDevice }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .padding(24)
            }
            .background(Theme.canvas)
            .navigationTitle("Ways to open Doddy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .foregroundStyle(Theme.ink)
    }

    /// A running test always shows its own screen, so a shortcut that opens Doddy during the test
    /// (even after iOS restarted the app) lands on the question about it, whatever was open.
    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .testing(let window):
            test(window)
        case .receiptReceived(_, let receivedAt):
            received(at: receivedAt)
        default:
            switch screen {
            case .ways: ways
            case .detail(let way): detail(way)
            case .backTapSteps: backTapSteps
            case .done: done(at: doneDate)
            }
        }
    }

    private var doneDate: Date {
        if case .userReportedTested(let at) = model.phase { return at }
        return .now
    }

    // MARK: The list

    private var ways: some View {
        Group {
            Text("A quick way to find me").miniLabelStyle()
            Text("How do you want\nto open me?")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Pick one. Each takes about a minute, and you can add another any time.")
            // Doddy steps out of a phone onto the desk (the pack's 037, ADR-380).
            PanelStoryView(story: .phone, played: $phonePlayed, height: 160)
                .frame(maxWidth: .infinity)
            VStack(spacing: 12) {
                ForEach(OpenDoddyWays.available(on: device)) { way in
                    Button { open(way) } label: { wayRow(way) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ways.\(way.rawValue)")
                }
            }
            Button("Maybe later") {
                model.send(.deferSetup)
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("setup.later")
            Text("You choose each one in iPhone Settings or Control Center. Doddy can't change them and can't see what they are set to.")
                .hintStyle()
            Text("What happens when you use one, a conversation or only opening Doddy, is set under Settings › Back Tap and Siri.")
                .hintStyle()
        }
    }

    private func wayRow(_ way: OpenDoddyWay) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon(way))
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(Theme.accentText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                title(of: way).font(.headline)
                summary(of: way)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            if way == .backTap, let status = backTapStatus {
                status.font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func icon(_ way: OpenDoddyWay) -> String {
        switch way {
        case .backTap: "hand.tap"
        case .actionButton: "button.programmable"
        case .control: "switch.2"
        case .siri: "mic"
        }
    }

    private func title(of way: OpenDoddyWay) -> Text {
        switch way {
        case .backTap: Text("Double-tap the back of your iPhone")
        case .actionButton: Text("Press the Action Button")
        case .control: Text("Add a Doddy button")
        case .siri: Text("Ask Siri")
        }
    }

    private func summary(of way: OpenDoddyWay) -> Text {
        switch way {
        case .backTap: Text("Three steps in Settings.")
        case .actionButton:
            device.actionButton == .yes ? Text("Choose Talk to Doddy in Settings.") : Text("If your iPhone has one.")
        case .control: Text("In Control Center or on the Lock Screen.")
        case .siri: Text("Say \u{201C}Hey Siri, Talk to Doddy\u{201D}. Nothing to set up.")
        }
    }

    /// What the user has said about Double Back Tap, never a verified setting.
    private var backTapStatus: Text? {
        switch model.phase {
        case .userReportedTested: Text("Tested by you")
        case .deferred: Text("Later")
        default: nil
        }
    }

    private func open(_ way: OpenDoddyWay) {
        guard way == .backTap else {
            screen = .detail(way)
            return
        }
        switch model.phase {
        case .notStarted, .deferred: model.send(.start)
        case .userReportedTested: model.send(.revisit)
        default: break
        }
        screen = .backTapSteps
    }

    private var allWaysButton: some View {
        Button { screen = .ways } label: { Label("All ways", systemImage: "chevron.left") }
            .font(.subheadline)
            .accessibilityIdentifier("ways.all")
    }

    // MARK: Double Back Tap, in three steps

    private var backTapSteps: some View {
        Group {
            allWaysButton
            Text("Double Back Tap").miniLabelStyle()
            Text("Three steps,\nthen try it.")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 14) {
                numbered(1) { Text("Open Settings, then choose Accessibility and Touch.") }
                numbered(2) { Text("Scroll down to Back Tap and choose Double Tap.") }
                numbered(3) { Text("Under Shortcuts, choose Talk to Doddy.") }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
            openSettingsButton
            Button {
                model.send(.startTest(now: .now))
            } label: {
                HStack { Text("I've done it, let me try"); Spacer(); Image(systemName: "arrow.right") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("setup.startTest")
            DisclosureGroup("If your iPhone doesn't list it under Back Tap") {
                VStack(alignment: .leading, spacing: 8) {
                    numbered(1) { Text("Open the Shortcuts app, tap the plus button, search for Doddy and add \u{201C}Talk to Doddy\u{201D}. If it isn't offered, add \u{201C}Open App\u{201D} and choose Doddy.") }
                    numbered(2) { Text("Name the shortcut Open Doddy, tap Done, then run it once. Then choose it under Back Tap instead.") }
                }
                .padding(.top, 8)
            }
            Button("Set this up later") {
                model.send(.deferSetup)
                dismiss()
            }
            .font(.footnote)
            .foregroundStyle(Theme.accentText)
            Text("Doddy can't see Settings, can't set Back Tap for you and can't check what your iPhone lists.")
                .hintStyle()
        }
    }

    private var openSettingsButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                Label("Open iPhone Settings", systemImage: "gear")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("ways.openSettings")
            Text("This opens Doddy's own page in Settings. Tap Settings at the top left to reach the main list.")
                .hintStyle()
        }
    }

    // MARK: The other ways

    @ViewBuilder
    private func detail(_ way: OpenDoddyWay) -> some View {
        allWaysButton
        switch way {
        case .backTap:
            EmptyView()
        case .actionButton:
            Text("Action Button").miniLabelStyle()
            Text("Press it to talk.")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Make the Action Button start a conversation with Doddy.")
            if device.actionButton != .yes {
                Text("Only some iPhones have an Action Button. If yours doesn't, pick another way.")
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
            }
            VStack(alignment: .leading, spacing: 14) {
                numbered(1) { Text("Open Settings and choose Action Button.") }
                numbered(2) { Text("Swipe to Controls (Shortcut on iOS 17) and tap the button under it.") }
                numbered(3) { Text("Pick Talk to Doddy.") }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
            // ADR-562: the control that starts the conversation without bringing Doddy forward.
            Text("To talk without Doddy opening, pick Talk in the Island instead (iOS 18 or later). He greets you and stays in the Dynamic Island; tap it to see the conversation.")
            openSettingsButton
            Text("The names can differ a little between iOS versions. Doddy can't see this setting.")
                .hintStyle()
        case .control:
            Text("Control Center and Lock Screen").miniLabelStyle()
            Text("A button\nfor Doddy.")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Put Talk to Doddy one tap away, even from the Lock Screen.")
            VStack(alignment: .leading, spacing: 14) {
                numbered(1) { Text("Swipe down from the top right corner to open Control Center.") }
                numbered(2) { Text("Tap the plus at the top left, then Add a Control.") }
                numbered(3) { Text("Search for Doddy and choose Talk to Doddy.") }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
            Text("For the Lock Screen, touch and hold it, tap Customize, choose Lock Screen, tap a control at the bottom and search for Doddy.")
            Text("Needs iOS 18 or later. Doddy can't add it for you and can't see whether it is there.")
                .hintStyle()
        case .siri:
            Text("Siri").miniLabelStyle()
            Text("Just ask.")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Say \u{201C}Hey Siri, Talk to Doddy\u{201D}. There is nothing to set up.")
                .font(.title3)
            Text("\u{201C}Hey Siri, Open Doddy\u{201D} works too.")
            Text("Siri is Apple's and has to be turned on in iPhone Settings. It hears your request; Doddy starts after that.")
                .hintStyle()
        }
        Button {
            dismiss()
        } label: {
            HStack { Text("Done"); Spacer(); Image(systemName: "checkmark") }
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    // MARK: The test

    private func test(_ window: BackTapTestWindow) -> some View {
        Group {
            Text("A small real-world check").miniLabelStyle()
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
                model.send(.backToSteps)
                screen = .backTapSteps
            }
            .buttonStyle(SecondaryButtonStyle())
            Button("Finish setup later") {
                model.send(.deferSetup)
                dismiss()
            }
            .font(.footnote)
            .foregroundStyle(Theme.accentText)
            Text("A received shortcut proves the route reached Doddy. You then say whether Double Back Tap triggered it.")
                .hintStyle()
        }
    }

    private func received(at date: Date) -> some View {
        Group {
            Text("Your shortcut reached Doddy").miniLabelStyle()
            Text("That worked.")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Doddy's shortcut ran at \(date.formatted(date: .omitted, time: .shortened)). Did Double Back Tap trigger it, or did you run the shortcut another way?")
            Button {
                model.send(.confirmDoubleTap(now: .now))
                screen = .done
            } label: {
                HStack { Text("Yes, I used Double Back Tap"); Spacer(); Image(systemName: "checkmark") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("setup.confirmTap")
            Button("I ran it another way") {
                model.send(.otherTrigger)
                screen = .backTapSteps
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("setup.otherTrigger")
            Text("Only you can tell which gesture ran it. iOS doesn't report that to apps.")
                .hintStyle()
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
            Text("This is your report. iOS doesn't tell apps what Back Tap is set to, so Doddy hasn't verified it and never will claim to.")
                .hintStyle()
            Button {
                dismiss()
            } label: {
                HStack { Text("Done"); Spacer(); Image(systemName: "checkmark") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("setup.done")
            Button("See the other ways") { screen = .ways }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("setup.otherWays")
            Button("Go through the steps again") {
                model.send(.revisit)
                screen = .backTapSteps
            }
            .font(.footnote)
            .foregroundStyle(Theme.accentText)
        }
    }

    // MARK: Pieces

    private func callout(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func numbered<Content: View>(_ number: Int, @ViewBuilder _ text: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number).")
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            text()
        }
        .accessibilityElement(children: .combine)
    }
}

private extension Text {
    /// Small uppercase line above a screen's title.
    func miniLabelStyle() -> some View {
        font(.caption.weight(.semibold))
            .kerning(1.2)
            .foregroundStyle(Theme.secondaryText)
            .textCase(.uppercase)
    }

    func hintStyle() -> some View {
        font(.footnote)
            .foregroundStyle(Theme.secondaryText)
    }
}
