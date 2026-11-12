Voice: "find me sushi and open Wolt" — new tool `open_food_app` shows a card ("Open Wolt? Search there for: …") and opens the app only on the tap; the person orders there, nothing is ordered by Doddy. Bolt Food joins the Food button (decision `2026-11-12-food-by-voice`).
Backend: the Logbook day's body cap is 24 KB (was 16): with 117 tools the pretty-printed worst case passed 16 KB; the iPhone's real days are about 7 KB. Takes effect with the next `doddy` deploy.
Ran: `make test-core` (Linux), backend `node --test` (719 pass), `scripts/voice_agent_spec.py check`, `scripts/typecheck_app_logic.sh`, `scripts/ci.sh --only checks`. Not compiled here: `VoiceSessionController.swift`. Not tried by voice.
Owner step: add the tool to the live voice agent (OWNER_QUEUE 45).
