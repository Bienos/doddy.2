import DoddyCore
import SwiftUI
import UIKit

/// Settings › Parcels (InPost) (ADR-641). Off until the person turns it on. A parcel is checked with
/// InPost only when they add it or tap Refresh; the list stays on this iPhone and "Delete all" removes it.
/// "Paste a number from the clipboard" only fills the number field (from `ParcelNumber.candidates`, which
/// takes a run of exactly 24 digits); the look-up still starts with "Add and check".
/// Not seen on a device in this build (docs/implementation/INPOST_STATUS.md).
struct ParcelsView: View {
    @State private var model = ParcelsModel(
        fetcher: InPostTrackingClient.shared,
        isPaused: { UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) })
    @AppStorage(ConnectionPause.preferenceKey) private var pauseAll = false
    @State private var number = ""
    @State private var label = ""
    @State private var pasteMessage: String?
    @State private var confirmTurnOff = false

    var body: some View {
        Form {
            Section {
                Toggle("Parcel list", isOn: Binding(
                    get: { model.isOn },
                    set: { wanted in
                        if wanted { model.setOn(true) }
                        else if model.entries.isEmpty { model.setOn(false) }
                        else { confirmTurnOff = true }
                    }))
                    .accessibilityIdentifier("parcels.toggle")
                    .confirmationDialog("Turn the parcel list off?", isPresented: $confirmTurnOff, titleVisibility: .visible) {
                        Button("Turn off and forget the numbers", role: .destructive) { model.setOn(false) }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The parcel numbers on this list are removed from this iPhone.")
                    }
            } footer: {
                Text("Off until you turn it on. Doddy checks a parcel with InPost only when you add it or tap Refresh. A number in a message or an email is never looked up by itself. Only the number goes to InPost, which needs no account or key.")
            }

            if pauseAll {
                Section {
                    Label("Connections are paused, so parcels aren't checked.", systemImage: "pause.circle")
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            if model.isOn {
                Section("Add a parcel") {
                    TextField("InPost parcel number (24 digits)", text: $number)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("parcels.number")
                    Button("Paste a number from the clipboard") { pasteNumber() }
                        .accessibilityIdentifier("parcels.paste")
                    if let pasteMessage {
                        Label(pasteMessage, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
                    }
                    TextField("Name (optional), e.g. shoes", text: $label)
                        .accessibilityIdentifier("parcels.label")
                    Button("Add and check") { Task { await add() } }
                        .disabled(number.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("parcels.add")
                    if let message = model.message {
                        Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
                    }
                }

                Section("Parcels") {
                    if model.entries.isEmpty {
                        Text("No parcels yet.").foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(model.entries) { entry in
                        row(entry)
                    }
                    .onDelete { offsets in
                        let shown = model.entries
                        for index in offsets { model.remove(shown[index]) }
                    }
                }
            }
        }
        .settingsPage()
        .navigationTitle("Parcels (InPost)")
    }

    private func add() async {
        await model.add(number: number, label: label)
        if model.message == nil {
            number = ""
            label = ""
            pasteMessage = nil
        }
    }

    /// Fills the number field from the clipboard when it holds exactly one 24-digit number (an SMS or an
    /// email from InPost has the number among other text). Nothing is looked up here.
    private func pasteNumber() {
        let found = ParcelNumber.candidates(in: UIPasteboard.general.string ?? "")
        switch found.count {
        case 1:
            number = found[0].digits
            pasteMessage = nil
        case 0:
            pasteMessage = NSLocalizedString("No 24-digit InPost number on the clipboard.", comment: "")
        default:
            pasteMessage = NSLocalizedString("The clipboard has more than one number. Copy just the one you want.", comment: "")
        }
    }

    private func row(_ entry: ParcelEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: entry.label ?? entry.number).font(.body.weight(.semibold))
                Spacer()
                if model.busy.contains(entry.number) { ProgressView() }
            }
            if entry.label != nil {
                Text(verbatim: entry.number).font(.footnote.monospacedDigit()).foregroundStyle(Theme.secondaryText)
            }
            Text(verbatim: model.statusLine(for: entry)).font(.subheadline)
            if let note = model.notes[entry.number] {
                Text(verbatim: note).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if let checked = entry.lastChecked {
                Text(verbatim: String(
                    format: NSLocalizedString("Checked %@ · status from InPost", comment: ""),
                    checked.formatted(date: .abbreviated, time: .shortened)))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if let tracking = model.details[entry.number], !tracking.events.isEmpty {
                DisclosureGroup("History") {
                    ForEach(Array(tracking.events.enumerated()), id: \.offset) { _, event in
                        VStack(alignment: .leading) {
                            Text(verbatim: sentence(event.status)).font(.footnote)
                            if let when = event.datetime {
                                Text(verbatim: Self.shown(when)).font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }
                .font(.footnote)
            }
            Button("Refresh") { Task { await model.refresh(entry) } }
                .buttonStyle(.borderless)
                .disabled(model.busy.contains(entry.number) || pauseAll)
                .accessibilityIdentifier("parcels.refresh")
        }
        .padding(.vertical, 2)
    }

    private func sentence(_ status: String) -> String {
        let text = ParcelStatuses.text(for: status)
        return ParcelsModel.polish ? text.polish : text.english
    }

    /// InPost writes ISO 8601 with an offset; shown in the person's own time format, or as InPost wrote it.
    private static func shown(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) ?? plain.date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
