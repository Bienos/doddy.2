import DoddyCore
import SwiftUI

/// "Call you every morning?" (decision 2026-11-14-morning-call): the exact schedule in the iPhone's zone, the number's
/// last digits, how the call opens and what it covers (only what Doddy's server holds; the calendar stays on the
/// iPhone), who hears it, the quiet-hours switch the approval covers, the morning call it replaces, and how to stop.
/// The card's own button or the person's spoken yes approves exactly this; nothing is set up before that.
/// The voice card and Settings › Phone calls › Doddy calls you › Morning call (owner, 15 Nov 2026) show this same view;
/// each passes its own quiet-hours switch and whether an earlier try of this schedule was left unconfirmed.
struct MorningCallCard: View {
    let draft: MorningCallDraft
    let to: String
    let quietHours: CallQuietHours
    let replaces: MorningCall?
    /// "Call even in quiet hours": part of the approval.
    @Binding var allowQuietHours: Bool
    /// An earlier try of this schedule had an unclear outcome, so it may already be set up.
    let earlierTryUnconfirmed: Bool

    var body: some View {
        let language = NotificationLanguage.current
        Text("Call you every morning?")
            .font(.headline)
        Text(verbatim: draft.scheduleText(language))
            .font(.body)
            .accessibilityIdentifier("voice.morningCall.schedule")
        Text(String(format: NSLocalizedString("Time in %@. From Doddy's number to your number ending %@", comment: "Morning call card"),
                    draft.timeZoneID, String(to.suffix(3))))
            .foregroundStyle(Theme.secondaryText)
        if let replaces, let days = replaces.dayList {
            Label(String(format: NSLocalizedString("This replaces your morning call %@.", comment: "Morning call card"),
                         MorningCallDraft(time: replaces.time, days: days, timeZoneID: replaces.timeZone).scheduleText(language)),
                  systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote)
        }
        Text("When you answer, Doddy says first:")
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: MorningCallDraft.opening(language))
                .font(.body)
            Text(verbatim: MorningCallDraft.covers(language))
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.separator, lineWidth: 1))
        .accessibilityIdentifier("voice.morningCall.opening")
        Label("Anyone who answers your phone hears this, and so does your voicemail.", systemImage: "speaker.wave.2")
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
        Toggle(isOn: $allowQuietHours) {
            Text(String(format: NSLocalizedString("Call even in quiet hours (%@–%@)", comment: ""), quietHours.start, quietHours.end))
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("voice.morningCall.quietHours")
        if draft.inQuietHours(quietHours) && !allowQuietHours {
            Label("This time is in quiet hours. Turn on the switch to set it up anyway, or ask Doddy for a later time.", systemImage: "moon")
                .font(.footnote)
        }
        if earlierTryUnconfirmed {
            Label("Doddy couldn't confirm an earlier try of these morning calls. They may already be set up: Doddy's server never sets up the same schedule twice.",
                  systemImage: "exclamationmark.triangle")
                .font(.footnote)
        }
        Text("Each day is checked again before it rings: your number, calls from Doddy on, quiet hours where your iPhone is, and the limit on calls. Twilio places the call. Say “stop the morning calls”, or tap Stop in Settings, Phone calls.")
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
    }
}

extension MorningCallCard {
    /// The voice card (`VoiceView`): the switch is the conversation's `callLaterAllowQuiet`, and an unclear earlier try is
    /// one the conversation recorded. The same as before the card took a binding.
    init(draft: MorningCallDraft, to: String, quietHours: CallQuietHours, replaces: MorningCall?, controller: VoiceSessionController) {
        self.init(
            draft: draft, to: to, quietHours: quietHours, replaces: replaces,
            allowQuietHours: Binding(get: { controller.callLaterAllowQuiet }, set: { controller.callLaterAllowQuiet = $0 }),
            earlierTryUnconfirmed: VoiceSessionController.unconfirmedCalls.contains(draft.identity(to: to, language: .current)))
    }
}
