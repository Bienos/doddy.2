import DoddyCore
import SwiftUI

/// "At a place" (ADR-194): pick where (here, or an Apple Maps search), name it, choose arrive or
/// leave and how close. Nothing is stored until Set reminder, and nothing is stored at all unless
/// notifications and precise location are on: a place reminder has no in-app fallback.
struct NotePlacePicker: View {
    let memoryID: UUID
    let onDone: () -> Void

    @Environment(NoteReminderStore.self) private var reminders

    @State private var picked: PlaceCoordinate?
    @State private var name = ""
    @State private var address = ""
    @State private var onArrival = true
    @State private var radius = ReminderPlace.defaultRadius
    @State private var query = ""
    @State private var results: [PlaceSearchResult] = []
    @State private var lastHere: PlaceCoordinate?
    @State private var busy = false
    @State private var problem: String?
    @State private var showExplainer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showExplainer {
                explainer
            } else if picked != nil {
                chosen
            } else {
                finder
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.error)
                    .accessibilityIdentifier("place.problem")
            }
        }
        .onAppear(perform: prefill)
    }

    // MARK: Finding a place

    private var finder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { Task { await useHere() } } label: {
                HStack { Text(busy ? "Finding where you are…" : "Use where I am now"); Spacer(); Image(systemName: "location") }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(busy)
            .accessibilityIdentifier("place.here")

            HStack {
                TextField("Search for a place", text: $query)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                    .textInputAutocapitalization(.words)
                    .padding(12)
                    .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("place.search")
                Button { Task { await search() } } label: {
                    Image(systemName: "magnifyingglass").frame(width: 44, height: 44)
                }
                .disabled(busy || query.allSatisfy(\.isWhitespace))
                .accessibilityLabel("Search")
            }
            Text("Search words go to Apple Maps to find the place.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)

            ForEach(results) { result in
                Button { choose(result) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name).font(.headline)
                        if !result.address.isEmpty {
                            Text(result.address).font(.subheadline).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    // MARK: The chosen place

    private var chosen: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Name this place", text: $name)
                .textInputAutocapitalization(.words)
                .padding(12)
                .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("Name this place")
                .accessibilityIdentifier("place.name")
            if !address.isEmpty {
                Text(address).font(.subheadline).foregroundStyle(Theme.secondaryText)
            }

            Picker("When", selection: $onArrival) {
                Text("When I arrive").tag(true)
                Text("When I leave").tag(false)
            }
            .pickerStyle(.segmented)

            Picker("How close", selection: $radius) {
                ForEach(ReminderPlace.radiusOptions, id: \.self) { Text("\($0) m").tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("How close, in metres")

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "mappin.and.ellipse").accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary).font(.headline)
                    Text("Within \(radius) m, each time, until you mark it Done. iOS watches this place on your iPhone; Doddy doesn't follow where you go.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)

            Button { confirm() } label: {
                HStack { Text(busy ? "Setting…" : "Set reminder"); Spacer() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy || name.allSatisfy(\.isWhitespace))
            .accessibilityIdentifier("place.set")

            Button("Choose another place") {
                picked = nil
                problem = nil
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var summary: String {
        let shown = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = shown.isEmpty ? "this place" : shown
        return onArrival ? "When you arrive at \(label)" : "When you leave \(label)"
    }

    // MARK: Permissions

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Doddy needs two permissions for this")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Text("To remind you \(summary.prefix(1).lowercased() + summary.dropFirst()), iOS needs to let Doddy send notifications and use your location while you use the app.")
            VStack(alignment: .leading, spacing: 10) {
                Label("iOS watches the place on this iPhone. Doddy never follows where you go.", systemImage: "checkmark")
                Label("Doddy asks for \u{201C}While Using\u{201D} only, never \u{201C}Always\u{201D}.", systemImage: "checkmark")
                Label("Keep Precise Location on, or iOS can't tell when you get there.", systemImage: "checkmark")
            }
            .font(.subheadline)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))

            Button {
                Task {
                    busy = true
                    if reminders.authorization == .notDetermined { await reminders.requestAuthorization() }
                    if reminders.locationReadiness == .notDetermined { await reminders.requestLocation() }
                    await commit()
                }
            } label: { HStack { Text("Continue"); Spacer() } }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy)
            .accessibilityIdentifier("place.permission.continue")

            Button("Not now (nothing is saved)") { onDone() }
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(busy)
        }
    }

    // MARK: Actions

    private func prefill() {
        guard picked == nil, let place = reminders.reminder(forMemory: memoryID)?.place else { return }
        picked = PlaceCoordinate(latitude: place.latitude, longitude: place.longitude)
        name = place.name
        onArrival = place.onArrival
        radius = ReminderPlace.radiusOptions.contains(place.radiusMeters) ? place.radiusMeters : ReminderPlace.defaultRadius
    }

    private func useHere() async {
        problem = nil
        if reminders.locationReadiness == .notDetermined { await reminders.requestLocation() }
        guard reminders.locationReadiness == .ready else {
            problem = NoteReminderStore.message(for: NoteReminderError.placeNeedsLocation(reminders.locationReadiness))
            return
        }
        busy = true
        defer { busy = false }
        guard let here = await PlaceLocation.shared.currentCoordinate() else {
            problem = "Couldn't find where you are right now. Try again in a moment, or search for the place."
            return
        }
        lastHere = here
        picked = here
        address = ""
        if name.allSatisfy(\.isWhitespace) { name = "Here" }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        problem = nil
        busy = true
        defer { busy = false }
        do {
            results = try await PlaceLocation.shared.search(text, near: lastHere)
            if results.isEmpty { problem = "Apple Maps found nothing for \u{201C}\(text)\u{201D}. Try other words." }
        } catch {
            results = []
            problem = "Couldn't search Apple Maps. Check your internet connection and try again."
        }
    }

    private func choose(_ result: PlaceSearchResult) {
        picked = result.coordinate
        name = String(result.name.prefix(ReminderPlace.maxNameLength))
        address = result.address
        results = []
        problem = nil
    }

    private func confirm() {
        if reminders.authorization == .notDetermined || reminders.locationReadiness == .notDetermined {
            showExplainer = true
        } else {
            Task { await commit() }
        }
    }

    private func commit() async {
        guard let picked,
              let place = try? ReminderPlace(
                  name: name, latitude: picked.latitude, longitude: picked.longitude,
                  radiusMeters: radius, onArrival: onArrival)
        else {
            showExplainer = false
            problem = NoteReminderStore.message(for: NoteReminderError.invalidPlace)
            return
        }
        busy = true
        await reminders.set(memoryID: memoryID, place: place)
        busy = false
        onDone()
    }
}
