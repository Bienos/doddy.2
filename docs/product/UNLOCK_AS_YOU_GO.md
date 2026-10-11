# Unlock as you go — consent is asked when a request needs it, never up front
Date: 2026-10-11. Owner instruction (voice note, paraphrased): *"The user experience should be unlocking functions as we go. At the start he has voice and everything available. Connecting Gmail, sending a text, writing something: if that needs approval, only then prompt him. The first time he has to approve the consent for Doddy to use it. Don't ask at the start and don't have everything unlocked. As he goes, anything he asks for, if a consent is needed, ask then, only then, and keep the access if allowed."*

Decision log row: `DECISIONS.md` ADR-324. Status: **built on Linux, not compiled with Xcode, not run on an iPhone** (owner, 2026-10-11: "go build it, one card with two taps"). What was built and what is verified: `docs/implementation/UNLOCK_STATUS.md`. The "today" column below describes the code before this round.

## The principle in one paragraph
First launch asks for nothing: no account, no system permission, no switch. Talking to Doddy works at once (iOS itself asks for the microphone on the first talk; that is the only up-front system prompt and it is Apple's). When a request needs something Doddy is not yet allowed to use, Doddy asks **right there, in the conversation, for exactly that one thing**, with a card. If the user allows it, the access stays until they take it away in Settings, and the request they made continues without being asked again. If they decline, nothing changes, Doddy says one sentence, and the same request later asks again. Doddy never asks for a consent nobody's request needs.

## What this changes and what it keeps

| Area | Today | After ADR-324 |
|---|---|---|
| First launch | Introduction and Back Tap guide are optional; no permission or account is asked (`ONBOARDING_STATUS.md`, design doc "No account or permissions are required"). | **Kept.** |
| iPhone connections (Calendar, Reminders, Contacts, Messages, Timers, Maps, Shortcuts; ADR-063) | All off under Settings › Connections. In a voice session an off connection shows a card "*X is off. Turn it on to let Doddy use X. Then ask again.*" (`VoiceView.connectionCard`). Turning on asks iOS for its permission. | The card becomes the consent: "*Let Doddy use Reminders?*" with what it is for. **Allow** turns the switch on and lets iOS ask. **The original request then continues on its own**; "Then ask again" goes away. |
| Online accounts (Gmail, Drive, Notion, Todoist; ADR-097) | Per-tool switch, off by default, enforced on the server. When a tool is off or the account is not connected, the server answers `tool_off` / `not_connected` / `connection_expired` / `permission_insufficient`, and the agent is told to say "*you can switch it on or connect it in Settings, Online accounts*" (`voice-agent/instructions.md`, `VoiceCloudTools.swift`). The conversation dead-ends; the user leaves for Settings, connects, flips a switch, comes back and asks again. | A consent card in the conversation, built from the server's typed code, never from the agent's words. Not connected: "*Connect Gmail?*" runs the existing connect flow (`SystemWebAuthenticator` → server verification, ADR-097/100) from the voice screen. Connected but the tool is off: "*Let Doddy read your email?*" names the one tool the request needs and sets that one server switch. Both needed: one card, two steps in order, each its own tap. Connecting still never switches tools on by itself (ADR-097 kept): the switch is a separate, named consent. |
| Writes (send, add, create, change) | Exact-payload, single-use approval card bound to the arguments (ADR-097 server side; `tool_switches` + `approvals`). | **Kept unchanged.** Consent to a capability and approval of one action are two different taps and stay so. After a consent card the write's approval card follows, as today. |
| Permission the user already refused in iOS | Connections screen explains and offers Open Settings. | Same, as a card in the conversation: the app cannot re-prompt iOS, so the card says that and offers **Open Settings**. No wording that implies Doddy can grant it. |
| Settings › Connections and Settings › Online accounts | The only way in. | Stay as the full inventory and the **revoke** path (ADR-097 behaviour on expiry and disconnect unchanged). They stop being the required entry point. |
| Features the user turns on in Settings (Hey Doddy, morning check-in, birthdays, note reminders…) | Each asks for notifications or location when it is turned on. | **Kept.** That is already "when needed". |
| Hidden or model-driven unlocking | None. | **Still none.** The model cannot switch anything on, connect anything or claim a consent was given. A card tap is the only way (constitution: `minimum_needed_permissions`, DOD-07 scoped approval, `disallow_model_only_approval`). |

## Rules (the ones code must enforce)
1. **Only on a request.** A consent card appears only while handling something the user asked for, and only for what that request needs. No consent prompts on launch, on Home, after an update, or because a feature "might be useful".
2. **Smallest thing.** One account, or one tool, or one iPhone connection per step. Never "all Gmail tools" because the user asked to read one email.
3. **From a typed code, not from text.** The card is raised by the app from the server's error code or the device's authorization state. The agent's reply never decides whether a card shows and never says access was given; it says one sentence and waits.
4. **Then it continues.** After **Allow**, the pending tool call is run again with the same arguments. If that call is a write, the normal approval card follows. If the user left the app for the system browser (account connect), the request resumes when they come back; if the voice session ended meanwhile, Doddy says what was connected and does not resume the old request on its own.
5. **Allowed stays allowed.** The grant is the same switch or connection Settings would set, so it persists exactly as today and is revoked in the same place. Expiry and disconnect follow ADR-097; after a reconnect the next request asks for the tool switch again, which is what rule 2 predicts.
6. **Not now is quiet.** Declining changes nothing, is not recorded as a preference, and is not followed by "are you sure". The same request later asks again, because asking is the only way the function unlocks.
7. **Honest about iOS.** If iOS denied a permission earlier, the card says Doddy cannot ask again and offers Open Settings. No "verified" or "set up" claim the app cannot check.

## Build plan (built 2026-10-11; see UNLOCK_STATUS.md for what is verified)
- `DoddyApp/Features/Voice/VoiceSessionController.swift`: new pending-card case for consent (`connection`, `account`, `tool`), raised from the device `Access.notDetermined/.denied` path and from `VoiceCloudTools` failure codes; holds the original tool call and re-runs it after Allow.
- `DoddyApp/Features/Voice/VoiceView.swift`: `connectionCard` reworded and extended; account connect reuses `OnlineAccountsModel.connect`, tool switch reuses its switch call; Open Settings for an iOS denial.
- `Packages/DoddyCore/.../VoiceCloudTools.swift`: failure strings stop telling the user to go to Settings; they say a card is shown.
- `voice-agent/instructions.md` lines 82 and 124: "say they can switch it on in Settings" → "a card is shown; say one short sentence and wait for the tap".
- Server: no new endpoint expected; connect, switch and run already exist (`backend/src/tools/service.ts`). If the per-tool switch endpoint needs a "reason" for the receipt, add it to `tool_receipts`, nothing else.
- Tests: card raised for each code and never from agent text; Allow re-runs the same arguments once; decline leaves switches untouched; a write after consent still needs its approval; denial state shows Open Settings; no card without a request (Home, launch).
- Docs: `ONBOARDING_STATUS.md` and `docs/trust/03_TRUST_FEATURES_AND_UX.md` UX-03 get a pointer here; `DECISIONS.md` row moves from "decided, not built" when the Mac build and a real iPhone run are reported.

## Owner decisions
- **Decided (2026-10-11): one card, two taps** when the account isn't connected and the tool is off. The card lists both steps; each is its own button, in order, and the second appears only after the first is verified.
- Card wording per tool: the card uses the server's own blurb for the tool (the same text as Settings, Online accounts) and, when a connect step is shown, the account's access text. No agent words.

## Not claimed
Built and tested on Linux only (the DoddyCore part). The iOS app is not compiled, nothing ran on an iPhone, and the live ElevenLabs agent prompt is not updated. Details: `docs/implementation/UNLOCK_STATUS.md`.
