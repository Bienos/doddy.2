import DoddyCore
import EventKit
import EventKitUI
import SwiftUI

// Today's tap on an event (owner, 13 Nov 2026: "zero edycji, tutaj nie można nic zrobić"): Apple's own event
// editor, where the person changes or deletes the event and iOS writes it to Calendar. Doddy writes nothing
// itself here. When the editor closes, Calendar is read again and the screen says what it found: "saved" or
// "deleted" only from that read-back (DOD-08). In this folder because the capability guard keeps calendar
// code here; the Today screen only passes these values along. Not run on a device yet.

/// One occurrence of an event, found again in Calendar and ready for the editor.
struct EditableCalendarEvent: Identifiable {
    /// The occurrence's id, as `CalendarEventSummary.id` (item id and start).
    let id: String
    let title: String
    let start: Date
    let end: Date
    fileprivate let store: EKEventStore
    fileprivate let event: EKEvent
}

/// What the editor did, as Calendar shows it afterwards.
enum CalendarEditorOutcome: Equatable, Sendable {
    case cancelled
    /// `moved`: the occurrence starts at another time now, so its id (and a nudge's) no longer match.
    case saved(title: String, confirmed: Bool, previousID: String, moved: Bool)
    case deleted(title: String, confirmed: Bool, id: String)
}

@MainActor
enum CalendarEventEditing {
    enum Lookup {
        case editable(EditableCalendarEvent)
        /// Its calendar can't be changed (a subscribed calendar, Birthdays, a shared one read only).
        case readOnly
        /// iOS gives Doddy less than full access to Calendar.
        case notAllowed
        /// It's no longer in Calendar as the screen showed it (moved, renamed or deleted elsewhere).
        case notFound
    }

    /// The editor needs the store the event came from; one for this screen, apart from DeviceConnections'.
    private static let store = EKEventStore()

    static func find(_ summary: CalendarEventSummary) -> Lookup {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return .notAllowed }
        guard let id = summary.id,
              let event = events(in: store, from: summary.start, to: summary.end).first(where: { occurrenceID($0) == id }) else {
            return .notFound
        }
        guard event.calendar?.allowsContentModifications == true else { return .readOnly }
        let title = event.title ?? summary.title
        return .editable(EditableCalendarEvent(id: id, title: title, start: summary.start, end: summary.end, store: store, event: event))
    }

    fileprivate static func events(in store: EKEventStore, from start: Date, to end: Date) -> [EKEvent] {
        let predicate = store.predicateForEvents(withStart: start.addingTimeInterval(-60), end: end.addingTimeInterval(60), calendars: nil)
        return store.events(matching: predicate)
    }

    fileprivate static func occurrenceID(_ event: EKEvent) -> String {
        CalendarEventSummary.occurrenceID(itemID: event.calendarItemIdentifier, start: event.startDate)
    }

    /// Calendar read again after the editor closed.
    fileprivate static func outcome(_ action: EKEventEditViewAction, editable: EditableCalendarEvent, event: EKEvent?) -> CalendarEditorOutcome {
        switch action {
        case .saved:
            guard let event, let start = event.startDate, let end = event.endDate else {
                return .saved(title: editable.title, confirmed: false, previousID: editable.id, moved: false)
            }
            let title: String = event.title ?? editable.title
            let itemID = event.calendarItemIdentifier
            let readBack = events(in: editable.store, from: start, to: end).contains { found in
                found.calendarItemIdentifier == itemID && (found.title ?? "") == title
                    && found.startDate == start && found.endDate == end
            }
            return .saved(title: title, confirmed: readBack, previousID: editable.id, moved: occurrenceID(event) != editable.id)
        case .deleted:
            let stillThere = events(in: editable.store, from: editable.start, to: editable.end).contains { occurrenceID($0) == editable.id }
            return .deleted(title: editable.title, confirmed: !stillThere, id: editable.id)
        case .canceled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }
}

/// Apple's event editor for one occurrence. Its Cancel, Done and Delete close it; iOS asks itself whether
/// a change to a repeating event is for this one or the ones after.
struct CalendarEventEditor: UIViewControllerRepresentable {
    let editable: EditableCalendarEvent
    let onFinish: @MainActor (CalendarEditorOutcome) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(editable: editable, onFinish: onFinish) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = editable.store
        controller.event = editable.event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    @MainActor
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let editable: EditableCalendarEvent
        var onFinish: @MainActor (CalendarEditorOutcome) -> Void
        /// The editor answers once; a second call (it has happened with UIKit delegates) is ignored.
        private var finished = false

        init(editable: EditableCalendarEvent, onFinish: @escaping @MainActor (CalendarEditorOutcome) -> Void) {
            self.editable = editable
            self.onFinish = onFinish
        }

        nonisolated func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            MainActor.assumeIsolated {
                self.finish(controller, action: action)
            }
        }

        private func finish(_ controller: EKEventEditViewController, action: EKEventEditViewAction) {
            guard !finished else { return }
            finished = true
            onFinish(CalendarEventEditing.outcome(action, editable: editable, event: controller.event))
        }
    }
}
