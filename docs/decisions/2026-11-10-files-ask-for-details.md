# Doddy asks what a file is for before making it, and the server insists on it

- **Date:** 2026-11-10
- **Decided by:** owner (10 Nov 2026): one tool, `make_document`, for every file; Doddy asks one or two short questions first when essential details are missing; the beta shows file-making.
- **Status:** proposed in the pull request `claude/make-file-asks-details`; owner approval pending for the live-agent steps
- **Replaces:** the `.claudeDocuments` entry in `ReleaseScope.shipping` (hidden since ADR-574); builds on ADR-564, ADR-606 and `2026-11-10-better-presentations`

## Why
"Prezentacja o Iławie" made a deck for nobody in particular, of no particular length. A prompt line alone ("ask first") is not enforced; the constitution says rules are enforced in code, not only in the prompt.

## Decision
1. **Prompt side.** The `make_document` description in `voice-agent/tools.json` tells the agent to ask at most two short questions (who it is for, what it is for, how long, the tone), skip what the user already said, and use stated defaults on "just do it". It also says a file is ready only when the result says so.
2. **Code side.** `backend/src/tools/documentDetails.ts` judges kind, title, request and material at `prepare` (the step before the ask card). It refuses only a request with neither a purpose nor an audience cue, that has fewer than 9 words (title plus request) and no material of at least 40 characters. Missing items come from the fixed set `audience`, `purpose`, `length` (a spreadsheet is never asked for length; a length already given is not asked again). The refusal is the error code `need_details` (HTTP 422), raised before the single-use approval, the daily caps and any model call, so it costs nothing and the user's yes is not spent (there is no yes yet). No receipt is written.
3. **What the agent receives.** `VoiceToolReply.cloudFailed` (DoddyCore) turns `need_details` into a result that starts with the word `need_details:`, then the server's line ("Missing details: audience, purpose, length."), then "Nothing was made and nothing was used up. Ask the user at most two short questions ... then call make_document again". It is never "failed:", "unknown:" or "done". `VoiceSessionController` is untouched: its existing `catch` already calls `cloudFailed`.
4. **Messages file cards (ADR-606).** `ThreadDocumentError.needsDetails` shows "Add a bit more detail, such as who it is for or what it is for, and try again. Nothing was made." instead of the generic failure.
5. **Beta scope.** `.claudeDocuments` leaves `ReleaseScope.shipping`, so `ask_claude` and `make_document` run in the beta. `.presentations` (`make_presentation`, the phone-made deck) stays hidden; the owner detaches that tool from the live agent so there is one tool.

## Caps that apply (no new cap added)
- `make_document` counts as `DODDY_DOCUMENT_CLAUDE_UNITS` = 5 Claude runs against `DODDY_LIMIT_USER_DAILY_CLAUDE` = 40 per person per UTC day (shared with `ask_claude`, one run each) and `DODDY_LIMIT_SERVICE_DAILY_CLAUDE` = 100 for the server: at most 8 files per person and 20 in all per day when nothing else uses Claude.
- At most `DODDY_LIMIT_USER_DOCUMENT_JOBS` = 1 file being made per person and `DODDY_LIMIT_SERVICE_DOCUMENT_JOBS` = 3 on the server at once (ADR-710).
- `DODDY_LIMIT_USER_DAILY_READS` x 4 requests per person per day bound `prepare` itself.
A separate "10 files a day" cap would sit above the existing 8 and never bind, so none was added. To change the number, set `DODDY_LIMIT_USER_DAILY_CLAUDE` or `DODDY_DOCUMENT_CLAUDE_UNITS` on Render `doddy`.

## Consequences
- A user who says only a topic hears one or two questions. A request that is long, or names an audience or purpose, never does. The judge is a small word-count and cue-word check; tune `THIN_WORDS`, `MATERIAL_ENOUGH_CHARS` and the cue lists in that one file.
- The live agent's `make_document` description differs from the spec until the owner-approved sync. Until then the server still refuses a thin request, so the code works without the prompt change; the agent just asks less gracefully.
- Cue lists are Polish and English only; another language is judged by word count alone.

## Evidence
Backend unit tests for the judge and a `prepare`-level test that a refusal answers 422 `need_details`, calls no model and counts nothing; DoddyCore tests for the agent's result and for the release scope. Not run: the app (no Xcode), a call with the live agent.
