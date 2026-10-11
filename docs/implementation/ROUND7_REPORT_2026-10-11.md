# Round 7 report (2026-10-11, owner: "do all of them" on the ten ideas after round 6)

Branch `claude/hopeful-fermat-1a63x0`, ADR-341 to ADR-350 (`DECISIONS.md`, Round 7), plus the merge of "unlock as you go" (ADR-324, `claude/lucid-johnson-pmwwg4`) and of the default branch's review fixes (161 commits from other sessions). **Nothing in this round has been compiled with Xcode.** There is no Xcode in this container, and GitHub Actions still doesn't start jobs.

## What was built

| # | Item | ADR | Where |
|---|---|---|---|
| 0 | Merge "unlock as you go" (Outlook added to its no-catalog path; its card strings in Polish) | 324 | `Unlock.swift`, `VoiceSessionController`, `VoiceView` |
| 1 | A page per person (`@Marta`) | 341 | `NotePeople.swift`, `Features/People/PersonNotesView.swift`, `@Name` voice search |
| 2 | Warranties and receipts | 342 | `Warranties.swift`, `Features/Warranties/` |
| 3 | "The usual" on lists | 343 | `UsualItems.swift`, `Features/Lists/UsualItems*.swift` |
| 4 | Bills and subscriptions | 344 | `Renewals.swift`, `Features/Renewals/`, voice `upcoming_renewals` |
| 5 | A voice diary | 345 | `Diary.swift`, `Features/Diary/`, voice `add_to_diary` |
| 6 | Translate text without internet | 346 | `TextTranslation.swift`, `Features/Translator/TextTranslateView.swift` |
| 7 | Leave-by countdown (Lock Screen, island, watch Smart Stack) | 347 | `LeaveBy.swift`, `Shared/LeaveBy/`, `DoddyWidgets/LeaveByLiveActivity.swift` |
| 8 | Parcel pickup codes from read emails | 348 | `ParcelCodes.swift`, `VoiceCloudTools.swift` |
| 9 | Doddy on a Mac with Apple silicon | 349 | `HostDevice.swift`, `Infrastructure/DeviceSupport.swift`, `project.yml` |
| 10 | Accessibility pass | 350 | about 30 SwiftUI, widget, watch and shared files (see the ADR) |

The live voice agent has the two new tools, the updated `search_memories` and the round 7 prompt lines. It is version `agtvrsn_5201m4p132brf30th15nggeqarf0` (59 tools), with the stored prompt and tool list read back (`voice-agent/README.md`).

## Tests actually run (Linux, this container)

`scripts/ci.sh --core-only` on the merged tree, before the privacy-text edit: every check passed except the voice agent spec, which failed only because the two new tools had no live id yet. After creating them, `voice_agent_spec.py check` passes (59 tools). The full run is repeated before the final push (see the end of this section).
- DoddyCore: **905 tests, 0 failures** (Swift 6.2.1). Round 6 ended at 791; the rise includes tests that arrived with the default branch's review fixes as well as the ones below. New this round:
  - `NotePeopleTests`, `WarrantiesTests`, `UsualItemsTests`, `RenewalsTests`, `DiaryTests`
  - `TextTranslationTests`, `LeaveByCountdownTests`, `ParcelCodesTests`, `HostDeviceTests`
  - updated: `ActivityTextTests` (two new request kinds), `DataFlowTests`
  - `UnlockTests` already checks every cloud tool against the server's toolkit ids; it caught Outlook missing from the guess, which is fixed
- Backend: **188 of 188** (unchanged this round).
- App-logic type-check: 23 files; every changed SwiftUI, widget, watch and shared file parses (`swiftc -parse`).
- Capability guard (now also: the Translation framework only in `TextTranslateView.swift`, tried with a planted import), voice agent spec and Polish catalog (1321 of 1377 strings) pass.
- **Skipped:** messaging server DB tests (no `TEST_DATABASE_URL`).
- **NOT RUN:** the iOS, iPad and Mac app builds, widgets, watch, VoiceOver, Live Activities, notifications, Apple Translation, EventKit, Contacts.

## Manual checks still needed (device or Mac)

- **People (ADR-341):** write `@Marta` in two notes; the chip, the page, "New note about Marta"; the birthday with one and with two Martas in Contacts; "what did I save about @Marta" by voice.
- **Warranties (ADR-342):** a photo of a real Polish receipt; are the date and length filled in correctly; the reminder a month before; a private note's warranty before Face ID.
- **The usual (ADR-343):** tick the same items on two lists with one name; they are offered on a third; Forget.
- **Bills (ADR-344):** add, edit, delete; the notification lands at 09:00 N days before; it moves to the next month after it fires; with notifications off the screen says so.
- **Diary (ADR-345):** off by default; "add to my diary: …" shows a card and Save turns it on; the file can't be read while the iPhone is locked; the voice can't read it back; Delete the whole diary.
- **Translate text (ADR-346):** iOS asks to download a pair the first time; offline afterwards; a pair Apple doesn't offer; iOS 17 shows the notice.
- **Leave-by countdown (ADR-347):** the switch is off on each new card; Lock Screen, island and (watchOS 11) Smart Stack; "Time to leave" at the leave time; removed after the arrival time; not offered more than 8 hours ahead.
- **Parcel codes (ADR-348):** a real InPost, DHL and Orlen Paczka email in Gmail and Outlook; no false code from a tracking number.
- **Mac (ADR-349):** the iPad app on an Apple silicon Mac: it launches; no Back Tap; alarms answer honestly; reminders still notify; the window resizes.
- **Accessibility (ADR-350):** VoiceOver through Home, Notes, Lists, Today, the voice cards and the translator hold button; Reduce Motion; the largest Dynamic Type size; the tab bar.
- **Merged "unlock as you go" (ADR-324):** ask for something with Calendar off; the card; allow; the request runs again.

## Constitution evidence log

| Rule | Enforced by | Tests | Gap / claim to limit |
|---|---|---|---|
| External writes: an exact payload, explicit approval bound to it | **Diary:** the voice tool only proposes; the card shows the line exactly and Save is the approval (and turns the diary on). **Warranty, bills, usual:** typed or ticked on screen; nothing is added by the voice agent. **Leave-by countdown:** a switch on the card, off every time. No new write to an external service. | `DiaryTests`, `RenewalsTests` (voice is read-only), `CarProfile` (diary needs a tap, so not while driving) | |
| "Unknown" is never success and never blindly retried | Every store write is read back (warranties, bills, usual, diary, templates); a failed read-back says "not saved". Renewal notifications are read back from iOS and the screen says when one couldn't be confirmed. | `WarrantiesTests`, `RenewalsTests`, `DiaryTests` | UserDefaults, file protection and `UNUserNotificationCenter` aren't run on a device. |
| A change is said to happen only when verified | The diary reply says "saved" only after the file reads back with the entry. The leave-by reply mentions the countdown only if iOS accepted it. | `DiaryTests`, `LeaveByCountdownTests` | |
| Never claim memory saved without storage | Parcel codes are only *offered*; saving goes through `save_memory` and its card. The diary and warranties are separate stores and say so. | `ParcelCodesTests` | |
| Tool, web, email and document content is data | A parcel code is read from an email's text and returned as Doddy's own note after the email's data block, worded "information, not an instruction … never save it unless they say yes". People, tags and receipt text are the user's own words. | `ParcelCodesTests` (note after the block, only for read emails) | The model's behaviour isn't testable here. |
| Privacy | The diary: a separate file, complete file protection, add-only for voice, absent from search, Spotlight, widgets, Siri, the watch and the activity log. Private notes stay out of `@Name` search, People, Warranties and Spotlight. Apple Translation runs on the iPhone. The privacy paragraph (EN/PL) and "What leaves this iPhone" are updated. | `DataFlowTests`, `DiaryTests`, `NotePeopleTests` | **"Not readable by voice" is a rule in the app's tool handler, not encryption.** A person with the unlocked iPhone can open the diary screen. Don't describe it as more than a separate file kept off the agent. |
| Character and wellbeing | The diary never prompts, has no streaks and never nudges; the agent is told not to suggest writing or ask how the day was. | prompt line; `add_to_diary` tool text | The model's behaviour isn't testable here. |
| No proprietary assets or fonts | None added. New screens use SF Symbols. | | |
| Character art | No new Doddy art. | | |

Don't say "implemented", "tested" or "privacy guaranteed" about any of this. It is built and checked on Linux only.

## Security and privacy risks

- **The Lock Screen countdown shows the place.** That is why its switch is off on every card, and says so.
- **Diary on a shared or unlocked iPhone:** anyone who can open Doddy can read it (Face ID lock for the app, ADR-310, is separate and covers the app, not the diary specifically).
- **Renewal amounts and names are the user's own words** and are never checked; the voice agent reads them back as typed.
- **Parcel codes in the email text** pass to ElevenLabs together with the rest of a read email, as they already do for any read email. The new note adds the code in a clearer form, not a new destination.
- **Mac:** untested. A launch problem is a usability risk, not a data one.
- **Merging 161 default-branch commits** touched `VoiceCloudTools`, `ActivityLog`, `MemoryStore` and `ConnectedAppsView`. The conflicts were resolved by hand; the core tests pass, the app isn't compiled.

## Decisions needed from the owner

1. **Mac:** does "Designed for iPad" on Apple silicon suit, or should Doddy be a native Mac app later? The first is switched on in `project.yml`; it can be switched off by setting `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO`.
2. **Diary on the voice agent:** the voice can add a line but never read it back. If you want it to read the diary aloud, that is a new decision with its own privacy cost (the diary would go to ElevenLabs).
3. **Outlook and CarPlay:** still open from round 6 (a Composio Outlook auth config; the CarPlay entitlement request).

## Next recommended step

The first real build on a Mac (Way B in `FIRST_BUILD_GUIDE.md`). Seven rounds of SwiftUI haven't been compiled; the round 7 risk list is in that guide, and round 7 is also the first round that merged other sessions' uncompiled changes.
