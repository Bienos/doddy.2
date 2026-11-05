import DoddyCore
import SwiftUI

/// "Allow access" (ADR-728): one step after "Before we start" that asks iOS for the permissions Doddy
/// uses, so the person isn't interrupted by them later. Nothing is asked until they tap Allow, they can
/// untick any item, and "Not now" asks nothing: each feature still asks when it is first used.
///
/// Honest about what happens: iOS shows its own question for each item, one at a time, and the person
/// may say no. An answer turns on that item's Settings › Connections switch (`ConnectionController`);
/// a "no" turns nothing on. Health and speech recognition are not asked here: Health has its own
/// screen and sheet, and speech recognition is asked with the first voice memo.
struct FirstRunAccessView: View {
    @AppStorage(PreferenceKey.firstRunAccessSeen) private var seen = false
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideArt = false
    @State private var connections = ConnectionController()
    @State private var ticked = Set(FirstRunAccessItem.allCases.filter(\.tickedAtStart))
    @State private var asking: FirstRunAccessItem?
    @State private var summary: (allowed: Int, refused: Int)?

    private var isAsking: Bool { asking != nil }

    var body: some View {
        OnboardingPage {
            if !hideArt {
                UploadedCharacterView(assetName: "UploadedDoddy_Listening", height: 120)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
            Text("Let Doddy get ready")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("access.title")

            Text("Doddy can ask your iPhone for these now, so nothing interrupts you later. Your iPhone asks each question itself, and you can say no to any of them.")

            if let summary {
                finished(summary)
            } else {
                list
                buttons
            }

            Text("Doddy uses each one only when you ask. You can change any of them later in iPhone Settings or in Doddy › Settings › Connections.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: Choosing

    private var list: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(FirstRunAccessItem.allCases) { item in
                Toggle(isOn: binding(for: item)) {
                    VStack(alignment: .leading, spacing: 2) {
                        title(item).font(.body.weight(.semibold))
                        reason(item).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
                .disabled(isAsking)
                .accessibilityIdentifier("access.\(item.rawValue)")
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                Task { await askAll() }
            } label: {
                // Two literals, not one conditional: a ternary of strings is a String, which isn't localized.
                Group {
                    if isAsking { Text("Asking…") } else { Text("Allow selected") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isAsking)
            .accessibilityIdentifier("access.allow")

            Button {
                seen = true
            } label: {
                Text("Not now, ask me when Doddy needs one").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(isAsking)
            .accessibilityIdentifier("access.skip")
        }
    }

    // MARK: After the questions

    @ViewBuilder
    private func finished(_ summary: (allowed: Int, refused: Int)) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if summary.refused > 0 {
                Text("Done. A few were refused. You can change those in iPhone Settings › Doddy.")
            } else if summary.allowed > 0 {
                Text("Done. You won't be asked for these again.")
            } else {
                Text("Nothing was asked.")
            }
            Button {
                seen = true
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("access.continue")
        }
    }

    private func binding(for item: FirstRunAccessItem) -> Binding<Bool> {
        Binding(
            get: { ticked.contains(item) },
            set: { on in
                if on { ticked.insert(item) } else { ticked.remove(item) }
            })
    }

    /// Asks the ticked items one after another, in the fixed order. iOS shows its own question for each
    /// and may skip it (already answered). Nothing is claimed beyond what iOS answered.
    private func askAll() async {
        var outcomes: [FirstRunAccessItem: FirstRunAccessOutcome] = [:]
        for item in FirstRunAccessRule.itemsToAsk(ticked: ticked) {
            asking = item
            outcomes[item] = await ask(item)
        }
        asking = nil
        summary = FirstRunAccessRule.summary(outcomes)
        await connections.refresh()
    }

    private func ask(_ item: FirstRunAccessItem) async -> FirstRunAccessOutcome {
        switch item {
        case .microphone:
            return await MicrophoneAccess.request() ? .allowed : .refused
        case .location:
            // While Using only, never Always (ADR-196). Approximate is still a yes.
            switch await PlaceLocation.shared.requestWhenInUse() {
            case .ready, .approximateOnly: return .allowed
            case .denied: return .refused
            case .notDetermined, .unavailable: return .skipped
            }
        case .notifications, .contacts, .calendar, .reminders, .motion, .photos, .camera:
            guard let connection = item.connection else { return .skipped }
            // Asks iOS, then turns the Settings › Connections switch on only if iOS allowed it.
            switch await connections.setOn(connection, true) {
            case .granted: return .allowed
            case .denied: return .refused
            case .notDetermined, nil: return .skipped
            }
        }
    }

    // MARK: Words

    private func title(_ item: FirstRunAccessItem) -> Text {
        switch item {
        case .microphone: Text("Microphone")
        case .notifications: Text("Notifications")
        case .contacts: Text("Contacts")
        case .calendar: Text("Calendar")
        case .reminders: Text("Reminders")
        case .location: Text("Location, while using Doddy")
        case .motion: Text("Motion & Fitness")
        case .photos: Text("Photos")
        case .camera: Text("Camera")
        }
    }

    private func reason(_ item: FirstRunAccessItem) -> Text {
        switch item {
        case .microphone: Text("So he can hear you when you talk to him.")
        case .notifications: Text("For reminders, timers and alarms when Doddy isn't open.")
        case .contacts: Text("To find a number or email when you say “text Ania”, and for birthdays.")
        case .calendar: Text("To read your day. An event is added or changed only after you tap.")
        case .reminders: Text("To add or change a reminder, only after you tap.")
        case .location: Text("For reminders at a place, when you tap “Use where I am”. Never in the background.")
        case .motion: Text("Steps, distance and floors for a day you ask about.")
        case .photos: Text("To count the photos you took on a day you ask about.")
        case .camera: Text("For a photo note, only when you tap Take a photo.")
        }
    }
}
