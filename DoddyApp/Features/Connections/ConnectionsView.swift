import DoddyCore
import SwiftUI
import UIKit

/// Settings → Connections. One card per function, in three groups. Each card shows what you can
/// say and whether it's on; a tap shows exactly what Doddy can do and what leaves the phone.
/// Nothing turns on without a tap.
struct ConnectionsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = ConnectionController()
    @State private var selected: VoiceConnection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Doddy can use these only when you say so. Each one starts off. Nothing is added, started, sent or opened until you tap.")
                    .foregroundStyle(Theme.secondaryText)

                ForEach(ConnectionGroup.all) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.title)
                            .font(.footnote.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityAddTraits(.isHeader)

                        ForEach(group.items) { connection in
                            Button {
                                selected = connection
                            } label: {
                                ConnectionCard(connection: connection, state: controller.state(of: connection))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text("Your notes are always on this iPhone. Weather and Wikipedia lookups run on ElevenLabs, are always on, and don't work when Home's voice is OpenAI.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(24)
        }
        .background(Theme.canvas)
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected, onDismiss: { Task { await controller.refresh() } }) { connection in
            ConnectionSheet(connection: connection, controller: controller)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await controller.refresh() } }
        }
    }
}

/// A heading and the functions under it, in the order the screen shows them.
struct ConnectionGroup: Identifiable {
    let title: String
    let items: [VoiceConnection]

    var id: String { title }

    static let all: [ConnectionGroup] = [
        ConnectionGroup(title: "Your day", items: [.calendar, .reminders, .timers]),
        ConnectionGroup(title: "People", items: [.contacts, .messages]),
        ConnectionGroup(title: "Places and apps", items: [.maps, .shortcuts]),
    ]
}

/// One function as a card. The state is written out in words, not only colour.
struct ConnectionCard: View {
    let connection: VoiceConnection
    let state: ConnectionController.State

    var body: some View {
        let info = ConnectionInfo.of(connection)
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: info.symbol)
                .font(.title3)
                .foregroundStyle(Theme.ink)
                .frame(width: 48, height: 48)
                .background(Theme.quietSurface, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(connection.title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("“\(info.examples[0])”")
                    .font(.subheadline.italic())
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)
            StatusPill(state: state)
        }
        .padding(16)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.separator, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows what Doddy can do with \(connection.title).")
    }
}

/// Off, On or Blocked, with a dot and a word.
struct StatusPill: View {
    let state: ConnectionController.State

    private var label: String {
        switch state {
        case .off: "Off"
        case .on: "On"
        case .blocked: NSLocalizedString("Blocked", comment: "")
        }
    }

    private var dot: Color {
        switch state {
        case .off: Theme.secondaryText
        case .on: Theme.confirmed
        case .blocked: Theme.error
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dot)
                .frame(width: 8, height: 8)
            Text(label)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// The detail view. Turning on is a separate, explicit tap, so the user always sees the terms first.
struct ConnectionSheet: View {
    let connection: VoiceConnection
    let controller: ConnectionController

    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var refusal: String?

    var body: some View {
        let info = ConnectionInfo.of(connection)
        let state = controller.state(of: connection)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: info.symbol)
                            .font(.largeTitle)
                            .foregroundStyle(Theme.ink)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(connection.title)
                                .font(.title2.bold())
                            StatusPill(state: state)
                        }
                    }

                    section("Say something like") {
                        ForEach(info.examples, id: \.self) { example in
                            Text("“\(example)”")
                                .font(.body.italic())
                        }
                    }

                    section("Doddy can") {
                        ForEach(info.canDo, id: \.self) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Circle()
                                    .fill(Theme.orangeCue)
                                    .frame(width: 6, height: 6)
                                    .accessibilityHidden(true)
                                Text(line)
                            }
                        }
                    }

                    section("What leaves your phone") {
                        Text(info.leavesPhone)
                    }

                    section("What stays here") {
                        Text(info.staysHere)
                    }

                    if connection == .shortcuts {
                        cameraShortcut
                    }

                    if let refusal {
                        ProblemView(message: refusal)
                    }

                    actions(state, title: connection.title)
                }
                .padding(24)
            }
            .background(Theme.canvas)
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
    private func actions(_ state: ConnectionController.State, title: String) -> some View {
        switch state {
        case .off:
            Button {
                Task { await turnOn() }
            } label: {
                Label("Turn on \(title)", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isWorking)
            .accessibilityIdentifier("connection.turnOn")
        case .on:
            Button("Turn off") {
                Task {
                    _ = await controller.setOn(connection, false)
                    refusal = nil
                }
            }
            .buttonStyle(SecondaryButtonStyle(tint: Theme.error))
            .accessibilityIdentifier("connection.turnOff")
        case .blocked:
            Text("Doddy is switched on, but iPhone doesn't allow \(title) for Doddy any more.")
                .foregroundStyle(Theme.secondaryText)
            Button("Open iPhone Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Switch off in Doddy") {
                Task { _ = await controller.setOn(connection, false) }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    /// "Open the camera" needs the user's "Doddy Camera" Shortcut (ADR-291, ADR-309).
    private var cameraShortcut: some View {
        section("Open the camera") {
            CameraShortcutHelp(style: .full)
        }
    }

    private func turnOn() async {
        isWorking = true
        defer { isWorking = false }
        switch await controller.setOn(connection, true) {
        case .granted:
            refusal = nil
        case .denied, .notDetermined, nil:
            refusal = "iPhone didn't allow \(connection.title) for Doddy. You can allow it in iPhone Settings, then try again."
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.secondaryText)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Plain-language copy for each function. What it can do and what leaves the phone must match
/// the code in DoddyCore, DeviceConnections and VoiceSessionController.
struct ConnectionInfo {
    let symbol: String
    let examples: [String]
    let canDo: [String]
    let leavesPhone: String
    let staysHere: String

    static func of(_ connection: VoiceConnection) -> ConnectionInfo {
        switch connection {
        case .calendar:
            ConnectionInfo(
                symbol: "calendar",
                examples: ["What's on tomorrow?", "Am I free on Thursday afternoon?", "Add dentist on Monday at three"],
                canDo: [
                    "Read your events for today, tomorrow, the week, or a day you name",
                    "Add an event, after you tap Add",
                    "Move, rename or delete one event, change its place or add a note to it, after you tap Change or Delete",
                ],
                leavesPhone: "Event titles and times, when Doddy uses them in a conversation.",
                staysHere: "An event's place is read only to show it on the card when you ask to change it, and notes are only added to. Neither is sent to Doddy's voice. Doddy changes or deletes events only after you tap.")
        case .reminders:
            ConnectionInfo(
                symbol: "checklist",
                examples: ["Remind me to call Marta at six", "Add buy milk to my reminders"],
                canDo: [
                    "Add a reminder, after you tap Add",
                    "Move, complete or delete one open reminder, after you tap",
                ],
                leavesPhone: "The reminder text and due time, when Doddy adds one.",
                staysHere: "Doddy reads your open reminders only to find the one you name. Notes on reminders aren't read.")
        case .timers:
            ConnectionInfo(
                symbol: "timer",
                examples: ["Set a timer for ten minutes", "Forty-five seconds for the eggs"],
                canDo: [
                    "Start a countdown, after you tap Start",
                    "Ring with a notification when it's done, even if the app is closed",
                    "Set an alarm that rings even in Silent mode, after you tap Set alarm (iOS 26 and later)",
                ],
                leavesPhone: "The length and label of a timer, or the time and label of an alarm, when Doddy sets one.",
                staysHere: "iPhone asks once for notification permission. Doddy doesn't keep track of the timer after it starts.")
        case .contacts:
            ConnectionInfo(
                symbol: "person.crop.circle",
                examples: ["What's Marta's number?", "Find Tomek Kowalski", "Whose birthday is this week?"],
                canDo: [
                    "Look up a contact by name and show the details on your screen",
                    "Call, text or email them from that card, after you tap",
                    "Tell you whose birthday is coming up, from the birthdays on your contact cards",
                    "Remind you of the birthdays you pick, in Settings, Birthdays",
                ],
                leavesPhone: "Only the names Doddy finds, and for birthdays the day and month. Numbers, email addresses and birth years stay on your iPhone.",
                staysHere: "Doddy never calls, texts or emails anyone by itself. Birthday reminders are set on this iPhone only.")
        case .messages:
            ConnectionInfo(
                symbol: "text.bubble",
                examples: ["Text Marta that I'm running late", "Email Tomek the agenda"],
                canDo: [
                    "Draft a text or email, then open it in Messages or Mail for you to check and send",
                    "Needs Contacts too, to find the person",
                ],
                leavesPhone: "The draft and the person's name, when Doddy drafts one.",
                staysHere: "Doddy never sends a message or email. The number or address is shown only on your screen.")
        case .maps:
            ConnectionInfo(
                symbol: "map",
                examples: ["Show me Mokotów Tower on the map", "Open the Old Town in Maps"],
                canDo: ["Open a place or address in Apple Maps, after you tap Open in Maps"],
                leavesPhone: "The place name you asked for, when you open it in Maps.",
                staysHere: "Doddy doesn't read your location or search for places by itself.")
        case .shortcuts:
            ConnectionInfo(
                symbol: "square.stack.3d.up",
                examples: ["Run my morning routine", "Start the movie shortcut", "Open the camera"],
                canDo: [
                    "Run one of your Shortcuts, after you tap Run",
                    "The Shortcuts app opens for a moment",
                ],
                leavesPhone: "The shortcut's name, when you ask Doddy to run it.",
                staysHere: "Doddy can't see what a shortcut does or whether it finished.")
        }
    }
}
