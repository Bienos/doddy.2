import DoddyCore
import SwiftUI

// Settings › Phone calls › Doddy calls you › Morning call (owner, 15 Nov 2026: "make button in app to switch calling",
// then "Morning call switch"). Turning the switch on opens this sheet: the time (05:00 to 11:59 on this iPhone's clock)
// and the days, then the voice card's own view (`MorningCallCard`) with its button. Only that button books it, with
// the approval of exactly what the card shows, through the voice card's call (DOD-07); the switch and the pickers book
// nothing. The logic is in DoddyCore `MorningCallSwitch.swift`, tested on Linux. Decision 2026-11-14-morning-call.
// Not compiled in the session that wrote it; NOT RUN on a device.

/// What the sheet gets back when it asks the server before showing the card.
enum MorningCallPreparation {
    case ready(MorningCallProposal)
    /// Why the card can't be shown, in the app's language.
    case notReady(String)
}

struct MorningCallSetupSheet: View {
    let model: CallsModel
    @Environment(\.dismiss) private var dismiss
    @State private var time: Date
    @State private var days: MorningCallDayChoice
    /// The card, once Doddy's server has said which number it calls, the quiet hours and the call it replaces.
    @State private var proposal: MorningCallProposal?
    /// The card's "Call even in quiet hours": part of the approval, off for every new card.
    @State private var allowQuietHours = false
    @State private var problem: String?

    /// `active`: the morning call set up now, whose time and days the pickers start from.
    init(model: CallsModel, active: MorningCall?) {
        self.model = model
        _time = State(initialValue: MorningCallTime.start(active?.time, on: Date(), calendar: .current))
        _days = State(initialValue: active?.dayList.map { MorningCallDayChoice($0) } ?? MorningCallDayChoice(kind: .everyDay))
    }

    /// What the pickers say now; nil while no day is ticked.
    private var draft: MorningCallDraft? { MorningCallDraft(pickedTime: time, days: days, calendar: .current) }

    var body: some View {
        NavigationStack {
            Form {
                if let proposal {
                    card(proposal)
                } else {
                    pickers
                }
                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                            .accessibilityIdentifier("calls.morning.problem")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Morning call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .disabled(model.isWorking)
            .overlay { if model.isWorking { ProgressView() } }
        }
    }

    // MARK: Time and days

    @ViewBuilder
    private var pickers: some View {
        Section {
            DatePicker("Time", selection: $time, in: MorningCallTime.range(on: time, calendar: .current), displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("calls.morning.time")
            Picker("Days", selection: $days.kind) {
                Text("Every day").tag(MorningCallDayChoice.Kind.everyDay)
                Text("Weekdays").tag(MorningCallDayChoice.Kind.weekdays)
                Text("Weekend").tag(MorningCallDayChoice.Kind.weekend)
                Text("Chosen days").tag(MorningCallDayChoice.Kind.chosen)
            }
            .accessibilityIdentifier("calls.morning.days")
            if days.kind == .chosen {
                ForEach(1...7, id: \.self) { day in
                    Toggle(Self.dayName(day), isOn: Binding(get: { days.chosen.contains(day) }, set: { days.set(day, $0) }))
                        .accessibilityIdentifier("calls.morning.day.\(day)")
                }
            }
        } header: {
            Text("When Doddy calls")
        } footer: {
            Text(String(format: NSLocalizedString("Between 05:00 and 11:59 on this iPhone's clock (%@).", comment: "Morning call: the time picker's limits"),
                        TimeZone.current.identifier))
        }
        Section {
            Button("Next") { Task { await next() } }
                .disabled(draft == nil)
                .accessibilityIdentifier("calls.morning.next")
        } footer: {
            if draft == nil {
                Text("Tick at least one day.")
            } else {
                Text("Next shows a card with exactly what Doddy will do. Nothing is set up until you tap its button.")
            }
        }
    }

    /// Asks the server for the number, quiet hours and the call this replaces, as the voice card does, then shows the card.
    private func next() async {
        guard let draft else { return }
        problem = nil
        switch await model.prepareMorningCall(draft) {
        case .ready(let ready):
            allowQuietHours = false
            proposal = ready
        case .notReady(let text):
            problem = text
        }
    }

    // MARK: The card

    @ViewBuilder
    private func card(_ proposal: MorningCallProposal) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                MorningCallCard(
                    draft: proposal.draft, to: proposal.to, quietHours: proposal.quietHours, replaces: proposal.replaces,
                    allowQuietHours: $allowQuietHours, earlierTryUnconfirmed: CallsModel.isUnconfirmed(proposal))
            }
            .padding(.vertical, 4)
        }
        Section {
            Button("Call me every morning") {
                Task {
                    await model.bookMorningCall(proposal, allowQuietHours: allowQuietHours)
                    dismiss()
                }
            }
            .disabled(!proposal.canBook(allowQuietHours: allowQuietHours))
            .accessibilityIdentifier("calls.morning.confirm")
            Button("Change time or days") {
                self.proposal = nil
                problem = nil
            }
            .accessibilityIdentifier("calls.morning.back")
            Button("Not now", role: .cancel) { dismiss() }
        } footer: {
            Text("Only this button sets it up, with exactly what the card shows. Afterwards the switch shows what Doddy's server says.")
        }
    }

    /// Literal keys, so the strings catalog finds them.
    private static func dayName(_ day: Int) -> String {
        switch day {
        case 1: NSLocalizedString("Monday", comment: "Morning call: a day it may ring")
        case 2: NSLocalizedString("Tuesday", comment: "Morning call: a day it may ring")
        case 3: NSLocalizedString("Wednesday", comment: "Morning call: a day it may ring")
        case 4: NSLocalizedString("Thursday", comment: "Morning call: a day it may ring")
        case 5: NSLocalizedString("Friday", comment: "Morning call: a day it may ring")
        case 6: NSLocalizedString("Saturday", comment: "Morning call: a day it may ring")
        default: NSLocalizedString("Sunday", comment: "Morning call: a day it may ring")
        }
    }
}

extension MorningCallBlocker {
    /// Why the switch can't be turned on, in the app's language; literal keys, so the strings catalog finds them.
    var localized: String {
        switch self {
        case .serverOff: NSLocalizedString("Morning calls are off on Doddy's server right now.", comment: "")
        case .lineNotSetUp: NSLocalizedString("Doddy's phone line isn't set up on the server yet.", comment: "")
        case .noVerifiedPhone: NSLocalizedString("Doddy only calls a number you have verified.", comment: "")
        case .callsOff: NSLocalizedString("Turn on \"Doddy may call me\" first.", comment: "")
        }
    }
}

extension MorningCallRefusal {
    /// What to do next after the server refused a morning call, in the app's language (every error has recovery copy).
    var localized: String {
        switch self {
        case .quietHours:
            NSLocalizedString("That time is inside quiet hours. Pick a later time, or turn on “Call even in quiet hours” on the card.", comment: "")
        case .numberChanged:
            NSLocalizedString("Your number changed after the card was shown. Turn the switch on again for a new card.", comment: "")
        case .anotherSetUp:
            NSLocalizedString("Another morning call was set up in the meantime; it's shown here. Change its time or days to replace it.", comment: "")
        case .alreadySetUp: NSLocalizedString("That morning call is already set up, so nothing changed.", comment: "Morning call")
        case .stoppedSince:
            NSLocalizedString("This morning call was stopped after an earlier try. Turn the switch on again to set it up.", comment: "")
        case .serverFull:
            NSLocalizedString("Doddy's server already makes as many morning calls as it may. Try again later, or ask Doddy to call you once at a set time.", comment: "")
        case .serverOff: NSLocalizedString("Morning calls are off on Doddy's server right now.", comment: "")
        case .callsOff: NSLocalizedString("Turn on \"Doddy may call me\" first.", comment: "")
        case .noVerifiedPhone: NSLocalizedString("Verify your phone number first, in Settings → Notifications and texts.", comment: "")
        case .countryNotAllowed: NSLocalizedString("Doddy doesn't text or call numbers in that country.", comment: "")
        case .lineNotSetUp: NSLocalizedString("Doddy's phone line isn't set up on the server yet.", comment: "")
        case .tooManyTries: NSLocalizedString("That's the limit for now. Try again later.", comment: "")
        case .notAccepted:
            NSLocalizedString("Doddy's server didn't accept that time or those days. Turn the switch on again and choose them again.", comment: "")
        case .other: NSLocalizedString("Doddy's server turned it down. Try again in a few minutes.", comment: "Morning call")
        }
    }
}
