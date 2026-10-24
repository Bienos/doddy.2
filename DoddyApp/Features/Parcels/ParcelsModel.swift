import DoddyCore
import Foundation
import Observation

/// The "Przesyłki" list's state (ADR-634): the parcels the person added, kept on this iPhone, and what
/// InPost last said about each. The list is off until they turn it on; a parcel is looked up only when
/// they add it or tap Refresh (`ParcelLookupPolicy`, checked again by `ParcelTracker`); a look-up that
/// can't be read leaves the last known status as it was. No UI framework here, so
/// scripts/typecheck_app_logic.sh compiles it; the screen is ParcelsView.
@MainActor
@Observable
final class ParcelsModel {
    static let storageKey = "parcelBook"

    private(set) var book: ParcelBook
    /// What the last look-up of a parcel said when it found nothing to show ("InPost has no record…").
    private(set) var notes: [String: String] = [:]
    /// The newest answer for a parcel, kept for the detail screen only until the app closes.
    private(set) var details: [String: ParcelTracking] = [:]
    private(set) var busy: Set<String> = []
    /// Why the last add did not happen.
    private(set) var message: String?

    private let defaults: UserDefaults
    private let tracker: ParcelTracker
    private let now: () -> Date
    /// "Pause all connections" in Settings: while it is on, nothing is looked up at InPost.
    private let isPaused: () -> Bool

    init(
        fetcher: any ParcelFetching, defaults: UserDefaults = .standard, isPaused: @escaping () -> Bool = { false },
        now: @escaping () -> Date = Date.init
    ) {
        self.tracker = ParcelTracker(fetcher: fetcher)
        self.defaults = defaults
        self.isPaused = isPaused
        self.now = now
        if let data = defaults.data(forKey: Self.storageKey), let saved = try? JSONDecoder().decode(ParcelBook.self, from: data) {
            book = saved
        } else {
            book = ParcelBook()
        }
    }

    /// The screens' language, as the list quantities use it.
    static var polish: Bool { NotificationLanguage.preferred(Bundle.main.preferredLocalizations) == .polish }

    var isOn: Bool { book.isOn }
    var entries: [ParcelEntry] { book.entries.sorted { $0.addedAt > $1.addedAt } }

    /// "Delete all" and turning the list off: the numbers go.
    static func forgetStoredList(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    // MARK: The list

    func setOn(_ on: Bool) {
        if on {
            book.isOn = true
        } else {
            book.turnOff()
            notes = [:]
            details = [:]
            busy = []
            message = nil
        }
        save()
    }

    func remove(_ entry: ParcelEntry) {
        book.remove(id: entry.id)
        notes[entry.number] = nil
        details[entry.number] = nil
        save()
    }

    /// The person typed or pasted a number. Adding it is their act, so it is looked up once.
    func add(number raw: String, label: String) async {
        guard let number = ParcelNumber(raw) else {
            message = String(
                format: NSLocalizedString("An InPost parcel number has %lld digits. Check that none is missing.", comment: ""),
                ParcelNumber.length)
            return
        }
        switch book.add(number, label: label, now: now()) {
        case .notTurnedOn:
            message = NSLocalizedString("Turn the parcel list on first.", comment: "")
        case .alreadyThere:
            message = NSLocalizedString("This parcel is already on the list.", comment: "")
        case .full:
            message = String(
                format: NSLocalizedString("The list holds at most %lld parcels. Remove one to add another.", comment: ""),
                ParcelBook.maxParcels)
        case .added:
            message = nil
            save()
            await look(number, trigger: .personAddedIt)
        }
    }

    /// The person tapped Refresh.
    func refresh(_ entry: ParcelEntry) async {
        guard let number = ParcelNumber(entry.number) else { return }
        await look(number, trigger: .personTappedRefresh)
    }

    private func look(_ number: ParcelNumber, trigger: ParcelLookupTrigger) async {
        guard book.mayLookUp(number), !busy.contains(number.digits) else { return }
        guard !isPaused() else {
            notes[number.digits] = NSLocalizedString("Connections are paused, so this parcel isn't checked.", comment: "")
            return
        }
        busy.insert(number.digits)
        let result = await tracker.lookup(number, trigger: trigger)
        busy.remove(number.digits)
        // Removed, or the list turned off, while InPost was answering: nothing comes back.
        guard book.mayLookUp(number) else { return }
        book.apply(result, now: now())
        if case .tracking(let tracking) = result {
            details[number.digits] = tracking
            notes[number.digits] = nil
        } else {
            notes[number.digits] = result.message(polish: Self.polish)
        }
        save()
    }

    // MARK: Words for the screen

    /// The last known status as a sentence, or that it hasn't been checked.
    func statusLine(for entry: ParcelEntry) -> String {
        if let tracking = details[entry.number] { return tracking.headline(polish: Self.polish) }
        guard let status = entry.lastStatus else { return NSLocalizedString("Not checked yet", comment: "") }
        let text = ParcelStatuses.text(for: status)
        return Self.polish ? text.polish : text.english
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(book) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
