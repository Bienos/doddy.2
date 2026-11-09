# Agreeing to send voice to the provider moves into first-run setup; Talk shows only a short fallback

- **Date:** 2026-11-09
- **Decided by:** owner, on a TestFlight screenshot of "Before Doddy listens": "We should get rid of that in that stage and move it", then chose "Into setup" over folding it into the Terms step or only shortening it.
- **Status:** proposed in this pull request
- **Replaces:** the consent part of ADR-522 ("on first voice use, Sign in with Apple, then one consent switch per provider"). Sign-in is unchanged.

## Why
The first tap on Talk stopped at a full page of provider text, a switch and "Continue to microphone access" before Doddy said anything. The microphone is already asked in the first-run "Let Doddy get ready" step (ADR-814), so the provider agreement belongs next to it.

## Decision
- "Let Doddy get ready" gets one box under the iOS list: "Send my voice to <provider>", with a short reason and a "What's sent" disclosure holding the full text. It starts **unticked** (`FirstRunAccessRule.voiceDataTickedAtStart`): it is agreement to send data to another company, not an iOS permission.
- It is recorded (`VoiceProviderConsent.grant`, the same per-provider key as before) only when the box is ticked and the person taps "Allow selected" (`FirstRunAccessRule.recordsVoiceConsent`). "Not now" records nothing. Recording it turns on no microphone and sends nothing; a conversation still starts only from Talk.
- Talk still checks the same consent before connecting (`VoiceView`, `VoiceSessionController`, `HomeConversation`, `TalkInIsland`, unchanged). For someone without it (skipped setup, installed before this step existed, switched provider, or used "Ask again before sharing voice"), "Before Doddy listens" is now one sentence, a "What's sent" disclosure with the full text, and an "Agree and talk" button. Tapping the button is the agreement.
- The provider text lives once, in `VoiceConsentCopy`, for both places. Its strings are format strings so Polish applies; Polish lines added.

## Consequences
- The first Talk for a new user who ticks the box goes straight to the iOS microphone question (if not already answered) and the conversation.
- Agreement is now given before the person has heard Doddy. The full text is one tap away in both places, and Settings can still reset it.
- People who already agreed keep their answer; nothing is migrated.

## Evidence
`make test-core` and `scripts/ci.sh --only checks` on Linux (results in the pull request). The SwiftUI screens were **not compiled** here (no Xcode); the hosted `ios-build` job compiles them. Not seen on a device.
