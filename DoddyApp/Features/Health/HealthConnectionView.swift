import DoddyCore
import SwiftUI

/// Settings › Connections › Apple Health (sport mode step 1, ADR-621). What Doddy may read from
/// Health and, once it's on, exactly what it sees for the last seven days. Nothing is sent or
/// spoken from here, except the week's summary (ADR-622): after a consent of its own, Messages
/// opens with that exact text and the person sends it with their own tap (ADR-620, decision 2).
/// Doddy's voice doesn't get Health data.
struct HealthConnectionView: View {
    /// Doddy's own switch. Off means Doddy reads nothing from Health; the permission itself lives
    /// in the Health app, which only the person can change.
    static let preferenceKey = "sport.appleHealth.on"

    @AppStorage(HealthConnectionView.preferenceKey) private var isOn = false
    @State private var glance: HealthGlance?
    @State private var problem: String?
    @State private var isWorking = false
    // Step 2 (ADR-622): the yes to sending a week summary to Doddy in Messages, with its version and time.
    @Environment(MemoryStore.self) private var store
    @AppStorage(HealthConnectionView.shareConsentVersionKey) private var shareConsentVersion = 0
    @AppStorage(HealthConnectionView.shareConsentAtKey) private var shareConsentAt: Double = 0
    @State private var askingConsent = false
    @State private var messagesDraft: MessagesDraft?
    @State private var pendingDraft: String?

    static let shareConsentVersionKey = "sport.healthShare.consentVersion"
    static let shareConsentAtKey = "sport.healthShare.consentAt"

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
                    Text("Nothing, unless you send the week's summary to Doddy in Messages yourself. Then only that text goes to Doddy's server and Claude (Anthropic), after your yes. Doddy's voice doesn't hear Health data.")
                }

                section(Text("What stays here")) {
                    Text("Health keeps your data. Doddy reads it only while this screen is open, keeps none of it and writes nothing to Health.")
                }

                if isOn {
                    seenNow
                }

                if isOn, let glance, !glance.isEmpty, let summary = HealthText.summary(glance) {
                    shareSection(summary)
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
        // Messages opens once the consent sheet has gone away, never while it is still closing.
        .sheet(isPresented: $askingConsent, onDismiss: {
            if let text = pendingDraft {
                pendingDraft = nil
                messagesDraft = MessagesDraft(text: text)
            }
        }) {
            HealthShareConsentSheet { allowed in
                if allowed, let glance, let summary = HealthText.summary(glance) {
                    shareConsentVersion = HealthShareConsent.version
                    shareConsentAt = Date().timeIntervalSince1970
                    pendingDraft = summary
                }
                askingConsent = false
            }
            .presentationDetents([.large])
        }
        .fullScreenCover(item: $messagesDraft) { draft in
            MessagesView(repository: store.environment.messageThreadRepository, draft: draft.text)
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

    // MARK: Ask Doddy about the week (ADR-622)

    /// The exact text that would be sent, and the button that puts it into Messages. Sending is
    /// the person's own tap on Send there.
    private func shareSection(_ summary: String) -> some View {
        section(Text("Ask Doddy about this week")) {
            Text("This is exactly what goes to Doddy if you send it. Messages opens with it in the box; you can change it, and nothing is sent until you tap Send.")
                .foregroundStyle(Theme.secondaryText)
            Text(verbatim: summary)
                .font(.callout)
                .monospacedDigit()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
                .textSelection(.enabled)
                .accessibilityIdentifier("health.summary")
            Button {
                if HealthShareConsent.isGranted(storedVersion: shareConsentVersion) {
                    messagesDraft = MessagesDraft(text: summary)
                } else {
                    askingConsent = true
                }
            } label: {
                Label("Ask Doddy about this week", systemImage: "bubble.left.and.text.bubble.right")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("health.askAboutWeek")
            if HealthShareConsent.isGranted(storedVersion: shareConsentVersion) {
                Button("Stop sending Health summaries") {
                    shareConsentVersion = 0
                    shareConsentAt = 0
                }
                .buttonStyle(SecondaryButtonStyle(tint: Theme.error))
                .accessibilityIdentifier("health.withdrawShare")
                Text("Messages you already sent stay in Messages until you delete them.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
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

    // MARK: The week summary (ADR-622)

    /// The message for Messages: the question, each workout of the last 7 days, the two weeks'
    /// totals, last night, resting heart rate, HRV and VO₂ max, in the app's language. Only what the
    /// screen shows; the oldest workouts are left out if it is too long. Nil if nothing fits.
    static func summary(_ glance: HealthGlance) -> String? {
        let question = NSLocalizedString("How did my week go? Rate it briefly, compare it with the week before and suggest one thing to change. No medical advice, please.", comment: "Apple Health summary")
            + "\n\n" + NSLocalizedString("My numbers from Apple Health:", comment: "Apple Health summary")
        let workoutLines = glance.workouts.map { "• " + name($0.activity) + " · " + details($0) }
        var other = [
            totals(glance.thisWeek, label: NSLocalizedString("Last 7 days", comment: "Apple Health summary")),
            totals(glance.previousWeek, label: NSLocalizedString("The 7 days before", comment: "Apple Health summary")),
        ]
        if let night = glance.lastNight {
            other.append(NSLocalizedString("Last night", comment: "Apple Health") + ": " + sleep(night))
        }
        if let resting = glance.restingHeartRate {
            other.append(NSLocalizedString("Resting heart rate", comment: "Apple Health") + ": " + reading(resting, unit: .beatsPerMinute))
        }
        if let hrv = glance.heartRateVariability {
            other.append(NSLocalizedString("Heart rate variability", comment: "Apple Health") + ": " + reading(hrv, unit: .milliseconds))
        }
        if let vo2 = glance.vo2Max {
            other.append("VO₂ max: " + vo2Max(vo2))
        }
        return HealthShareText.assemble(question: question, workoutLines: workoutLines, otherLines: other) { count in
            String(format: NSLocalizedString("(%@ older workouts left out)", comment: "Apple Health summary"), count.formatted())
        }
    }

    /// "Last 7 days: workouts 4 · total time 3 hr 5 min · running 14.0 km · average 5:21 /km".
    static func totals(_ week: WeekTotals, label: String) -> String {
        var parts = [String(format: NSLocalizedString("workouts %@", comment: "Apple Health summary"), week.workouts.formatted())]
        if week.duration > 0 {
            parts.append(String(format: NSLocalizedString("total time %@", comment: "Apple Health summary"), duration(week.duration)))
        }
        if week.runningMeters > 0 {
            parts.append(String(format: NSLocalizedString("running %@ km", comment: "Apple Health summary"),
                                (week.runningMeters / 1000).formatted(.number.precision(.fractionLength(1)))))
        }
        if let pace = week.runningPaceSecondsPerKilometre {
            parts.append(String(format: NSLocalizedString("average %@ /km", comment: "Apple Health summary"), HealthFormat.pace(pace)))
        }
        return label + ": " + parts.joined(separator: " · ")
    }

    private static func beats(_ value: Double) -> String {
        String(format: NSLocalizedString("%@ bpm", comment: "Heart rate, beats per minute"), Int(value.rounded()).formatted())
    }

    private static func millis(_ value: Double) -> String {
        String(format: NSLocalizedString("%@ ms", comment: "Milliseconds"), Int(value.rounded()).formatted())
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        // Whole minutes, so no "59 sec" rounding surprises.
        return formatter.string(from: (seconds / 60).rounded() * 60) ?? HealthFormat.clock(seconds)
    }
}

/// The summary waiting in Messages' box (ADR-622).
struct MessagesDraft: Identifiable {
    let id = UUID()
    let text: String
}

/// The yes before a summary of Health data can go to Doddy's server and Claude (ADR-620, decision
/// 2; GDPR Art. 9; App Review 5.1.2(i)). Asked once per wording (`HealthShareConsent.version`);
/// each summary is still sent only by the person's own tap on Send in Messages.
struct HealthShareConsentSheet: View {
    let answer: (Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Send Health summaries to Doddy?")
                        .font(.title2.bold())
                    Text("Health data is sensitive. Here is what happens if you allow it:")
                    VStack(alignment: .leading, spacing: 10) {
                        point(Text("Only the summary you see goes: the week's numbers, no raw data from Health."))
                        point(Text("It goes to Doddy's server and to Claude (Anthropic), which writes the answer. Doddy's server doesn't keep or log what you write, only how many questions you asked."))
                        point(Text("Your message and the answer are saved in Messages on this iPhone until you delete them."))
                        point(Text("Nothing is sent by itself: each time, Messages opens with the text and you tap Send."))
                        point(Text("You can take this back on the Apple Health screen at any time."))
                    }
                    Text("Doddy is an AI, not a doctor or a coach. For pain, dizziness or anything that worries you, see a doctor.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    Button("Allow") { answer(true) }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("health.share.allow")
                    Button("Not now") { answer(false) }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("health.share.notNow")
                }
                .padding(24)
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
        }
        .foregroundStyle(Theme.ink)
    }

    private func point(_ line: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(Theme.orangeCue)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            line
        }
    }
}
