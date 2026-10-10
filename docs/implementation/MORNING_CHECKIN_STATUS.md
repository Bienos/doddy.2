# Morning check-in status (ADR-220)
Date: 2026-10-10. Owner: "do all of them" (item 5 of the proposed list).

## What ships
- **Off by default.** Settings › Morning check-in:
  - switch, time (08:00 by default) and "Weekdays only";
  - a receipt read back from iOS ("Set for 07:30 every day.");
  - "Open the check-in now".
- **The notification** repeats at that time: one request, or five (Monday to Friday). It says only "Good morning · A quick look at your day?" ("Dzień dobry · Szybki rzut oka na Twój dzień?" on a Polish iPhone), never a note. If iOS notifications are off, Settings says so and nothing is scheduled. The words are refreshed on each launch, so they follow the iPhone's language.
- **A tap opens the check-in screen.** It doesn't open while a conversation or a shared draft is up. The screen is built on this iPhone and shows:
  - today's Doddy time reminders still ahead, in time order, at most 6;
  - lists with things left, most first, at most 5;
  - the existing Today card (Calendar and Reminders, only when they are connected).
- **Talk it through with Doddy.** The sheet closes, then a conversation opens with `{{morning_checkin}}`: the same reminders and list names, as text. After Doddy's greeting the app sends "(app) Morning check-in: give the briefing now". The prompt asks for:
  - a few sentences from the check-in only;
  - `read_calendar` for today if the calendar is connected (the usual tool and switch);
  - then "what first?".
- **Not now** closes the screen; nothing was sent.
- **Privacy text.** "What leaves this iPhone" adds "today's Doddy reminders and lists with things left, when you talk through the morning check-in" while the check-in is on.

## Files
- Core:
  - `MorningCheckIn.swift`: `MorningCheckInSettings`, `MorningCheckIn` (requests, ids, words), `MorningBriefing`, `MorningCheckInPrompt`;
  - `DataFlow.swift` (`morningCheckInOn`).
- App:
  - `Features/MorningCheckIn/MorningCheckInScheduler.swift` and `MorningCheckInViews.swift`;
  - `ShortcutRouter`: check-in sheet, then the conversation;
  - `NoteReminderNotifications.swift`: the tap is routed;
  - `VoiceSessionController`: `checkIn:` and the variable;
  - `VoiceView`, `RootView`, `DoddyApp` (re-apply on launch), `SettingsView`, `DataFlowView`.
- Agent spec: a `voice-agent/instructions.md` section "Morning check-in" and the `morning_checkin` variable in `session.json`.
- Tests: `MorningCheckInTests` (4).

## Verified (Linux, Swift 6.2.1)
- DoddyCore: 444 tests pass, including `MorningCheckInTests`. They cover:
  - off by default and nothing scheduled;
  - daily versus five weekday requests and clamped values;
  - notification words;
  - briefing order and filtering;
  - prompt text;
  - the privacy line only when on.
- App logic type-check passes (ShortcutRouter).
- `swiftc -parse` on the new and changed UI and notification files.
- `voice_agent_spec.py check` passes.

## NOT RUN / UNVERIFIED
- No Xcode build. Never rang on a device:
  - repeating calendar triggers;
  - a tap from a cold start opening the sheet;
  - the sheet-then-cover order.
- **Live agent updated** (`agtvrsn_0401m4kzqvpkfjb8bqsvnsg2j3nh`, see `voice-agent/README.md`), but no conversation has been run against it, so the spoken briefing is untested.
- Whether the "(app)" message comes back as a transcript line in the conversation log is not checked. The translator start uses the same path.

## Constitution evidence log (docs/trust/config/doddy_rules.yaml)
| Rule | What enforces it here | Tests run | Gaps / claims to limit |
|---|---|---|---|
| DOD-11 observable_privacy | Notification carries no personal text; screen built on device; nothing sent before "Talk it through"; privacy screen line while on | `testTheNotificationSaysNothingPersonal`, `testWhatLeavesThisIPhoneSaysSoOnlyWhenOn` | ElevenLabs keeps the conversation as with any conversation |
| DOD-08 verified_status_and_receipts | Settings shows "Set for …" only after the requests are read back from iOS's pending list | — | Scheduler not compiled |
| DOD-10 nonmanipulative_companionship | Off by default; one neutral line; "Not now"; no streaks or nagging | — | — |
| DOD-02 honesty_over_agreeableness | Prompt: only what the check-in or a tool returned | `testBriefingHasTodaysRemindersAndOpenListsOnly` | Prompt-only for the spoken briefing |

Don't claim: "Doddy plans your day", "knows your calendar" (only with Calendar on, via the tool), or that the check-in rang on a device.
