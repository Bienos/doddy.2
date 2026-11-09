# ElevenLabs is the only voice; OpenAI voice and the voice picker are removed

- **Date:** 2026-11-09
- **Decided by:** owner ("usuń również opcję wyboru głosu, tylko ElevenLabs. Od teraz możemy usunąć OpenAI", then "ale tylko OpenAI usuń dla głosu"; call rehearsal removal confirmed when asked)
- **Status:** accepted
- **Replaces:** ADR-265 (OpenAI Realtime as a provider), ADR-442 (OpenAI default and model picker), ADR-443 (picker on Home), ADR-546 (ElevenLabs default again, now the only one), ADR-726 (OpenAI without a voice account)

## Why
Two voices meant two privacy stories, two consent paths, a picker nobody asked for in the beta (the shipping scope already hid it, `ReleaseScope.shipping`), a second server path that spends the owner's money, and a Debug switch that let strangers use it (`OPENAI_OPEN_ACCESS`). The owner wants one voice.

## Decision
- **App:** no `VoiceProvider`, no picker (Home's ••• › Voice, Settings › Voice), no OpenAI model choice, no `OpenAIRealtimeSession`, no OpenAI wire code. `Feature.voiceProviderPicker` is gone from `ReleaseScope`.
- **Call rehearsal removed.** It ran only on OpenAI Realtime. "Dzwonię sam" (the script on screen) stays. A rehearsal on ElevenLabs would need a new agent, which is the owner's to change.
- **Token server:** `POST /api/voice-token` and `sign-in` on `/api/voice-auth` accept `elevenlabs` only. `{"provider":"openai"}` from an older app gets `400 unknown_provider` (voice-token) or `400 invalid_request` (voice-auth). Every voice request needs a Doddy account session; the open-access bucket is gone.
- **Consent:** one voice-data consent, stored under the key that was kept for ElevenLabs (`voice.providerConsent.elevenlabs.v1`), so a yes already given still counts.
- **Kept on purpose:** OpenAI in the gateway (typed Ask Doddy fallback), the news writer on `doddy-messaging`, and the OpenAI model behind the live ElevenLabs agent. None of them is a voice choice. Conversation logs from before this date may say `"openai"` and still load; the history screens name that voice truthfully.

## Consequences
- Weather and Wikipedia now always work in a conversation (they never worked with OpenAI).
- Older app builds with OpenAI chosen can't talk until they update or switch to ElevenLabs.
- Public pages: Privacy and Terms (en, pl) and the homepage FAQ line (all languages) no longer offer OpenAI as the voice. The privacy page keeps OpenAI as the language model behind ElevenLabs. The versions in `LegalAcceptance.swift` are not raised: the change removes a way data could go, and `docs/legal/LEGAL_PAGES_OWNER_CHECKLIST.md` leaves that call to the owner.
- `voice-agent/session.json` lost its `openai_realtime` block and `scripts/voice_agent_spec.py` its `openai` command.
- Owner step left: Vercel, after the merge (`docs/OWNER_QUEUE.md` item 30).
- Eight draft app languages lose the few changed sentences (they show English there); Polish was updated.

## Evidence
`node --test` in `server/voice-token`: 65 passed. `bash scripts/check_forbidden_capabilities.sh`, `node tools/secrets/sync.mjs check`, `python3 -I tools/build_strings_catalog.py --check`: pass. The Swift changes (DoddyApp, DoddyCore, tests, UI tests) were **not compiled and not run**: this session had no Swift toolchain. The hosted Mac CI is the first compile.
