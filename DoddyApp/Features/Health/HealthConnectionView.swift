import DoddyCore
import SwiftUI

/// Settings › Connections › Apple Health (sport mode step 1, ADR-621). What Doddy may read from
/// Health and, once it's on, exactly what it sees for the last seven days. Nothing on this screen
/// is sent anywhere or spoken: Doddy's voice doesn't get Health data in this step (ADR-620,
/// decision 2: that comes later, as a short summary, after a yes of its own).
struct HealthConnectionView: View {
    /// Doddy's own switch. Off means Doddy reads nothing from Health; the permission itself lives
    /// in the Health app, which only the person can change.
    static let preferenceKey = "sport.appleHealth.on"

    @AppStorage(HealthConnectionView.preferenceKey) private var isOn = false
    @State private var glance: HealthGlance?
    @State private var problem: String?
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "heart.text.square")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.ink)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Apple Health")
                            .font(.title2.bold())
                        StatusPill(state: isOn ? .on : .off)
                    }
                }

                section(Text("Doddy can read")) {
                    bullet(Text("Workouts from the last 7 days: kind, time, distance, pace, calories and average heart rate"))
                    bullet(Text("Last night's sleep: time asleep and its stages"))
                    bullet(Text("Resting heart rate and heart rate variability (HRV)"))
                    bullet(Text("VO₂ max, the newest one"))
                }

                section(Text("What leaves your phone")) {
                    Text("Nothing. For now Doddy only shows these numbers on this screen. Doddy's voice doesn't hear them; that will ask for your yes first.")
                }

                section(Text("What stays here")) {
                    Text("Health keeps your data. Doddy reads it only while this screen is open, keeps none of it and writes nothing to Health.")
                }

                if isOn {
                    seenNow
                }

                if let problem {
                    ProblemView(message: problem)
                }

                actions

                section(Text("To stop it completely")) {
                    Text("In the Health app, tap your picture, then Apps, then Doddy, and turn off what Doddy may read. Doddy can't change that for you.")
                }
            }
            .padding(24)
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.canvas)
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: isOn) {
            if isOn { await load() } else { glance = nil }
        }
    }

    // MARK: What Doddy sees

    @ViewBuilder
    private var seenNow: some View {
        section(Text("What Doddy sees now")) {
            if let glance {
                if glance.isEmpty {
                    Text("Nothing to show. Either Health has nothing from the last 7 days, or Doddy isn't allowed to read it. iPhone doesn't tell apps which.")
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    seen(glance)
                }
            } else if problem == nil {
                ProgressView()
            }
            Button("Read again") {
                Task { await load() }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(isWorking)
            .accessibilityIdentifier("health.readAgain")
        }
    }

    @ViewBuilder
    private func seen(_ glance: HealthGlance) -> some View {
        if glance.workouts.isEmpty {
            row(title: "Workouts", value: NSLocalizedString("None in the last 7 days", comment: "Apple Health"))
        } else {
            ForEach(Array(glance.workouts.enumerated()), id: \.offset) { _, workout in
                row(name: HealthText.name(workout.activity), value: HealthText.details(workout))
            }
        }
        if let night = glance.lastNight {
            row(title: "Last night", value: HealthText.sleep(night))
        }
        if let resting = glance.restingHeartRate {
            row(title: "Resting heart rate", value: HealthText.reading(resting, unit: .beatsPerMinute))
        }
        if let hrv = glance.heartRateVariability {
            row(title: "Heart rate variability", value: HealthText.reading(hrv, unit: .milliseconds))
        }
        if let vo2Max = glance.vo2Max {
            row(title: "VO₂ max", value: HealthText.vo2Max(vo2Max))
        }
    }

    // MARK: On and off

    @ViewBuilder
    private var actions: some View {
        if !HealthReader.isAvailable {
            Text("Health isn't available on this device.")
                .foregroundStyle(Theme.secondaryText)
        } else if isOn {
            Button("Turn off") {
                isOn = false
                glance = nil
                problem = nil
            }
            .buttonStyle(SecondaryButtonStyle(tint: Theme.error))
            .accessibilityIdentifier("health.turnOff")
        } else {
            Button {
                Task { await turnOn() }
            } label: {
                Label("Turn on Apple Health", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isWorking)
            .accessibilityIdentifier("health.turnOn")
        }
    }

    private func turnOn() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await HealthReader.shared.requestRead()
            problem = nil
            isOn = true
        } catch {
            problem = error.localizedDescription
        }
    }

    private func load() async {
        isWorking = true
        defer { isWorking = false }
        do {
            glance = try await HealthReader.shared.glance(now: Date())
            problem = nil
        } catch {
            glance = nil
            problem = error.localizedDescription
        }
    }

    // MARK: Layout

    private func section<Content: View>(_ title: Text, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            title
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullet(_ line: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(Theme.orangeCue)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            line
        }
    }

    private func row(title: LocalizedStringKey, value: String) -> some View {
        rowBody(Text(title), value: value)
    }

    private func row(name: String, value: String) -> some View {
        rowBody(Text(verbatim: name), value: value)
    }

    private func rowBody(_ title: Text, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title.font(.headline)
            Text(verbatim: value)
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// The card on Settings › Connections that opens the Apple Health screen.
struct HealthConnectionCard: View {
    @AppStorage(HealthConnectionView.preferenceKey) private var isOn = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "heart.text.square")
                .font(.title3)
                .foregroundStyle(Theme.ink)
                .frame(width: 48, height: 48)
                .background(Theme.quietSurface, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Apple Health")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("Workouts, sleep and heart, shown on this iPhone only")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)
            StatusPill(state: isOn ? .on : .off)
        }
        .padding(16)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.separator, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows what Doddy can read from Apple Health.")
    }
}

/// Words and numbers for the screen, in the app's language. The numbers come from DoddyCore.
enum HealthText {
    enum Unit {
        case beatsPerMinute, milliseconds
    }

    static func name(_ activity: WorkoutActivity) -> String {
        switch activity {
        case .running: NSLocalizedString("Running", comment: "Workout kind")
        case .walking: NSLocalizedString("Walking", comment: "Workout kind")
        case .hiking: NSLocalizedString("Hiking", comment: "Workout kind")
        case .cycling: NSLocalizedString("Cycling", comment: "Workout kind")
        case .swimming: NSLocalizedString("Swimming", comment: "Workout kind")
        case .strength: NSLocalizedString("Strength training", comment: "Workout kind")
        case .hiit: NSLocalizedString("Intervals (HIIT)", comment: "Workout kind")
        case .yoga: NSLocalizedString("Yoga", comment: "Workout kind")
        case .other: NSLocalizedString("Workout", comment: "Workout kind")
        }
    }

    /// "Thu 07:00 · 8.2 km · 47:10 · 5:45 /km · 152 bpm · 610 kcal": only what Health has.
    static func details(_ workout: HealthWorkout) -> String {
        var parts = [workout.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())]
        if let meters = workout.distanceMeters {
            parts.append(String(format: NSLocalizedString("%@ km", comment: "Distance"),
                                (meters / 1000).formatted(.number.precision(.fractionLength(meters < 10_000 ? 2 : 1)))))
        }
        parts.append(HealthFormat.clock(workout.duration))
        if let pace = workout.paceSecondsPerKilometre {
            parts.append(String(format: NSLocalizedString("%@ /km", comment: "Pace, minutes per kilometre"), HealthFormat.pace(pace)))
        }
        if let heartRate = workout.averageHeartRate {
            parts.append(beats(heartRate))
        }
        if let kilocalories = workout.activeKilocalories {
            parts.append(String(format: NSLocalizedString("%@ kcal", comment: "Active energy"), Int(kilocalories.rounded()).formatted()))
        }
        return parts.joined(separator: " · ")
    }

    /// "7 hr 30 min asleep · deep 1 hr, REM 1 hr 30 min, core 5 hr".
    static func sleep(_ night: SleepNight) -> String {
        var text = String(format: NSLocalizedString("%@ asleep", comment: "Sleep"), duration(night.asleep))
        if let deep = night.deep, let rem = night.rem, let core = night.core {
            text += " · " + String(format: NSLocalizedString("deep %@, REM %@, core %@", comment: "Sleep stages"),
                                   duration(deep), duration(rem), duration(core))
        }
        return text
    }

    /// "52 bpm · 7-day average 54".
    static func reading(_ glance: ReadingGlance, unit: Unit) -> String {
        let latest = unit == .beatsPerMinute ? beats(glance.latest.value) : millis(glance.latest.value)
        let average = unit == .beatsPerMinute ? beats(glance.average) : millis(glance.average)
        return latest + " · " + String(format: NSLocalizedString("7-day average %@", comment: "Apple Health"), average)
    }

    static func vo2Max(_ reading: HealthReading) -> String {
        String(format: NSLocalizedString("%@ ml/kg/min", comment: "VO2 max"), reading.value.formatted(.number.precision(.fractionLength(1))))
            + " · " + reading.date.formatted(date: .abbreviated, time: .omitted)
    }

    private static func beats(_ value: Double) -> String {
        String(format: NSLocalizedString("%@ bpm", comment: "Heart rate, beats per minute"), Int(value.rounded()).formatted())
    }

    private static func millis(_ value: Double) -> String {
        String(format: NSLocalizedString("%@ ms", comment: "Milliseconds"), Int(value.rounded()).formatted())
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        // Whole minutes, so no "59 sec" rounding surprises.
        return formatter.string(from: (seconds / 60).rounded() * 60) ?? HealthFormat.clock(seconds)
    }
}
