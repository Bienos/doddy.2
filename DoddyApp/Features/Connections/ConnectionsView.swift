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

                // A group whose every switch the build hides (decision 2026-11-07-release-scope) goes with its heading.
                ForEach(ConnectionGroup.shown(in: ReleaseScopeStore.current)) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        // Looked up when shown, so the heading is in the screens' language.
                        Text(NSLocalizedString(group.title, comment: ""))
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
        ConnectionGroup(title: "Your day", items: [.calendar, .reminders, .timers, .steps]),
        ConnectionGroup(title: "People", items: [.contacts, .messages]),
        // ADR-567: a presentation is a file made here, opened in Keynote by the user.
        ConnectionGroup(title: "Places and apps", items: [.maps, .shortcuts, .presentations]),
        // ADR-569: the photo library (counts, pictures on screen only) and Doddy's camera.
        ConnectionGroup(title: "Photos and camera", items: [.photos, .camera]),
        // Lights, outlets, fans and scenes through HomeKit, after a tap on a card.
        ConnectionGroup(title: "Home", items: [.home]),
        // ADR-510: shown, never sent; the user sends it in their bank app.
        ConnectionGroup(title: "Money", items: [.blik]),
    ]

    /// The groups with the switches the scope shows (decision 2026-11-07-release-scope); a group left with no switch is dropped.
    static func shown(in scope: ReleaseScope) -> [ConnectionGroup] {
        all.compactMap { group in
            let items = group.items.filter { scope.shows($0) }
            return items.isEmpty ? nil : ConnectionGroup(title: group.title, items: items)
        }
    }
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

                    section(NSLocalizedString("Say something like", comment: "")) {
                        ForEach(info.examples, id: \.self) { example in
                            Text("“\(example)”")
                                .font(.body.italic())
                        }
                    }

                    section(NSLocalizedString("Doddy can", comment: "")) {
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

                    section(NSLocalizedString("What leaves your phone", comment: "")) {
                        Text(info.leavesPhone)
                    }

                    section(NSLocalizedString("What stays here", comment: "")) {
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
/// the code in DoddyCore, DeviceConnections and VoiceSessionController. Every line goes through
/// `NSLocalizedString`, so it is collected into the string tables and shown in the screens' language
/// (decision 2026-11-09-remove-old-design-leftovers, S1; ADR-234: privacy texts get a native review first).
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
                examples: [NSLocalizedString("What's on tomorrow?", comment: ""), NSLocalizedString("Am I free on Thursday afternoon?", comment: ""), NSLocalizedString("Add dentist on Monday at three", comment: "")],
                canDo: [
                    NSLocalizedString("Read your events for today, tomorrow, the week, or a day you name", comment: ""),
                    NSLocalizedString("Add an event, after you tap Add", comment: ""),
                    NSLocalizedString("Move, rename or delete one event, change its place or add a note to it, after you tap Change or Delete", comment: ""),
                ],
                leavesPhone: NSLocalizedString("Event titles and times, when Doddy uses them in a conversation.", comment: ""),
                staysHere: NSLocalizedString("An event's place is read only to show it on the card when you ask to change it, and notes are only added to. Neither is sent to Doddy's voice. Doddy changes or deletes events only after you tap.", comment: ""))
        case .reminders:
            ConnectionInfo(
                symbol: "checklist",
                examples: [NSLocalizedString("Remind me to call Marta at six", comment: ""), NSLocalizedString("Add buy milk to my reminders", comment: "")],
                canDo: [
                    NSLocalizedString("Add a reminder, after you tap Add", comment: ""),
                    NSLocalizedString("Move, complete or delete one open reminder, after you tap", comment: ""),
                ],
                leavesPhone: NSLocalizedString("The reminder text and due time, when Doddy adds one.", comment: ""),
                staysHere: NSLocalizedString("Doddy reads your open reminders only to find the one you name. Notes on reminders aren't read.", comment: ""))
        case .timers:
            ConnectionInfo(
                symbol: "timer",
                examples: [NSLocalizedString("Set a timer for ten minutes", comment: ""), NSLocalizedString("Forty-five seconds for the eggs", comment: "")],
                canDo: [
                    NSLocalizedString("Start a countdown, after you tap Start", comment: ""),
                    NSLocalizedString("Ring it like the Clock app's timer, even in Silent mode or a Focus, with the time left, Pause and Stop on the Lock Screen (iOS 26 and later; before that, a notification)", comment: ""),
                    NSLocalizedString("Set an alarm that rings even in Silent mode, after you tap Set alarm (iOS 26 and later)", comment: ""),
                ],
                leavesPhone: NSLocalizedString("The length and label of a timer, or the time and label of an alarm, when Doddy sets one.", comment: ""),
                staysHere: NSLocalizedString("iPhone asks once to allow alarms and timers (on iOS before 26, notifications). Doddy keeps each timer's ring time and label on this iPhone, only to find it again.", comment: ""))
        case .contacts:
            ConnectionInfo(
                symbol: "person.crop.circle",
                examples: [NSLocalizedString("What's Marta's number?", comment: ""), NSLocalizedString("Find Tomek Kowalski", comment: ""), NSLocalizedString("Whose birthday is this week?", comment: "")],
                canDo: [
                    NSLocalizedString("Look up a contact by name and show the details on your screen", comment: ""),
                    NSLocalizedString("Call, text or email them from that card, after you tap", comment: ""),
                    NSLocalizedString("Tell you whose birthday is coming up, from the birthdays on your contact cards", comment: ""),
                    NSLocalizedString("Remind you of the birthdays you pick, in Settings, Birthdays", comment: ""),
                ],
                leavesPhone: NSLocalizedString("Only the names Doddy finds, and for birthdays the day and month. Numbers, email addresses and birth years stay on your iPhone.", comment: ""),
                staysHere: NSLocalizedString("Doddy never calls, texts or emails anyone by itself. Birthday reminders are set on this iPhone only.", comment: ""))
        case .messages:
            ConnectionInfo(
                symbol: "text.bubble",
                examples: [NSLocalizedString("Text Marta that I'm running late", comment: ""), NSLocalizedString("Email Tomek the agenda", comment: "")],
                canDo: [
                    NSLocalizedString("Draft a text or email, then open it in Messages or Mail for you to check and send", comment: ""),
                    NSLocalizedString("Needs Contacts too, to find the person", comment: ""),
                ],
                leavesPhone: NSLocalizedString("The draft and the person's name, when Doddy drafts one.", comment: ""),
                staysHere: NSLocalizedString("Doddy never sends a message or email. The number or address is shown only on your screen.", comment: ""))
        case .maps:
            ConnectionInfo(
                symbol: "map",
                examples: [NSLocalizedString("Show me Mokotów Tower on the map", comment: ""), NSLocalizedString("Open the Old Town in Maps", comment: "")],
                canDo: [NSLocalizedString("Open a place or address in Apple Maps, after you tap Open in Maps", comment: "")],
                leavesPhone: NSLocalizedString("The place name you asked for, when you open it in Maps.", comment: ""),
                staysHere: NSLocalizedString("Doddy doesn't read your location or search for places by itself.", comment: ""))
        case .shortcuts:
            ConnectionInfo(
                symbol: "square.stack.3d.up",
                examples: [NSLocalizedString("Run my morning routine", comment: ""), NSLocalizedString("Start the movie shortcut", comment: ""), NSLocalizedString("Open the camera", comment: "")],
                canDo: [
                    NSLocalizedString("Run one of your Shortcuts, after you tap Run", comment: ""),
                    NSLocalizedString("The Shortcuts app opens for a moment", comment: ""),
                ],
                leavesPhone: NSLocalizedString("The shortcut's name, when you ask Doddy to run it.", comment: ""),
                staysHere: NSLocalizedString("Doddy can't see what a shortcut does or whether it finished.", comment: ""))
        case .presentations:
            // ADR-567: Apple lets no app control Keynote, so Doddy makes the file and the user opens it.
            ConnectionInfo(
                symbol: "rectangle.on.rectangle.angled",
                examples: [NSLocalizedString("Make me five slides about our trip", comment: ""), NSLocalizedString("Turn my notes on the launch into a presentation", comment: "")],
                canDo: [
                    NSLocalizedString("Show every slide on a card first: the title, then each slide's title and points", comment: ""),
                    NSLocalizedString("Make the presentation after you tap Make presentation, as a PowerPoint file that Keynote opens", comment: ""),
                    NSLocalizedString("Open the share sheet, so you pick Keynote, Files or someone to send it to", comment: ""),
                ],
                leavesPhone: NSLocalizedString("What you ask for and the slides Doddy writes are part of the conversation, which runs on ElevenLabs, or OpenAI if you chose it.", comment: ""),
                staysHere: NSLocalizedString("The file is made on this iPhone and kept in Doddy's temporary files until iOS clears them; save it in Keynote or Files to keep it. Doddy can't see what you do with it and never sends it.", comment: ""))
        case .steps:
            // ADR-568: Motion & Fitness, read only. Not Health.
            ConnectionInfo(
                symbol: "figure.walk",
                examples: [NSLocalizedString("How many steps today?", comment: ""), NSLocalizedString("How far did I walk yesterday?", comment: "")],
                canDo: [
                    NSLocalizedString("Read one day's steps, walking distance and floors climbed, after you say yes or tap", comment: ""),
                    NSLocalizedString("Today and the six days before it, which is what your iPhone keeps", comment: ""),
                ],
                leavesPhone: NSLocalizedString("That day's numbers, when Doddy uses them in a conversation.", comment: ""),
                staysHere: NSLocalizedString("Doddy keeps none of it. Steps come from Motion & Fitness, not from the Health app. iPhone asks once for Motion & Fitness.", comment: ""))
        case .photos:
            // ADR-569: counts and times to the voice, pictures on this screen only.
            ConnectionInfo(
                symbol: "photo.on.rectangle",
                examples: [NSLocalizedString("How many photos did I take on Saturday?", comment: ""), NSLocalizedString("Show me my photos from last week", comment: "")],
                canDo: [
                    NSLocalizedString("Count the photos and videos you took on a day or over up to a month, after you say yes or tap", comment: ""),
                    NSLocalizedString("Show the newest of them on your screen, with a button to open Photos", comment: ""),
                ],
                leavesPhone: NSLocalizedString("Only how many there are and when the first and last were taken, when Doddy uses them in a conversation. Never the pictures or where they were taken.", comment: ""),
                staysHere: NSLocalizedString("The pictures are shown on this screen only. Doddy never changes, deletes or adds anything in your photo library. If you let Doddy see only some photos, it says so.", comment: ""))
        case .camera:
            // ADR-569: iOS's own camera screen; a kept photo becomes a note the user saves.
            ConnectionInfo(
                symbol: "camera",
                examples: [NSLocalizedString("Take a photo", comment: ""), NSLocalizedString("Open the camera", comment: "")],
                canDo: [
                    NSLocalizedString("Open Doddy's camera, after you tap Open camera", comment: ""),
                    NSLocalizedString("Put the photo you keep into a new note, with its text read on this iPhone, for you to check and save", comment: ""),
                ],
                leavesPhone: NSLocalizedString("Nothing from the camera. Only the words you save in the note can reach Doddy's voice, like any note.", comment: ""),
                staysHere: NSLocalizedString("The photo is kept with the note on this iPhone, never sent anywhere and never saved to your photo library. You can also tap Take a photo when writing a note.", comment: ""))
        case .home:
            // Needs the HomeKit entitlement (a paid Apple team): HOME_COMMANDS_STATUS.md.
            ConnectionInfo(
                symbol: "house",
                examples: [NSLocalizedString("Turn off the living room lamp", comment: ""), NSLocalizedString("Run Good night", comment: "")],
                canDo: [NSLocalizedString("Turn a light, outlet or fan on or off, or run a scene, after you tap Yes on a card naming it", comment: "")],
                leavesPhone: NSLocalizedString("Nothing leaves your iPhone: HomeKit talks to your home from here.", comment: ""),
                staysHere: NSLocalizedString("Doddy never controls locks, garage doors, alarms, cameras or doorbells.", comment: ""))
        case .blik:
            // ADR-510: BLIK has no way for an app to send money, so Doddy only shows the details.
            ConnectionInfo(
                symbol: "banknote",
                examples: [NSLocalizedString("Send Ania 50 zł for the pizza", comment: ""), NSLocalizedString("Send Tomek 20 zł with BLIK", comment: "")],
                canDo: [
                    NSLocalizedString("Show a BLIK phone transfer on your screen: who, their number, how much in złoty, and the title", comment: ""),
                    NSLocalizedString("You send it yourself in your bank app; Doddy never sends or pays money", comment: ""),
                    NSLocalizedString("Finds the person's number if Contacts is allowed too", comment: ""),
                ],
                leavesPhone: NSLocalizedString("The person's name, the amount and the title you said, as part of the conversation.", comment: ""),
                staysHere: NSLocalizedString("Phone numbers are shown only on your screen. Doddy has no access to your bank and can't see whether you sent it.", comment: ""))
        }
    }
}
