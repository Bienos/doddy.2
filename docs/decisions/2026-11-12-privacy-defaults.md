# Privacy defaults: what is on today, and a proposal to start with less leaving the phone

- **Date:** 2026-11-12
- **Decided by:** proposal, owner approval pending
- **Status:** proposed — waiting for the owner. **Nothing is implemented.** No default, screen or text is changed by this file.
- **Replaces:** nothing yet. If accepted, it would change parts of `2026-11-09-messages-on-by-default` and `2026-11-09-usage-counts-on-by-default`, which were the owner's own choices.

## Why
The owner is to rewrite the privacy policy (owner queue 7 and 26). Before that, it helps to have in one place what each switch does when nobody has touched it. The constitution's config sets `ephemeral_context_default: true` and `explicit_long_term_memory_opt_in_default: true` (`memory_policy`), and `legal_review_required_before_launch: true` (`privacy_policy`), in `docs/trust/config/doddy_rules.yaml` (DOD-06, DOD-11).

## What is on by default today (read from the code)
| What | Default | Where it is set | What leaves the iPhone when it is on |
|---|---|---|---|
| Ask Doddy in Messages | **On** (a missing value means on) | `PreferenceKey.assistantConsentDefault = true`, `DoddyApp/App/RootView.swift`; decision `2026-11-09-messages-on-by-default` | A typed question, when the person sends it, to Doddy's server and Anthropic |
| Ask Doddy uses relevant saved notes | **On** | `assistantUseNotes`, default `true` in `DoddyApp/Features/Privacy/DataFlowView.swift` | Matching notes with the question (never notes marked Private, ADR-310) |
| The copy of Messages on Doddy's server, for Doddy Web | **Always on, no switch**, whenever the iPhone has a backend session | `ThreadSync` (`Packages/DoddyCore/Sources/DoddyCore/Messages/ThreadSync.swift`, "sync always on", owner 28 Oct); `MessagesModel.syncToWeb`; `DoddyApp/Infrastructure/ServerThreadSync.swift` | The newest 200 messages as text after every change, encrypted at rest on the server, not end to end (`backend/src/messages/service.ts`); a photo is never sent, only that there was one |
| Logbook usage counts | **On** (absent means on) | `LogbookModel.onKey`, `Packages/DoddyCore/Sources/DoddyCore/Logbook/LogbookModel.swift`; decision `2026-11-09-usage-counts-on-by-default` | Counts only (tool ids, note types, language codes, numbers); the owner's panel shows each account's counts |
| Remember recent conversations | **On** | `ConversationLogStore.isEnabled` (`DoddyApp/Infrastructure/ConversationLogStore.swift`); `KnowledgeSettingsView` (`DoddyApp/Features/Settings/SettingsScreens.swift`) | Kept on the iPhone; the last few go to ElevenLabs at the start of the next voice conversation ("your last few conversations", `Packages/DoddyCore/Sources/DoddyCore/DataFlow.swift`) |
| Apple Health | **Off** | `HealthConnectionView.preferenceKey` (`sport.appleHealth.on`), `DoddyApp/Features/Health/HealthConnectionView.swift` | Only a week's summary, and only with a consent of its own each way: sent in Messages by the person (ADR-622), or to the voice after a yes (ADR-623); never the raw data |
| Voice recordings and transcripts at ElevenLabs | Kept for the period the privacy page states | `site/privacy/index.html`; each agent's `privacy` in `voice-agent/*/session.json` | The conversation itself (every voice conversation) |

Already off until the person turns them on: conversation recaps (`RecapPolicy`, both defaults `false`), notes and conversations kept on Doddy's server (`WebMemoryModel`), the notes copy for phone calls (`memoryCopyOn`), the profile and learned facts for the voice, notifications. Connections that need an iOS permission start off; maps, shortcuts, message drafts, BLIK and presentations start on, because each only prepares something the person still taps (`VoiceConnection.startsOn`, `Packages/DoddyCore/Sources/DoddyCore/VoiceTools.swift`).

## Proposal: privacy by default, item by item
1. **Ask Doddy:** stays usable from the first tap. The first send shows once what goes where (Doddy's server, Anthropic), with Send and Not now, instead of being on with no question asked. *Trade-off:* one extra tap, once.
2. **Saved notes in Ask Doddy:** off until turned on. *Trade-off:* answers know less about the person until they choose.
3. **Messages copy on the server:** off until the person signs in to Doddy Web, then on with a switch on both sides. Turning it on sends the newest 200 messages at once, so the web still shows history. *Trade-off:* someone who never uses the web never has a server copy, which is the point. Doddy Web shows nothing until the first sign-in there.
4. **Logbook:** off until turned on, or kept on with the owner's panel limited to totals across accounts (no per-account history). *Trade-off:* fewer or coarser numbers for the owner.
5. **Remembered conversations:** split the switch. Keeping them on the iPhone stays on; sending the last few to ElevenLabs is off until turned on. *Trade-off:* Doddy doesn't pick up where the last conversation stopped unless the person allows it.
6. **Health:** unchanged; it already starts off with two separate consents.
7. **ElevenLabs:** 30 days, as proposed in `2026-11-12-voice-conversations-per-account`.
8. **People who already have the app:** a saved choice always wins, as today. Changing a default only moves phones that never saved a choice, and those would switch off. Either their current behaviour is written down once at the upgrade (nothing changes for them), or they move to the new defaults and the app says so once.

## What the owner decides
1. For each of 1 to 7: yes, no, or a different shape. Items 1, 3 and 4 go back on the owner's own choices of 28 Oct and 9 Nov.
2. For people who already have the app: keep what they have (proposed) or move them to the new defaults with a notice.
3. When the privacy policy and App Store privacy answers are rewritten to match (owner queue 7 and 26). Whatever is chosen, they must describe the defaults as they ship.

## Consequences
- Fewer things leave the phone for someone who never opens Settings. "What leaves this iPhone" (`DataFlow`) lists fewer rows by default and stays the place that says what is on.
- Some features start quieter: Ask Doddy knows less, Doddy Web is empty until used, the owner sees fewer numbers.
- Each change is a small pull request of its own, with the UI tests that assume today's defaults updated (`DoddyUITests/LaunchSmokeTests.swift` was updated for the Ask Doddy default on 9 Nov).

## Evidence
- Read: `DoddyApp/App/RootView.swift` (`PreferenceKey`), `DoddyApp/Features/Privacy/DataFlowView.swift`, `Packages/DoddyCore/Sources/DoddyCore/DataFlow.swift`, `Packages/DoddyCore/Sources/DoddyCore/Messages/ThreadSync.swift`, `DoddyApp/Features/Messages/MessagesModel.swift`, `DoddyApp/Infrastructure/ServerThreadSync.swift`, `backend/src/messages/service.ts`, `Packages/DoddyCore/Sources/DoddyCore/Logbook/LogbookModel.swift`, `DoddyApp/Infrastructure/ConversationLogStore.swift`, `DoddyApp/Features/Settings/SettingsScreens.swift`, `DoddyApp/Features/Health/HealthConnectionView.swift`, `Packages/DoddyCore/Sources/DoddyCore/Recap/RecapPolicy.swift`, `Packages/DoddyCore/Sources/DoddyCore/VoiceTools.swift`, `site/privacy/index.html`, `docs/trust/config/doddy_rules.yaml`, and the two decisions named above.
- Not run: the app; nothing was checked on a device. The live agents' settings were not read.
