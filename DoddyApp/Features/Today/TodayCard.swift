import DoddyCore
import SwiftUI
import UIKit

/// Today at a glance (decision 2026-11-10-today-at-a-glance): a line about the day worked out by
/// code, what's on now and next (time to go, the place and a Maps link when the event has one), the
/// rest of today with the free time between events, reminders due with a tick, and the first few
/// things tomorrow. In Home's Today sheet with Doddy and the date, and in the morning check-in under
/// its own heading. `TodayModel` reads and writes; this view only shows.
///
/// In Doddy's colours since 13 Nov 2026 (owner: "zero edycji … nie wiadomo o co tu chodzi"): the page
/// says what it is, and things can be changed here. "Add" puts a reminder in Reminders; a tap on a
/// reminder's words opens it to change or delete; a tap on an event opens Apple's event editor (or the
/// Calendar app, for a calendar Doddy can't change). Nothing shows as changed until it's read back.
struct TodayCard: View {
    /// Opens Settings, where Connections is.
    let openSettings: () -> Void
    /// The sheet shows the page header with Doddy; the morning check-in has its own heading and picture.
    var showsDoddy = false

    @State private var model = TodayModel()
    @State private var editingEvent: EditableCalendarEvent?
    @State private var reminderSheet: TodayReminderTarget?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .subheadline) private var timeColumn: CGFloat = 56

    private var language: NotificationLanguage { NotificationLanguage.preferred(Bundle.main.preferredLocalizations) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            switch model.content {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 60).doddyCard()
            case .notConnected:
                setupCard(
                    Text("See today's events and reminders here: turn on Calendar or Reminders in Settings, Connections. They're read on this iPhone only."),
                    identifier: "today.openSettings")
            case .paused:
                setupCard(
                    Text("Connections are paused, so Doddy isn't reading your calendar or reminders. Turn them back on in Settings, Connections."),
                    identifier: "today.openSettings.paused")
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
        .sheet(item: $editingEvent) { editable in
            CalendarEventEditor(editable: editable) { outcome in
                editingEvent = nil
                Task { await model.eventEditorFinished(outcome) }
            }
            .ignoresSafeArea()
            // Its own Cancel and Done close it, so Calendar is read again every time.
            .interactiveDismissDisabled()
        }
        .sheet(item: $reminderSheet) { target in
            TodayReminderEditor(target: target, model: model)
        }
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
    private var pose: IslandPose {
        if let glance, !glance.isEmpty { .bellyReading } else { .crosslegged }
    }

    @ViewBuilder
    private var header: some View {
        if showsDoddy {
            DoddyPageHeader(
                title: "Today",
                subtitle: "Your day: events from Calendar and reminders from Reminders on this iPhone.",
                pose: pose)
            dayLine
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let glance {
                    Text(verbatim: summary(glance))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("today.summary")
                }
            }
        }
    }

    /// The date and the line about the day, under the page header.
    private var dayLine: some View {
        HStack(alignment: .top, spacing: 12) {
            DoddyIconBadge(systemName: "sun.max", size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.ink)
                if let glance {
                    Text(verbatim: summary(glance))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("today.summary")
                }
            }
        }
        .doddyCard(padding: 14)
        .accessibilityElement(children: .combine)
    }

    private func summary(_ glance: TodayGlance) -> String {
        TodayGlanceText.summary(glance, nextTime: glance.nextUp.map { clock($0.start) }, language)
    }

    private func setupCard(_ text: Text, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            text
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings", action: openSettings)
                .buttonStyle(DoddyAccentButtonStyle())
                .accessibilityIdentifier(identifier)
        }
        .doddyCard()
    }

    // MARK: The day

    @ViewBuilder
    private func glanceView(_ glance: TodayGlance) -> some View {
        if glance.calendarOn {
            calendarSection(glance)
        }
        if glance.remindersOn {
            remindersSection(glance)
        }
        if !glance.tomorrow.isEmpty {
            tomorrowSection(glance)
        }
        if !glance.calendarOn || !glance.remindersOn {
            partlyOff(glance)
        }
        DoddyFinePrint(text: Text("Read from and saved to Calendar and Reminders on this iPhone. Nothing here goes to Doddy's server; Open in Maps hands the place to Apple Maps."))
    }

    private func hasEventsLeft(_ glance: TodayGlance) -> Bool {
        !glance.allDay.isEmpty || !glance.onNow.isEmpty || glance.nextUp != nil || !glance.later.isEmpty
    }

    // MARK: Calendar

    @ViewBuilder
    private func calendarSection(_ glance: TodayGlance) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            DoddySectionTitle(title: "Calendar")
            Text("Tap an event to change or delete it.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        if let notice = model.notice {
            DoddyNotice(text: Text(verbatim: notice))
                .accessibilityIdentifier("today.notice")
        }
        if !glance.allDay.isEmpty {
            allDayStrip(glance.allDay)
        }
        if !glance.onNow.isEmpty || glance.nextUp != nil {
            nowAndNext(glance)
        }
        if !glance.later.isEmpty {
            laterCard(glance)
        }
        if !hasEventsLeft(glance) {
            Text("Nothing more in Calendar today.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .doddyCard()
        }
    }

    /// Today's all-day events as tags.
    private func allDayStrip(_ events: [CalendarEventSummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(events, id: \.rowID) { event in
                Button { openEvent(event) } label: {
                    Label {
                        Text(verbatim: event.title)
                            .multilineTextAlignment(.leading)
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Theme.quietSurface, in: Capsule())
                    .overlay { Capsule().strokeBorder(Theme.separator, lineWidth: 1) }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: NSLocalizedString("All day: %@", comment: "Today: an all-day event"), event.title))
                .accessibilityHint("Opens the event to change or delete it")
            }
        }
    }

    /// What's on now and the next event, picked out with Doddy's orange edge.
    private func nowAndNext(_ glance: TodayGlance) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(glance.onNow, id: \.rowID) { event in
                Button { openEvent(event) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        eyebrow(NSLocalizedString("On now", comment: "Today: an event that has started"))
                        Text(verbatim: event.title)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                        Text(verbatim: String(format: NSLocalizedString("Until %@", comment: "Today: when an event on now ends"), clock(event.end)))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens the event to change or delete it")
            }
            if let free = glance.freeBeforeNext {
                freeRow(free)
            }
            if let next = glance.nextUp {
                if !glance.onNow.isEmpty { Divider().overlay(Theme.separator) }
                nextUp(next)
            }
        }
        .doddyCard(accent: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.next")
    }

    private func nextUp(_ event: CalendarEventSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button { openEvent(event) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        // The time to go counts down by the minute while the screen is open.
                        TimelineView(.everyMinute) { context in
                            eyebrow(NSLocalizedString("Next up", comment: "Today: the next event") + " · "
                                    + TodayGlanceText.status(NextUpStatus.of(event, at: context.date), endTime: clock(event.end), language))
                        }
                        Text(verbatim: event.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: "\(clock(event.start))–\(clock(event.end))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens the event to change or delete it")
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Later today")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
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
        .doddyCard()
    }

    private func eventRow(_ event: CalendarEventSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button { openEvent(event) } label: {
                timeAndTitle(time: clock(event.start), title: event.title) {
                    if let nudge = model.nudge(for: event) { nudgeLine(nudge, event: event) }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the event to change or delete it")
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

    /// Apple's editor for an event in a calendar Doddy may change; otherwise the Calendar app at that
    /// time, with a line saying why.
    private func openEvent(_ event: CalendarEventSummary) {
        switch CalendarEventEditing.find(event) {
        case .editable(let editable):
            editingEvent = editable
        case .readOnly:
            openInCalendar(event, why: NSLocalizedString("This calendar can't be changed from Doddy, so the event opened in the Calendar app.", comment: ""))
        case .notAllowed:
            openInCalendar(event, why: NSLocalizedString("Doddy doesn't have full access to Calendar, so the event opened in the Calendar app. To change events here, allow Full Access in iPhone Settings, Privacy, Calendars.", comment: ""))
        case .notFound:
            let model = self.model
            Task { await model.eventGone(event) }
        }
    }

    private func openInCalendar(_ event: CalendarEventSummary, why: String) {
        let model = self.model
        let didNotOpen = NSLocalizedString("The Calendar app didn't open. Open it yourself to change this event.", comment: "")
        guard let url = CalendarAppLink.url(at: event.start) else {
            model.say(didNotOpen)
            return
        }
        openURL(url) { accepted in
            Task { @MainActor in model.say(accepted ? why : didNotOpen) }
        }
    }

    // MARK: Reminders

    private func remindersSection(_ glance: TodayGlance) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                DoddySectionTitle(title: "Reminders") {
                    addReminderButton
                }
                Text("Tap the circle to tick one off, or the words to change it.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                if glance.reminders.isEmpty {
                    Text("Nothing due today.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(minHeight: 44, alignment: .leading)
                }
                ForEach(glance.reminders) { reminder in
                    reminderRow(reminder)
                }
                if glance.moreReminders > 0 {
                    Text(verbatim: String(format: NSLocalizedString("And %lld more in Reminders.", comment: ""), glance.moreReminders))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                if let notice = model.reminderNotice {
                    reminderNoticeRow(notice)
                }
            }
            .doddyCard(padding: 12)
        }
    }

    private var addReminderButton: some View {
        Button {
            reminderSheet = .add
        } label: {
            Label("Add", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.inkOnOrange)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Theme.orangeCue, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a reminder")
        .accessibilityIdentifier("today.addReminder")
    }

    private func reminderNoticeRow(_ notice: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: notice)
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
        .padding(.top, 4)
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
            Button {
                edit(id: reminder.id, title: reminder.title)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: reminder.title)
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        reminderDue(reminder)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens it to change or delete")
            .accessibilityIdentifier("today.reminder")
        }
    }

    @ViewBuilder
    private func reminderDue(_ reminder: ReminderSummary) -> some View {
        if TodayAgenda.isOverdue(reminder, now: .now, calendar: .current) {
            Label("Overdue", systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(Theme.error)
        } else if reminder.dueHasTime, let due = reminder.due {
            Text(verbatim: String(format: NSLocalizedString("Due %@", comment: ""), clock(due)))
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    /// Reads the reminder again and opens the sheet with it as Reminders has it now.
    private func edit(id: String, title: String) {
        let model = self.model
        Task {
            if let found = await model.reminderToEdit(id: id, title: title) {
                reminderSheet = .edit(found)
            }
        }
    }

    // MARK: Tomorrow

    private func tomorrowSection(_ glance: TodayGlance) -> some View {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        return VStack(alignment: .leading, spacing: 10) {
            DoddySectionTitle(title: "Tomorrow") {
                Text(tomorrow, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(glance.tomorrow, id: \.rowID) { item in
                    tomorrowRow(item)
                }
                if glance.moreTomorrow > 0 {
                    Text(verbatim: String(format: NSLocalizedString("And %lld more tomorrow.", comment: ""), glance.moreTomorrow))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .doddyCard(padding: 14)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.tomorrow")
    }

    @ViewBuilder
    private func tomorrowRow(_ item: TomorrowItem) -> some View {
        switch item {
        case .event(let event):
            Button { openEvent(event) } label: {
                timeAndTitle(time: event.allDay ? NSLocalizedString("All day", comment: "") : clock(event.start), title: event.title) {}
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the event to change or delete it")
        case .reminder(let reminder):
            Button { edit(id: reminder.id, title: reminder.title) } label: {
                timeAndTitle(
                    time: reminder.dueHasTime ? reminder.due.map { clock($0) } ?? "" : NSLocalizedString("Reminder", comment: "Today: a reminder due tomorrow without a time"),
                    title: reminder.title) {}
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens it to change or delete")
        }
    }

    // MARK: Partly off

    private func partlyOff(_ glance: TodayGlance) -> some View {
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
        .padding(.horizontal, 4)
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
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                extra()
            }
        }
        .accessibilityElement(children: .combine)
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

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Nudges

    private func nudgeLine(_ nudge: ScheduledNudge, event: CalendarEventSummary) -> some View {
        Text(verbatim: nudgeText(nudge, event: event))
            .font(.footnote)
            .foregroundStyle(nudge.fits(event) == false ? Theme.error : Theme.secondaryText)
    }

    private func nudgeText(_ nudge: ScheduledNudge, event: CalendarEventSummary) -> String {
        let time = nudge.fireAt?.formatted(date: .omitted, time: .shortened) ?? "?"
        return nudge.fits(event) == false
            ? String(format: NSLocalizedString("Nudge at %@, the old time: the event moved. Set it again.", comment: ""), time)
            : String(format: NSLocalizedString("Nudge at %@", comment: ""), time)
    }

    private func nudgeMenu(_ event: CalendarEventSummary) -> some View {
        Menu {
            ForEach(EventNudgePlan.leadMinuteOptions, id: \.self) { minutes in
                Button(nudgeChoice(minutes)) {
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

    private func nudgeChoice(_ minutes: Int) -> String {
        minutes == 60
            ? NSLocalizedString("1 hour before", comment: "Today: a nudge's lead time")
            : String(format: NSLocalizedString("%lld minutes before", comment: "Today: a nudge's lead time"), minutes)
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
