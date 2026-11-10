import DoddyCore
import SwiftUI
import UIKit

/// Today at a glance (decision 2026-11-10-today-at-a-glance): a line about the day worked out by
/// code, what's on now and next (time to go, the place and a Maps link when the event has one), the
/// rest of today with the free time between events, reminders due with a tick, and the first few
/// things tomorrow. In Home's Today sheet with Doddy and the date, and in the morning check-in under
/// its own heading. `TodayModel` reads and writes; this view only shows.
struct TodayCard: View {
    /// Opens Settings, where Connections is.
    let openSettings: () -> Void
    /// The sheet shows Doddy and the date; the morning check-in has its own heading and picture.
    var showsDoddy = false

    @State private var model = TodayModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var timeColumn: CGFloat = 56

    private var language: NotificationLanguage { NotificationLanguage.preferred(Bundle.main.preferredLocalizations) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            switch model.content {
            case .loading:
                card { ProgressView().frame(maxWidth: .infinity) }
            case .notConnected:
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("See today's events and reminders here: turn on Calendar or Reminders in Settings, Connections. They're read on this iPhone only.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Settings", action: openSettings)
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityIdentifier("today.openSettings")
                    }
                }
            case .paused:
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Connections are paused, so Doddy isn't reading your calendar or reminders. Turn them back on in Settings, Connections.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Settings", action: openSettings)
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityIdentifier("today.openSettings.paused")
                    }
                }
            case .glance(let glance):
                glanceView(glance)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.content)
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        // VoiceOver hears a receipt where it appears, not only when it finds it.
        .onChange(of: model.notice) { _, new in announce(new) }
        .onChange(of: model.reminderNotice) { _, new in announce(new) }
        // A container keeps its own identifier only as an element; otherwise SwiftUI copies it onto
        // every child and the Open Settings button would lose `today.openSettings`. Not `home.today`,
        // which is the ••• menu's item.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.card")
    }

    private func announce(_ text: String?) {
        if let text { UIAccessibility.post(notification: .announcement, argument: text) }
    }

    // MARK: Header

    private var glance: TodayGlance? {
        if case .glance(let glance) = model.content { glance } else { nil }
    }

    /// Doddy reads the calendar when there's something on, and sits back when there's nothing left.
    private var pose: String {
        if let glance, !glance.isEmpty { "WholeDoddy_belly_reading" } else { "WholeDoddy_crosslegged" }
    }

    private var header: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: 12))
        return layout {
            if showsDoddy {
                UploadedCharacterView(assetName: pose, height: 96)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                if showsDoddy {
                    Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                } else {
                    Text("Today")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                }
                if let glance {
                    Text(verbatim: summary(glance))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("today.summary")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, showsDoddy ? 8 : 0)
    }

    private func summary(_ glance: TodayGlance) -> String {
        TodayGlanceText.summary(glance, nextTime: glance.nextUp.map { clock($0.start) }, language)
    }

    // MARK: The day

    @ViewBuilder
    private func glanceView(_ glance: TodayGlance) -> some View {
        if !glance.allDay.isEmpty {
            allDayStrip(glance.allDay)
        }
        if !glance.onNow.isEmpty || glance.nextUp != nil {
            nowAndNext(glance)
        }
        if !glance.later.isEmpty {
            laterCard(glance)
        }
        if let notice = model.notice {
            Text(notice)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityIdentifier("today.notice")
        }
        if glance.remindersOn, !glance.reminders.isEmpty || model.reminderNotice != nil {
            remindersCard(glance)
        }
        if !glance.tomorrow.isEmpty {
            tomorrowCard(glance)
        }
        if !glance.calendarOn || !glance.remindersOn {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(glance.calendarOn ? "Reminders are off for Doddy, so they aren't shown here." : "Calendar is off for Doddy, so events aren't shown here.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Settings", action: openSettings)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("today.openSettings.partial")
            }
        }
        Label("Read from Calendar and Reminders on this iPhone. Nothing here is sent anywhere.", systemImage: "lock")
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
    }

    /// Today's all-day events as small tags under the header.
    private func allDayStrip(_ events: [CalendarEventSummary]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(events, id: \.rowID) { event in
                Label {
                    Text(verbatim: event.title)
                } icon: {
                    Image(systemName: "calendar").foregroundStyle(Theme.orangeCue)
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
                .accessibilityLabel(String(format: NSLocalizedString("All day: %@", comment: "Today: an all-day event"), event.title))
            }
        }
    }

    /// What's on now and the next event, picked out with Doddy's orange edge.
    private func nowAndNext(_ glance: TodayGlance) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(glance.onNow, id: \.rowID) { event in
                VStack(alignment: .leading, spacing: 4) {
                    eyebrow(NSLocalizedString("On now", comment: "Today: an event that has started"))
                    Text(verbatim: event.title).font(.headline)
                    Text(verbatim: String(format: NSLocalizedString("Until %@", comment: "Today: when an event on now ends"), clock(event.end)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }
            if let free = glance.freeBeforeNext {
                freeRow(free)
            }
            if let next = glance.nextUp {
                if !glance.onNow.isEmpty { Divider() }
                nextUp(next)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.quietSurface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.orangeCue.opacity(0.6), lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.next")
    }

    private func nextUp(_ event: CalendarEventSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    // The time to go counts down by the minute while the screen is open.
                    TimelineView(.everyMinute) { context in
                        eyebrow(NSLocalizedString("Next up", comment: "Today: the next event") + " · "
                                + TodayGlanceText.status(NextUpStatus.of(event, at: context.date), endTime: clock(event.end), language))
                    }
                    Text(verbatim: event.title)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: "\(clock(event.start))–\(clock(event.end))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                nudgeMenu(event)
            }
            if let nudge = model.nudge(for: event) {
                nudgeLine(nudge, event: event)
            }
            if let location = model.nextLocation {
                Label {
                    Text(verbatim: location).lineLimit(3)
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                }
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                // A web address (an online meeting) is shown but has no place to go to.
                if let place = TodayGlance.mapsPlace(location), let url = OpenLinks.map(place: place) {
                    Link(destination: url) {
                        Label("Open in Maps", systemImage: "map")
                            .font(.footnote.weight(.semibold))
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .foregroundStyle(Theme.accentText)
                    .accessibilityIdentifier("today.maps")
                }
            }
        }
    }

    /// The rest of today after the next event, with the free time between.
    private func laterCard(_ glance: TodayGlance) -> some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(Text("Later today"))
                ForEach(glance.later, id: \.rowID) { item in
                    switch item {
                    case .event(let event): eventRow(event)
                    case .free(let slot): freeRow(slot)
                    }
                }
                if glance.moreLater > 0 {
                    Text(verbatim: String(format: NSLocalizedString("And %lld more in Calendar.", comment: ""), glance.moreLater))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    private func eventRow(_ event: CalendarEventSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            timeAndTitle(time: clock(event.start), title: event.title) {
                if let nudge = model.nudge(for: event) { nudgeLine(nudge, event: event) }
            }
            Spacer(minLength: 8)
            if event.start > .now {
                nudgeMenu(event)
            }
        }
    }

    private func freeRow(_ slot: FreeDay.Slot) -> some View {
        Label {
            Text(verbatim: TodayGlanceText.free(slot, start: clock(slot.start), end: clock(slot.end), language))
        } icon: {
            Image(systemName: "cup.and.saucer").foregroundStyle(Theme.confirmed)
        }
        .font(.footnote.monospacedDigit())
        .foregroundStyle(Theme.secondaryText)
        .padding(.vertical, 2)
    }

    // MARK: Reminders

    private func remindersCard(_ glance: TodayGlance) -> some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(Text("Reminders"))
                ForEach(glance.reminders) { reminder in
                    reminderRow(reminder)
                }
                if glance.moreReminders > 0 {
                    Text(verbatim: String(format: NSLocalizedString("And %lld more in Reminders.", comment: ""), glance.moreReminders))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                if let notice = model.reminderNotice {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("today.reminderNotice")
                        Spacer(minLength: 4)
                        if model.undoable != nil {
                            Button("Undo") { Task { await model.undoTick() } }
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.accentText)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("today.undo")
                        }
                    }
                }
            }
        }
    }

    private func reminderRow(_ reminder: ReminderSummary) -> some View {
        let busy = model.busyReminders.contains(reminder.id)
        return HStack(alignment: .center, spacing: 8) {
            Button {
                Task { await model.complete(reminder) }
            } label: {
                Group {
                    if busy {
                        ProgressView()
                    } else {
                        Image(systemName: "circle")
                            .font(.title3)
                            .foregroundStyle(Theme.ink)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityLabel(String(format: NSLocalizedString("Mark as done: %@", comment: "Today: ticks off a reminder in Reminders"), reminder.title))
            .accessibilityIdentifier("today.tick")
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: reminder.title)
                    .fixedSize(horizontal: false, vertical: true)
                if TodayAgenda.isOverdue(reminder, now: .now, calendar: .current) {
                    Text("Overdue").font(.footnote).foregroundStyle(Theme.error)
                } else if reminder.dueHasTime, let due = reminder.due {
                    Text(verbatim: String(format: NSLocalizedString("Due %@", comment: ""), clock(due)))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
    }

    // MARK: Tomorrow

    private func tomorrowCard(_ glance: TodayGlance) -> some View {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        return card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    sectionTitle(Text("Tomorrow"))
                    Spacer(minLength: 8)
                    Text(tomorrow, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                ForEach(glance.tomorrow, id: \.rowID) { item in
                    switch item {
                    case .event(let event):
                        timeAndTitle(time: event.allDay ? NSLocalizedString("All day", comment: "") : clock(event.start), title: event.title) {}
                    case .reminder(let reminder):
                        timeAndTitle(
                            time: reminder.dueHasTime ? reminder.due.map { clock($0) } ?? "" : NSLocalizedString("Reminder", comment: "Today: a reminder due tomorrow without a time"),
                            title: reminder.title) {}
                    }
                }
                if glance.moreTomorrow > 0 {
                    Text(verbatim: String(format: NSLocalizedString("And %lld more tomorrow.", comment: ""), glance.moreTomorrow))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.tomorrow")
    }

    // MARK: Pieces

    /// A time in its own column and the title beside it; the time goes above the title at the
    /// largest text sizes so neither is squeezed.
    private func timeAndTitle<Extra: View>(time: String, title: String, @ViewBuilder extra: () -> Extra) -> some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text(verbatim: time)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                .frame(minWidth: textSize.isAccessibilitySize ? nil : timeColumn, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .fixedSize(horizontal: false, vertical: true)
                extra()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func sectionTitle(_ title: Text) -> some View {
        title
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }

    private func eyebrow(_ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.orangeCue).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(verbatim: text)
                .textCase(.uppercase)
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    /// The same card as the rest of the new screens (Cheapest this week).
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.quietSurface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Nudges

    private func nudgeLine(_ nudge: ScheduledNudge, event: CalendarEventSummary) -> some View {
        Text(nudgeText(nudge, event: event))
            .font(.footnote)
            .foregroundStyle(nudge.fits(event) == false ? Theme.error : Theme.secondaryText)
    }

    private func nudgeText(_ nudge: ScheduledNudge, event: CalendarEventSummary) -> String {
        let time = nudge.fireAt?.formatted(date: .omitted, time: .shortened) ?? "?"
        return nudge.fits(event) == false
            ? "Nudge at \(time), the old time: the event moved. Set it again."
            : "Nudge at \(time)"
    }

    private func nudgeMenu(_ event: CalendarEventSummary) -> some View {
        Menu {
            ForEach(EventNudgePlan.leadMinuteOptions, id: \.self) { minutes in
                Button(minutes == 60 ? "1 hour before" : "\(minutes) minutes before") {
                    Task { await model.setNudge(for: event, leadMinutes: minutes) }
                }
            }
            if let nudge = model.nudge(for: event) {
                Button("Remove nudge", role: .destructive) {
                    Task { await model.cancel(nudge, title: event.title) }
                }
            }
        } label: {
            Image(systemName: model.nudge(for: event) == nil ? "bell" : "bell.fill")
                .foregroundStyle(Theme.accentText)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(String(format: NSLocalizedString("Nudge before %@", comment: ""), event.title))
        }
        .accessibilityIdentifier("today.nudge")
    }
}

private extension CalendarEventSummary {
    /// Events from the device always have an id; the fallback keeps ForEach stable regardless.
    var rowID: String { id ?? "\(title)@\(start.timeIntervalSince1970)" }
}

private extension TodayTimelineItem {
    var rowID: String {
        switch self {
        case .event(let event): event.rowID
        case .free(let slot): "free@\(slot.start.timeIntervalSince1970)"
        }
    }
}

private extension TomorrowItem {
    var rowID: String {
        switch self {
        case .event(let event): event.rowID
        case .reminder(let reminder): "reminder@\(reminder.id)"
        }
    }
}
