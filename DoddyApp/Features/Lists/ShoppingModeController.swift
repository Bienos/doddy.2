@preconcurrency import ActivityKit
import DoddyCore
import Foundation
import Observation

/// Starts, updates and ends shopping mode's Live Activity (ADR-257). One list at a time. It is
/// redrawn from the store after every change (including ticks from the Lock Screen), ends from
/// the list, when every item is ticked, when the list is deleted, or by itself after
/// `ShoppingMode.staleAfter`.
@MainActor
@Observable
final class ShoppingModeController {
    static let shared = ShoppingModeController()

    @ObservationIgnored weak var store: MemoryStore?
    private(set) var listID: UUID?
    private(set) var problem: String?
    @ObservationIgnored private var activity: Activity<ShoppingActivityAttributes>?
    @ObservationIgnored private var shown: ShoppingModeState?

    private init() {}

    var isAvailable: Bool { DeviceSupport.host.supports(.liveActivities) && ActivityAuthorizationInfo().areActivitiesEnabled }

    func isOn(for listID: UUID) -> Bool { self.listID == listID }

    /// A shopping mode still running from before a relaunch is picked up again, or ended if its
    /// list is gone.
    func reattach() {
        guard activity == nil, let running = Activity<ShoppingActivityAttributes>.activities.first else { return }
        activity = running
        listID = running.attributes.listID
        refresh()
    }

    func start(_ list: DoddyList) {
        problem = nil
        if listID != nil { end() }
        guard isAvailable else {
            problem = NSLocalizedString("Live Activities are off for Doddy. Turn them on in the Settings app, under Doddy.", comment: "")
            return
        }
        let state = ShoppingModeState.make(list)
        do {
            activity = try Activity.request(
                attributes: ShoppingActivityAttributes(listID: list.id),
                content: Self.content(state), pushType: nil)
            listID = list.id
            shown = state
        } catch {
            problem = NSLocalizedString("Shopping mode couldn't start. Try again.", comment: "")
        }
    }

    /// Called whenever the store changes (WidgetSync.refresh).
    func refresh() {
        guard let activity, let listID, let store, store.hasLoaded else { return }
        guard let list = store.list(id: listID) else {
            end()
            return
        }
        let state = ShoppingModeState.make(list)
        guard state != shown else { return }
        shown = state
        if state.isFinished {
            // "All ticked" stays a moment on the Lock Screen, then goes.
            self.activity = nil
            self.listID = nil
            Task {
                await activity.end(Self.content(state), dismissalPolicy: .after(.now.addingTimeInterval(ShoppingMode.finishedCardFor)))
            }
        } else {
            Task { await activity.update(Self.content(state)) }
        }
    }

    func end() {
        guard let activity else { listID = nil; return }
        self.activity = nil
        listID = nil
        shown = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private static func content(_ state: ShoppingModeState) -> ActivityContent<ShoppingModeState> {
        ActivityContent(state: state, staleDate: .now.addingTimeInterval(ShoppingMode.staleAfter))
    }
}
