# Acceptance matrix (proposed test spec)
**Never report unexecuted tests as passing.** Record device/OS/build/commit, steps, expected, observed, evidence and disposition for every row.

| ID | Phase | Scenario | Pass condition |
|---|---|---|---|
| A-01 | M0 | Fresh install & first launch | Launch succeeds; honest product label; no fake network/audio |
| A-02 | M1 | Save valid Unicode note | Data persisted, original exact text, correct source/date |
| A-03 | M1 | Empty >5k input | Validation error, zero corrupted/truncated records |
| A-04 | M1 | Simulated storage failure | No success toast; unsaved draft recoverable |
| A-05 | M1 | Force quit / relaunch | Saved records preserved with correct metadata |
| A-06 | M1 | Edit note | rawText retained, currentText changed, updatedAt set |
| A-07 | M1 | Recall with typo/diacritics | Real record IDs returned; source surfaced; no hallucinations |
| A-08 | M1 | Deleted note search | Cannot reappear through index/cache or restart |
| A-09 | M1 | Conflicting facts | Both presented or clarification; no invented certainty |
| A-10 | M1 | Corrupt DB / interrupted migration | Non-destructive recovery; explicit error; no silent reset |
| A-11 | M1 | JSON/text export | User can inspect exact data, metadata and provenance |
| A-12 | M1 | Delete-all confirmation | Both text and indexes gone; relevant remaining copies disclosed |
| A-13 | M1 | VoiceOver/Dynamic Type/dark/reduced motion | Usable at max supported settings, no hidden status |
| A-14 | M2 | Approved memory citations only | Unknown IDs rejected; no fabricated personal facts |
| A-15 | M2 | Provider fail/rate limit/offline | Graceful error and retry; local memory always usable |
| A-16 | M2 | Network/log minimization | Only approved fields transmitted/logged |
| A-17 | M3 | Real mic permissions | Correct mic usage; denial → text fallback |
| A-18 | M3 | Background/interruption/route change | Capture stops and resources released |
| A-19 | M3 | Polish/English utterances | Actual speech recognition tested with recorded ground truth |
| A-20 | M4 | Clarify ambiguous time | Never silently schedule wrong date/timezone |
| A-21 | M4 | Verified EventKit write | External reminder exists with saved external ID |
| A-22 | M4 | Unknown write outcome | Reconcile; no duplicate via naive retry |
| A-23 | M4 | Permission denied | User told no external reminder created; local draft remains |
| A-24 | M5 | Study metrics | Organic, prompted, reacquisition, paid intent separated |
| A-25 | All | Character persona evals | Truth and task completion win over joke/animation |

## Test layers
Unit: validation, schema migration, lexical candidate recall, action proposal state. Integration: GRDB read/write/delete/export, gateway contract, EventKit adapter where available. UI: first-run, denial, loading, error, accessibility. Physical device: audio, Back Tap/Shortcut, iOS protection, memory pressure, interruptions, EventKit. Security: injection, failure/replay, telemetry PII checks. Persona: test 64 source cases, update cases for actual release context.

## Evidence record
`testId;buildSha;device;osVersion;executionDate;runner;commandOrSteps;expected;actual;passFailBlocked;artifactLink;knownLimitations`.
