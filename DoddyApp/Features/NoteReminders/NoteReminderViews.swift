import DoddyCore
import SwiftUI
import UIKit
import UserNotifications

/// Memory detail: "Remind me", or the reminder that is set with Change / Cancel, plus the receipt.
struct NoteReminderSection: View {
    let memoryID: UUID

    @Environment(NoteReminderStore.self) private var reminders
    @State private var showSheet = false
    /// Opens the sheet on "At a time" (from a blocked place reminder's receipt).
    @State private var sheetAtTime = false
    @State private var confirmStop = false

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
        .coversDoddy(showSheet)
        .confirmationDialog(stopQuestion, isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop", role: .destructive) { Task { await reminders.cancel(memoryID: memoryID) } }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The note stays.")
        }
    }

    private var stopQuestion: String {
        guard let reminder = reminders.reminder(forMemory: memoryID), let rule = reminder.repeats,
              case .time(let anchor, let zone) = reminder.trigger else { return NSLocalizedString("Stop this reminder?", comment: "") }
        return "Stop reminding you \(ReminderFormat.cadence(rule, anchor: anchor, timeZoneID: zone))?"
    }

    private func open(atTime: Bool = false) {
        sheetAtTime = atTime
        showSheet = true
    }

    private func card(_ reminder: MemoryReminder) -> some View {
        let alerts = reminders.authorization == .allowed
        let atPlace = reminder.place != nil
        let repeating = reminder.repeats != nil
        let zone = reminder.timeZoneID ?? TimeZone.autoupdatingCurrent.identifier
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: atPlace ? "mappin.and.ellipse" : repeating ? "repeat" : alerts ? "bell" : "bell.slash").accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cardLabel(reminder, alerts: alerts))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    Text(ReminderFormat.summary(reminder))
                        .font(.headline)
                    if repeating, let next = reminder.nextFire(after: .now) {
                        Text("Next \(ReminderFormat.dateTime(next, timeZoneID: zone))")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if let firstSetFor = reminder.firstSetFor {
                        Text("First set for \(ReminderFormat.dateTime(firstSetFor, timeZoneID: zone))")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if let lastDone = reminder.lastDoneAt, reminder.snoozedUntil == nil {
                        Label("Done this time on \(ReminderFormat.dateTime(lastDone, timeZoneID: zone))", systemImage: "checkmark")
                            .font(.footnote)
                            .foregroundStyle(Theme.confirmed)
                    }
                    if let place = reminder.place {
                        Text("Within \(place.radiusMeters) m, each time, until you mark it Done.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    // Said only when AlarmKit lists its alarm (ADR-608).
                    if reminders.ringing.contains(reminder.memoryID) {
                        Label("Rings like an alarm, even in Silent mode", systemImage: "alarm")
                            .font(.footnote)
                            .foregroundStyle(Theme.accentText)
                    } else if reminders.wantsToRing(memoryID: reminder.memoryID), ReminderRing.plan(for: reminder, now: .now) != nil {
                        Label("Set to ring like an alarm, but the iPhone hasn't confirmed the alarm. Check that Doddy may set alarms in iPhone Settings.", systemImage: "alarm.waves.left.and.right")
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
                Button(repeating ? "Stop repeating" : "Cancel reminder", role: .destructive) {
                    // Stopping a repeat asks first; one stray tap can't end it (design screen 16).
                    if repeating { confirmStop = true } else { Task { await reminders.cancel(memoryID: memoryID) } }
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

    private func cardLabel(_ reminder: MemoryReminder, alerts: Bool) -> String {
        let kind = reminder.repeats != nil ? "Repeating reminder" : reminder.firstSetFor != nil ? "Reminder · snoozed" : "Reminder"
        return alerts ? kind : "\(kind) · in Doddy only"
    }
}

/// Built only from a real outcome: verified with iOS, kept in Doddy only, or failed.
struct NoteReminderReceiptView: View {
    let receipt: NoteReminderReceipt
    let retry: () -> Void
    /// Offered when a place reminder is blocked by a setting: a time reminder needs no location.
    var atTimeInstead: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL
    @Environment(NoteReminderStore.self) private var reminders

    /// "Reminder set for …", "Reminder set: every Monday at 20:00.", or after a snooze "Moved to …".
    static func headline(_ reminder: MemoryReminder) -> String {
        let zone = reminder.timeZoneID ?? TimeZone.autoupdatingCurrent.identifier
        if let snoozedUntil = reminder.snoozedUntil {
            return "Moved to \(ReminderFormat.dateTime(snoozedUntil, timeZoneID: zone)). The repeat carries on."
        }
        if reminder.firstSetFor != nil { return "Moved to \(ReminderFormat.short(reminder))." }
        if reminder.repeats != nil { return "Reminder set: \(ReminderFormat.short(reminder))." }
        return reminder.place == nil
            ? "Reminder set for \(ReminderFormat.short(reminder))."
            : "Reminder set \(ReminderFormat.short(reminder))."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch receipt {
            case .scheduled(let reminder):
                Label(Self.headline(reminder), systemImage: "checkmark")
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
                // Said from iOS's answer now, not assumed (review F9): after "Not now" iOS was never
                // asked, so notifications aren't "off".
                switch reminders.authorization {
                case .notDetermined:
                    Text("Doddy hasn't asked to send notifications yet, so your iPhone won't alert you. When it's due, the note waits at the top of Home.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    Button("Allow notifications") { Task { await reminders.requestAuthorization() } }
                        .frame(minHeight: 44)
                case .denied:
                    Text("Notifications are off for Doddy, so your iPhone won't alert you. When it's due, the note waits at the top of Home.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                    .frame(minHeight: 44)
                case .allowed:
                    Text("Notifications are allowed now, so Doddy has asked iOS to alert you when it's due.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
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
                Button(reminder.repeats == nil ? "Done" : "Done this time") {
                    Task { await reminders.done(reminderID: reminder.id) }
                }
                .buttonStyle(PrimaryButtonStyle())
                Menu {
                    ForEach(NoteReminderStore.snoozeChoices(now: .now), id: \.self) { option in
                        Button("\(Self.title(option.choice)) · \(option.date.formatted(date: .omitted, time: .shortened))") {
                            Task { await reminders.snooze(reminderID: reminder.id, until: option.date) }
                        }
                    }
                    // Opens the note, where Change picks any time.
                    Button("Pick a time…") { reminders.pendingOpenMemoryID = record.id }
                } label: {
                    Text("Later…").frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("home.due.later")
            }
        }
    }
}

extension DueRemindersView {
    static func title(_ choice: NoteReminderStore.SnoozeChoice) -> String {
        switch choice {
        case .inAnHour: NSLocalizedString("In 1 hour", comment: "")
        case .thisEvening: NSLocalizedString("This evening", comment: "")
        case .tomorrowMorning: NSLocalizedString("Tomorrow morning", comment: "")
        }
    }
}

private struct DueItem: Identifiable {
    let reminder: MemoryReminder
    let record: MemoryRecord
    var id: UUID { reminder.id }
}

/// Note-reminder notifications iOS already delivered (Lock Screen, Notification Centre).
enum DeliveredNoteReminders {
    /// Removes them, so none keeps showing a note's text once "Show note text" is off (review
    /// F4). Only Doddy's note reminders (`MemoryReminder.notificationPrefix`); the reminders
    /// themselves stay, and one that is due waits at the top of Home.
    static func removeAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.deliveredNotifications().map(\.request.identifier)
            .filter { $0.hasPrefix(MemoryReminder.notificationPrefix) }
        if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
    }
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
                .onChange(of: showNoteText) { _, shown in
                    Task {
                        await reminders.noteTextSettingChanged()
                        // Rewriting waiting notifications doesn't reach ones already delivered,
                        // which keep the words they arrived with (review F4).
                        if !shown { await DeliveredNoteReminders.removeAll() }
                    }
                }
                .accessibilityIdentifier("settings.showNoteText")
            StatusRow(title: "Location for place reminders", value: locationText)
            StatusRow(title: "Reminders set", value: "\(reminders.slotsUsed) of \(NoteReminderLimits.maxActive)")
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
        case .ready: NSLocalizedString("While Using, precise", comment: "")
        case .approximateOnly: NSLocalizedString("Precise Location off", comment: "")
        case .denied: "Off"
        case .notDetermined: NSLocalizedString("Not asked yet", comment: "")
        case .unavailable: NSLocalizedString("Location Services off", comment: "")
        }
    }

    private var statusText: String {
        switch reminders.authorization {
        case .allowed: NSLocalizedString("Allowed", comment: "")
        case .denied: "Off"
        case .notDetermined: NSLocalizedString("Not asked yet", comment: "")
        }
    }
}
