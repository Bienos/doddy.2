# "Doddy, call me" rings the user's own phone now, after one tap on a card

- **Date:** 2026-11-10
- **Decided by:** owner. On 9 Nov 2026: "A call me now, can I ask Doddy to call me…", then "Ok do 1" (do the call-now part first). On 10 Nov 2026: "daj to już żeby działało" (get it working now).
- **Status:** applied in the pull request of branch `claude/kind-maxwell-xpnfhj`
- **Replaces:** the line in `call_me_later` and `voice-agent/instructions.md` that told the user to tap Call me now in Settings for a call right now

## Why
`call_me_later` books a call from two minutes ahead. A call right now was only possible from Settings, Phone calls, Call me now. When the user asked for one in a conversation, Doddy sent them to Settings.

## Decision
- A new voice tool, `call_me_now`, with no parameters. Nothing the model writes can choose the number. The server calls only the user's verified number, as `POST /v1/calls/outbound` always has (ADR-750).
- Before the card the app checks the same things as `call_me_later` (`CallReadiness`): a verified number, "Doddy may call me" on, and the server's phone line set up. The card shows "Call you now?" and the last three digits. Nothing is placed until the tap on **Call me**.
- After the tap the app sends the same request as the Settings button (`DoddyServerClient.callMeNow`). The agent hears one of four results:
  - `requested`: the phone is being rung, not answered;
  - `unknown`: never redialled (DOD-08);
  - `failed` with the reason;
  - `declined`.
- Unlike a booked call, a call right now ignores quiet hours, because the user is awake and asking. The server's caps still apply: 3 an hour and 10 a day (`OUTBOUND_HOURLY_LIMIT`, `OUTBOUND_DAILY_LIMIT`).
- It waits while driving (`CarProfile`) and while connections are paused (`ConnectionPause`). It is part of `Feature.phoneCalls`, so the beta (`ReleaseScope.shipping`) hides it with the rest of phone calls.
- The client now reads the messaging server's own 502 `{"error":"provider_unavailable","callId":…}` as "not placed". Since #293 the server answers that when Twilio refuses the call, and marks the call row `failed`. A 502 without that body may come from a proxy after the call started, so it is still `unknown` (ADR-672). Before this change, the Settings button said "Couldn't confirm the call was placed" when Twilio had refused the call.

## Consequences
- The live ElevenLabs agent needs the tool created and attached, and its prompt brought in line with `voice-agent/instructions.md`, before Doddy can use it. Both are live-agent changes, made on the owner's instruction.
- The owner's two taps on 9 Nov returned 502 from Twilio. Until the reason is fixed (the code is in the Render log since #293), this tool will answer `failed: the phone service turned the call down`.

## Evidence
- `make test-core` on Linux (Swift 6.1.3): 2811 tests, 0 failures, including the new `CallMeNowTests`.
- `scripts/ci.sh --only checks`: PASS except the Studio renderers step (NOT RUN, no reportlab).
- `backend` `npm test`: 678 pass.
- Not compiled: the app (`VoiceSessionController.swift`, `VoiceView.swift`); the hosted Mac job is its first build. Not run on a phone.
