import DoddyCore
import SwiftUI
import UIKit

/// Settings → Connections. One card per function: what you can say, whether it's on, and a tap
/// to see exactly what Doddy can do and what leaves the phone. Nothing turns on without a tap.
struct ConnectionsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = ConnectionController()
    @State private var selected: VoiceConnection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Doddy can use these only when you say so. Each one starts off. Nothing is added until you tap Add.")
                    .foregroundStyle(Theme.secondaryText)

                ForEach(VoiceConnection.allCases) { connection in
                    Button {
                        selected = connection
                    } label: {
                        ConnectionCard(connection: connection, state: controller.state(of: connection))
                    }
                    .buttonStyle(.plain)
                }

                Text("Your notes are always on this iPhone. Weather and Wikipedia lookups run on ElevenLabs and are always on.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(24)
        }
        .background(Theme.canvas)
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected, onDismiss: { controller.refresh() }) { connection in
            ConnectionSheet(connection: connection, controller: controller)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { controller.refresh() }
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
        case .blocked: "Blocked"
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
/// the code in DoddyCore and DeviceConnections.
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
                ],
                leavesPhone: "Event titles and times, when Doddy uses them in a conversation.",
                staysHere: "Locations and notes are not read or sent. Doddy never changes or deletes existing events.")
        case .reminders:
            ConnectionInfo(
                symbol: "checklist",
                examples: ["Remind me to call Marta at six", "Add buy milk to my reminders"],
                canDo: ["Add a reminder, after you tap Add"],
                leavesPhone: "The reminder text and due time, when Doddy adds one.",
                staysHere: "Doddy doesn't read or change your existing reminders.")
        case .contacts:
            ConnectionInfo(
                symbol: "person.crop.circle",
                examples: ["What's Marta's number?", "Find Tomek Kowalski"],
                canDo: ["Look up a contact by name and show the details on your screen"],
                leavesPhone: "Only the names Doddy finds. Numbers and email addresses stay on your screen.",
                staysHere: "Doddy can't call, text or email anyone.")
        }
    }
}
