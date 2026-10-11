import DoddyCore
import SwiftUI

/// Quick start (ADR-319): once, after the introduction. The notifications start ticked (the evening
/// wrap-up only with Reminders connected) and the profile switch doesn't; nothing changes until "Turn these on", and every result shown
/// afterwards is what iOS or the store read back.
struct QuickStartView: View {
    /// There are saved "About you" answers, so using them in voice conversations can be offered.
    let profileSaved: Bool
    let done: () -> Void

    private enum Phase: Equatable {
        case choosing
        case applying
        case applied([Receipt])
    }

    struct Receipt: Equatable, Identifiable {
        let id: String
        let text: String
        let isProblem: Bool
    }

    @State private var choices = QuickStartChoices.suggested(
        remindersConnected: UserDefaults.standard.bool(forKey: VoiceConnection.reminders.preferenceKey)
            && DeviceConnections().access(for: .reminders) == .granted)
    /// Read once when the screen opens; anything already on isn't offered again.
    @State private var current = QuickStart.Current(
        morningCheckIn: MorningCheckInSettings.stored().isOn,
        eveningWrapUp: EveningWrapUpSettings.stored().isOn,
        weeklyTidyUp: TidyUpSettings.stored().isOn,
        weeklyLookBack: WeeklyLookBackSettings.stored().isOn,
        useProfileInVoice: UserDefaults.standard.bool(forKey: PreferenceKey.shareProfileWithVoice))

    private var plan: QuickStart.Plan { QuickStart.plan(choices, profileSaved: profileSaved, current: current) }
    @State private var phase: Phase = .choosing

    var body: some View {
        OnboardingPage {
            OnboardingLabel(text: "Quick start · optional")
            switch phase {
            case .choosing, .applying:
                choosing
            case .applied(let receipts):
                applied(receipts)
            }
        }
    }

    private var choosing: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("A few things that make Doddy easier.")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Nothing changes until you tap the button. You can change any of it later in Settings.")
                .foregroundStyle(Theme.secondaryText)

            VStack(alignment: .leading, spacing: 10) {
                if !current.morningCheckIn {
                    QuickStartRow(
                        title: "Morning check-in",
                        detail: String(format: NSLocalizedString("%@ on weekdays. A quick look at your day: reminders and lists.", comment: ""),
                                       Self.time(QuickStart.morning.hour, QuickStart.morning.minute)),
                        isOn: $choices.morningCheckIn, id: "quickStart.morning")
                }
                if !current.eveningWrapUp {
                    QuickStartRow(
                        title: "Evening wrap-up",
                        detail: String(format: NSLocalizedString("%@ every day. Move today's open reminders to tomorrow. Needs Reminders on in Connections.", comment: ""),
                                       Self.time(QuickStart.evening.hour, QuickStart.evening.minute)),
                        isOn: $choices.eveningWrapUp, id: "quickStart.evening")
                }
                if !current.weeklyTidyUp {
                    QuickStartRow(
                        title: "Weekly tidy-up",
                        detail: String(format: NSLocalizedString("%@ at %@. Notes saved twice and finished lists; nothing is deleted unless you tap it.", comment: ""),
                                       Calendar.current.weekdaySymbols[QuickStart.tidyUp.weekday - 1],
                                       Self.time(QuickStart.tidyUp.hour, QuickStart.tidyUp.minute)),
                        isOn: $choices.weeklyTidyUp, id: "quickStart.tidyUp")
                }
                if !current.weeklyLookBack {
                    QuickStartRow(
                        title: "Weekly look-back",
                        detail: String(format: NSLocalizedString("%@ at %@. Notes from the week, ticked items and what's coming up. No scores or streaks.", comment: ""),
                                       Calendar.current.weekdaySymbols[QuickStart.lookBack.weekday - 1],
                                       Self.time(QuickStart.lookBack.hour, QuickStart.lookBack.minute)),
                        isOn: $choices.weeklyLookBack, id: "quickStart.lookBack")
                }
                Text("iOS will ask whether Doddy may send notifications. They never show your notes.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }

            if profileSaved && !current.useProfileInVoice {
                QuickStartRow(
                    title: "Use what you told me in voice conversations",
                    detail: NSLocalizedString("Your saved answers are sent to ElevenLabs at the start of each conversation so I know them. Off, they stay on this iPhone.", comment: ""),
                    isOn: $choices.useProfileInVoice, id: "quickStart.profile")
            }

            Button {
                Task { await apply() }
            } label: {
                HStack {
                    if phase == .applying { Text("Setting up…") } else { Text("Turn these on") }
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(phase == .applying || plan.isEmpty)
            .accessibilityIdentifier("quickStart.apply")

            Button("Not now", action: done)
                .buttonStyle(SecondaryButtonStyle())
                .disabled(phase == .applying)
                .accessibilityIdentifier("quickStart.notNow")
        }
    }

    private func applied(_ receipts: [Receipt]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Here's what's set.")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(receipts) { receipt in
                    Label(receipt.text, systemImage: receipt.isProblem ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(receipt.isProblem ? Theme.error : Theme.ink)
                        .accessibilityIdentifier("quickStart.receipt.\(receipt.id)")
                }
            }
            Text("Change or turn off any of these in Settings.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Button(action: done) {
                HStack { Text("Continue to Doddy"); Spacer(); Image(systemName: "arrow.right") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("quickStart.continue")
        }
    }

    /// Applies one at a time, so iOS asks about notifications once, on the first.
    private func apply() async {
        let plan = self.plan
        phase = .applying
        var receipts: [Receipt] = []
        if let morning = plan.morning {
            morning.store()
            let outcome: QuickStart.Outcome = switch await MorningCheckInScheduler.apply(morning) {
            case .scheduled: .set
            case .needsPermission: .needsPermission
            case .off, .failed: .failed
            }
            receipts.append(receipt("morning", outcome, set: NSLocalizedString("Morning check-in set.", comment: "")))
        }
        if let evening = plan.evening {
            evening.store()
            let outcome: QuickStart.Outcome = switch await EveningWrapUpScheduler.apply(evening) {
            case .scheduled: .set
            case .needsPermission: .needsPermission
            case .off, .failed: .failed
            }
            receipts.append(receipt("evening", outcome, set: NSLocalizedString("Evening wrap-up set.", comment: "")))
        }
        if let tidyUp = plan.tidyUp {
            tidyUp.store()
            let outcome: QuickStart.Outcome = switch await TidyUpScheduler.apply(tidyUp) {
            case .scheduled: .set
            case .needsPermission: .needsPermission
            case .off, .failed: .failed
            }
            receipts.append(receipt("tidyUp", outcome, set: NSLocalizedString("Weekly tidy-up set.", comment: "")))
        }
        if let lookBack = plan.lookBack {
            lookBack.store()
            let outcome: QuickStart.Outcome = switch await WeeklyLookBackScheduler.apply(lookBack) {
            case .scheduled: .set
            case .needsPermission: .needsPermission
            case .off, .failed: .failed
            }
            receipts.append(receipt("lookBack", outcome, set: NSLocalizedString("Weekly look-back set.", comment: "")))
        }
        if plan.useProfileInVoice {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: PreferenceKey.shareProfileWithVoice)
            let outcome: QuickStart.Outcome = defaults.bool(forKey: PreferenceKey.shareProfileWithVoice) ? .set : .failed
            receipts.append(receipt("profile", outcome, set: NSLocalizedString("Your answers will be used in voice conversations.", comment: "")))
        }
        phase = .applied(receipts)
    }

    private func receipt(_ id: String, _ outcome: QuickStart.Outcome, set: String) -> Receipt {
        switch outcome {
        case .set:
            Receipt(id: id, text: set, isProblem: false)
        case .needsPermission:
            Receipt(id: id, text: NSLocalizedString("Notifications are off for Doddy, so this can't ring. Turn them on in iOS Settings.", comment: ""), isProblem: true)
        case .failed:
            Receipt(id: id, text: NSLocalizedString("This couldn't be set. Try again in Settings.", comment: ""), isProblem: true)
        }
    }

    /// The hour and minute in the iPhone's own clock style ("21:00" or "9:00 PM").
    private static func time(_ hour: Int, _ minute: Int) -> String {
        guard let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) else {
            return String(format: "%02d:%02d", hour, minute)
        }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// One tickable choice with a line saying exactly what it does.
private struct QuickStartRow: View {
    let title: LocalizedStringKey
    let detail: String
    @Binding var isOn: Bool
    let id: String

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityIdentifier(id)
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.separator, lineWidth: 1))
    }
}
