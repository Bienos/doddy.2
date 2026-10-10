import DoddyCore
import SwiftUI
import UIKit

/// Memory detail: "Remind me", or the reminder that is set with Change / Cancel, plus the receipt.
struct NoteReminderSection: View {
    let memoryID: UUID

    @Environment(NoteReminderStore.self) private var reminders
    @State private var showSheet = false
    /// Opens the sheet on "At a time" (from a blocked place reminder's receipt).
    @State private var sheetAtTime = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let receipt = reminders.receipts[memoryID] {
                NoteReminderReceiptView(receipt: receipt, retry: { open() }, atTimeInstead: {
                    reminders.clearReceipt(memoryID: memoryID)
                    open(atTime: true)
                })
            }
            if let reminder = reminders.reminder(forMemory: memoryID) {
                card(reminder)
            } else if reminders.isAvailable {
                Button { open() } label: {
                    HStack { Text("Remind me"); Spacer(); Image(systemName: "bell") }
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("detail.remind")
            }
        }
        .sheet(isPresented: $showSheet) { NoteReminderSheet(memoryID: memoryID, startAtTime: sheetAtTime) }
    }

    private func open(atTime: Bool = false) {
        sheetAtTime = atTime
        showSheet = true
    }

    private func card(_ reminder: MemoryReminder) -> some View {
        let alerts = reminders.authorization == .allowed
        let atPlace = reminder.place != nil
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: atPlace ? "mappin.and.ellipse" : alerts ? "bell" : "bell.slash").accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alerts ? "Reminder" : "Reminder · in Doddy only")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    Text(ReminderFormat.summary(reminder))
                        .font(.headline)
                    if let place = reminder.place {
                        Text("Within \(place.radiusMeters) m, each time, until you mark it Done.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if reminder.isDue(at: .now) {
                        Text("Due now").font(.footnote.bold()).foregroundStyle(Theme.accentText)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 10) {
                Button("Change") { open() }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.ink))
                Button("Cancel reminder", role: .destructive) {
                    Task { await reminders.cancel(memoryID: memoryID) }
                }
                .foregroundStyle(Theme.error)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.error))
                .accessibilityIdentifier("detail.cancelReminder")
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.separator))
    }
}

/// Built only from a real outcome: verified with iOS, kept in Doddy only, or failed.
struct NoteReminderReceiptView: View {
    let receipt: NoteReminderReceipt
    let retry: () -> Void
    /// Offered when a place reminder is blocked by a setting: a time reminder needs no location.
    var atTimeInstead: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch receipt {
            case .scheduled(let reminder):
                Label(reminder.place == nil
                      ? "Reminder set for \(ReminderFormat.short(reminder))."
                      : "Reminder set \(ReminderFormat.short(reminder)).", systemImage: "checkmark")
                    .font(.headline)
                    .foregroundStyle(Theme.confirmed)
                Text(UserDefaults.standard.bool(forKey: PreferenceKey.showNoteTextInNotifications)
                    ? "Your iPhone will show a notification with the note text."
                    : "Your iPhone will show a notification. The note text stays hidden on the Lock Screen.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            case .inAppOnly(let reminder):
                Label("Saved in Doddy for \(ReminderFormat.short(reminder)).", systemImage: "bell.slash")
                    .font(.headline)
                Text("Notifications are off for Doddy, so your iPhone won't alert you. When it's due, the note waits at the top of Home.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
                .frame(minHeight: 44)
            case .needsSettings(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.error)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .frame(minHeight: 44)
                if let atTimeInstead {
                    Button("Remind me at a time instead", action: atTimeInstead)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("reminder.atTimeInstead")
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.error)
                Button("Try again", action: retry)
                    .frame(minHeight: 44)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminder.receipt")
    }
}

/// Home: reminders whose time has passed, at the top. Works with notifications off; no badge.
struct DueRemindersView: View {
    @Environment(NoteReminderStore.self) private var reminders
    @Environment(MemoryStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let due = reminders.due(at: context.date).compactMap { reminder in
                store.record(id: reminder.memoryID).map { DueItem(reminder: reminder, record: $0) }
            }
            if !due.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Due now", systemImage: "bell")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.accentText)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(due) { item($0.reminder, $0.record) }
                }
                .padding(16)
                .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityIdentifier("home.due")
            }
        }
    }

    private func item(_ reminder: MemoryReminder, _ record: MemoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: record.id) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.currentText).lineLimit(4)
                    Text("You asked to see this again · \(ReminderFormat.short(reminder))")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            HStack(spacing: 10) {
                Button("Done") { Task { await reminders.done(reminderID: reminder.id) } }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Tomorrow 09:00") { Task { await reminders.later(reminderID: reminder.id) } }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

private struct DueItem: Identifiable {
    let reminder: MemoryReminder
    let record: MemoryRecord
    var id: UUID { reminder.id }
}

/// Settings → Notifications. Status comes from iOS; nothing here claims an alert iOS won't show.
struct NoteReminderSettingsSection: View {
    @Environment(NoteReminderStore.self) private var reminders
    @Environment(\.openURL) private var openURL
    @AppStorage(PreferenceKey.showNoteTextInNotifications) private var showNoteText = false
    @State private var confirmCancelAll = false

    var body: some View {
        Section("Reminders on notes") {
            StatusRow(title: "iOS notifications", value: statusText)
            switch reminders.authorization {
            case .notDetermined:
                Button("Allow notifications") { Task { await reminders.requestAuthorization() } }
            case .denied:
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            case .allowed:
                EmptyView()
            }
            Toggle("Show note text in notifications", isOn: $showNoteText)
                .onChange(of: showNoteText) { Task { await reminders.noteTextSettingChanged() } }
                .accessibilityIdentifier("settings.showNoteText")
            StatusRow(title: "Location for place reminders", value: locationText)
            StatusRow(title: "Reminders set", value: "\(reminders.reminders.count) of \(NoteReminderLimits.maxActive)")
            StatusRow(
                title: "At a place",
                value: "\(reminders.reminders.filter { $0.place != nil }.count) of \(NoteReminderLimits.maxPlaces)")
            Button("Cancel all reminders", role: .destructive) { confirmCancelAll = true }
                .disabled(reminders.reminders.isEmpty)
            Text(showNoteText
                ? "On: the note's text is shown on your Lock Screen and stored by iOS with the notification."
                : "Off: notifications say only \"\(NoteReminderCopy.privateBody)\" The note text never leaves Doddy.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .confirmationDialog(
            "Cancel all \(reminders.reminders.count) reminders?", isPresented: $confirmCancelAll, titleVisibility: .visible
        ) {
            Button("Cancel all reminders", role: .destructive) { Task { await reminders.cancelAll() } }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text("Your notes stay. Only the reminders are removed.")
        }
    }

    private var locationText: String {
        switch reminders.locationReadiness {
        case .ready: "While Using, precise"
        case .approximateOnly: "Precise Location off"
        case .denied: "Off"
        case .notDetermined: "Not asked yet"
        case .unavailable: "Location Services off"
        }
    }

    private var statusText: String {
        switch reminders.authorization {
        case .allowed: "Allowed"
        case .denied: "Off"
        case .notDetermined: "Not asked yet"
        }
    }
}
