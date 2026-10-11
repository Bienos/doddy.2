# Quick start (ADR-310): status

Owner request, 11 October 2026: "tak, zrób ekran Szybki start z tymi godzinami". It followed
Claude's list of which settings make Doddy easy to use and which have to stay off until the user
says yes.

## What changed
- **New last step of first use** (`DoddyApp/Features/Onboarding/QuickStartView.swift`): after the
  introduction is saved or skipped, and before Home. It is shown once per install
  (`PreferenceKey.quickStartOffered`, set on **Not now** and on **Continue to Doddy**). Reopening the
  introduction from Settings later skips it.
- **What it offers:**
  | Item | Suggested | Pre-ticked | Why |
  |---|---|---|---|
  | Morning check-in | 08:00, weekdays only | yes | local notification, shows no note; iOS asks first |
  | Evening wrap-up | 21:00 every day | only with Reminders connected | same; without Reminders its screen has nothing to show (owner, 2026-10-11) |
  | Weekly tidy-up | Sunday 18:00 | yes | same; nothing is deleted unless tapped |
  | Use "About you" answers in voice conversations | — | **no** | sends the answers to ElevenLabs; only offered when answers are saved |
- **Rules** (`Packages/DoddyCore/Sources/DoddyCore/QuickStart.swift`, `QuickStart.plan`):
  - nothing changes until **Turn these on**;
  - an unticked item is left as it is, never turned off;
  - an item already on is neither offered nor changed, so a time picked in Settings is kept.
- **Applying:** each setting is stored, then applied through the existing
  `MorningCheckInScheduler`, `EveningWrapUpScheduler` and `TidyUpScheduler`, one after the other, so
  iOS asks about notifications only once. The result screen reports only what was read back from
  iOS's pending notifications, or from UserDefaults for the profile switch. If notifications are off,
  it says so and doesn't claim anything is set.
- **Unchanged:** the defaults in Settings. Anyone who taps **Not now** has exactly the settings they
  had before this change.
- **Polish:** 18 new lines in `l10n/pl.json`; catalog rebuilt.

## Tests
- `Packages/DoddyCore/Tests/DoddyCoreTests/QuickStartTests.swift` (8) covers what is pre-ticked (the
  wrap-up only with Reminders connected), the
  owner's times, that unticked and already-on items are left alone, that the profile is shared only
  when ticked and saved, and that the stored settings read back unchanged.
- `DoddyUITests/LaunchSmokeTests.swift`: the first-use tests now pass through the Quick start. With
  nothing saved, the profile row is absent. After saving answers, the profile row is shown and unticked.
  NOT RUN (no Xcode).

## Privacy and constitution evidence
- Explicit opt-in for data leaving the phone (memory/privacy policy): the profile switch is never
  pre-ticked and is gated in code on saved answers (`plan`, test `testProfileIsSharedOnlyWhenTickedAndSaved`).
- No claim without read-back: the receipts come from scheduler outcomes. `.off` and `.failed` are
  both shown as "couldn't be set".
- Minimum permissions: the notification permission is asked by iOS only after the user taps
  **Turn these on** with a notification ticked.
- Gaps: none of this has been compiled for iOS or run on a device. The wording of the screen has not
  been reviewed by the owner.

## Decisions for the owner
- ~~Evening wrap-up pre-ticked without Reminders~~: decided 2026-10-11, pre-ticked only when Reminders
  is on in Connections and iOS allows it (same check as the wrap-up screen). Still offered, unticked,
  otherwise.
- Should the screen also offer "Hey Doddy" or Back Tap? Not included: Hey Doddy keeps the microphone
  listening, and Back Tap can only be set up in iOS Settings.
