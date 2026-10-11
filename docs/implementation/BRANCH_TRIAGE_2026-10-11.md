# Branch triage, 2026-10-11

This is a read-only review of every remote branch in `Bienos/doddy.2`.
Nothing was deleted, merged, closed or pushed.

## How it was measured

- Base: `origin/claude/loving-dirac-uuxoux` (default branch) at `a419f59a`, after `git fetch origin`.
- Ahead / behind: `git rev-list --left-right --count base...branch`. "Ahead" is commits on the branch that are not on default.
- Clean merge: `git merge-tree --write-tree base branch`. Exit code 0 means clean; the listed files conflict.
- ADR numbers: rows like `| 123 |` added to `DECISIONS.md` in `git diff base...branch`, compared with default's `DECISIONS.md`.
- Superseded: checked by hand whether the branch's files or feature already exist on default.
- Open PRs: GitHub `list_pull_requests` (state open). There are 9 open PRs.
- No code was built or tested for this triage. "Clean" means git merges it without conflicts, not that it compiles.

Counts: 70 branches besides default. A (fully merged): 38. B (superseded): 15. C (small and clean): 3. D (needs real work): 14.

Classes:

- **A**: fully merged (ahead = 0). Safe to delete.
- **B**: superseded. The same feature is already on default. Close and delete.
- **C**: small and merges cleanly. Could merge after review.
- **D**: needs real work: conflicts, large, or ADR numbers to fix.

## Branches

| Branch | PR | Ahead / behind | Last commit | Class | Summary | Conflicts |
|---|---|---|---|---|---|---|
| `claude/admiring-curie-bsuwv9` | #43 (to default) | 8 / 183 | 2026-10-11 | D | Quick start screen after the introduction (ADR-324). Also edits ADR-306: weekly look-back default Sunday 19:00. | DECISIONS.md, LaunchSmokeTests.swift, MAC_VERIFICATION_CHECKLIST_2026-10-10.md |
| `claude/admiring-curie-bsuwv9-all` | none | 28 / 155 | 2026-10-11 | D | Integration branch. Merges all eight admiring-curie branches (ADR-324 to 328, 401 to 403). | HomeView.swift, VoiceSessionController.swift, Localizable.xcstrings, LaunchSmokeTests.swift, VoiceTokenTests.swift, pl.json |
| `claude/admiring-curie-bsuwv9-ask-about-note` | #58 (to default) | 1 / 161 | 2026-10-11 | D | "Ask me about it" on Home's recent notes (ADR-403). | VoiceSessionController.swift |
| `claude/admiring-curie-bsuwv9-first-conversation` | #56 (to -home-first-visit) | 7 / 183 | 2026-10-11 | D | Guided first conversation, shown once (ADR-401). Contains -onboarding and -home-first-visit. | DECISIONS.md, HomeView.swift, SettingsView.swift, VoiceSessionController.swift, Localizable.xcstrings, LaunchSmokeTests.swift, MAC_VERIFICATION_CHECKLIST_2026-10-10.md, pl.json |
| `claude/admiring-curie-bsuwv9-hey-doddy-card` | #53 (to default) | 1 / 183 | 2026-10-11 | D | "Hey Doddy" with one tap, and a Home card that offers it (ADR-328). | DECISIONS.md, VoiceTokenTests.swift, MAC_VERIFICATION_CHECKLIST_2026-10-10.md |
| `claude/admiring-curie-bsuwv9-home-first-visit` | #48 (to -onboarding) | 6 / 183 | 2026-10-11 | D | Home's first visit keeps to talking; privacy summary moves to Settings (ADR-326). Contains -onboarding. | DECISIONS.md, HomeView.swift, SettingsView.swift, Localizable.xcstrings, LaunchSmokeTests.swift, MAC_VERIFICATION_CHECKLIST_2026-10-10.md, pl.json |
| `claude/admiring-curie-bsuwv9-onboarding` | #46 (to default) | 4 / 183 | 2026-10-11 | D | First-use fixes: test voice switch moves to Settings; listening waits for the mic (ADR-325). | DECISIONS.md, HomeView.swift, LaunchSmokeTests.swift, MAC_VERIFICATION_CHECKLIST_2026-10-10.md |
| `claude/admiring-curie-bsuwv9-quick-access` | #57 (to admiring-curie-bsuwv9) | 9 / 183 | 2026-10-11 | D | Where to start Doddy without opening the app (ADR-402). Contains admiring-curie-bsuwv9. | DECISIONS.md, LaunchSmokeTests.swift, MAC_VERIFICATION_CHECKLIST_2026-10-10.md |
| `claude/admiring-curie-bsuwv9-short-intro` | #51 (to default) | 2 / 183 | 2026-10-11 | D | Shorter introduction: three questions instead of six (ADR-327). Only 29 lines, but it conflicts. | DECISIONS.md, MAC_VERIFICATION_CHECKLIST_2026-10-10.md |
| `claude/cool-archimedes-9l8l1h` | none | 3 / 183 | 2026-10-11 | D | Learning loop phases A and B: typed core, migrations v11 to v13, repositories, tests (ADR-324). Not on default. | DECISIONS.md |
| `claude/epic-gauss-md6x9b` | none | 1 / 176 | 2026-10-11 | D | Timers, saved island, widgets, wallpaper, review prompt, paper notification (ADR-337 to 343). 2,612 lines. | DECISIONS.md, WidgetSync.swift, WidgetSnapshot.swift |
| `claude/hopeful-fermat-1a63x0` | none | 9 / 161 | 2026-10-11 | D | Round 7: unlock as you go (ADR-324), people pages, warranties, the usual on lists, bills. Code cites ADR-341 to 344 with no DECISIONS rows. | MemoryStore.swift, Localizable.xcstrings, ActivityLog.swift, pl.json |
| `claude/lucid-johnson-pmwwg4` | none | 4 / 183 | 2026-10-11 | D | Unlock as you go (ADR-324). Fully contained in hopeful-fermat-1a63x0. | DECISIONS.md, instructions.md |
| `claude/peaceful-hopper-v3gx75` | #44 (to default) | 16 / 155 | 2026-10-11 | D | Action status model, session recovery, Stop listening, unfinished notes (ADR-319 to 322, 360 to 362). 5,785 lines. | AlarmScheduler.swift, SettingsView.swift, VoiceSessionController.swift, Localizable.xcstrings, ActivityLog.swift, pl.json, build_strings_catalog.cpython-313.pyc |
| `claude/fervent-hamilton-cv19sj` | none | 1 / 155 | 2026-10-11 | C | Adds prompts/APPLE_PLATFORMS_WATCH_IPAD_MAC.md. Docs only. | None |
| `claude/sleepy-bell-795a0u` | none | 1 / 206 | 2026-10-11 | C | Settings: TikTok and Instagram labels drop 'doddy_mate'. 2 lines. Default still shows the handle. | None |
| `claude/sleepy-gates-f9najr` | none | 1 / 230 | 2026-10-11 | C | Public init for SharedListMerge.Result. Fixes a compile error that is still on default. | None |
| `claude/admiring-bohr-0xn7fa` | none | 1 / 638 | 2026-10-10 | B | Early Dynamic Island Live Activity and Back Tap shortcut. Both are on default (VoiceLiveActivity.swift, Talk to Doddy intent). | 12 files |
| `claude/busy-hawking-20w5ql` | none | 9 / 639 | 2026-10-08 | B | Oct 8 M2 gateway (Supabase) and a 'popcorn' voice decision. Default has the gateway, M2 status and later voice decisions. | 14 files |
| `claude/busy-mendel-cckm8b` | none | 5 / 635 | 2026-10-09 | B | V2 Siri and Shortcuts, Back Tap setup, voice token server. All on default (server/voice-token, ADR-040 to 048). | 28 files |
| `claude/clever-davinci-6icfxq` | none | 11 / 638 | 2026-10-09 | B | Landing page, waitlist, admin page, analytics. site/ and site/admin are on default. | 15 files |
| `claude/confident-planck-0gf6qo` | none | 5 / 638 | 2026-10-10 | B | Constitution V1, action ledger, Apple Reminders (M4). docs/trust and M4_REMINDERS_STATUS.md are on default. | 19 files |
| `claude/dreamy-mayer-u3rtx4` | none | 12 / 638 | 2026-10-09 | B | Landing page plus optional waitlist questions. site/api/waitlist-answers.js is on default. | 11 files |
| `claude/eloquent-hawking-pax4bq` | none | 1 / 638 | 2026-10-10 | B | Store voice-confirmed notes as explicit_voice. Default already saves them with source .explicitVoice. | 5 files |
| `claude/friendly-sagan-6odwsl` | none | 5 / 638 | 2026-10-09 | B | Oct 9 M2 OpenAI gateway plus a 401-file video asset library import. Gateway is on default; the asset library is not. | DECISIONS.md, M2_STATUS.md |
| `claude/gifted-hypatia-u6vwds` | none | 1 / 638 | 2026-10-09 | B | Design mockups for an optional 'keep the taps quiet' step. The quiet-banner previews are already on default. | None |
| `claude/kind-davinci-kfndaz` | none | 1 / 638 | 2026-10-09 | B | Proposed brand guidelines. Default has BRAND_GUIDELINES.md; it differs by one line. | BRAND_GUIDELINES.md |
| `claude/lucid-rubin-h8mfmr` | none | 2 / 645 | 2026-10-08 | B | Switches colour tokens to brand v1.3. Conflicts with the current Pocket Notebook direction (edits ADR-018). | Theme.swift, BRAND_INDEX.md |
| `claude/nice-thompson-6exq2t` | none | 1 / 638 | 2026-10-09 | B | Image-generation prompt pack. The same file is already on default, unchanged. | None |
| `claude/nifty-euler-w6vgdb` | none | 5 / 638 | 2026-10-09 | B | Background voice detection, Realtime-shape voice spec, character master C. The voice-agent spec and setting are on default. | 10 files |
| `claude/upbeat-brown-c4svzf` | none | 3 / 638 | 2026-10-09 | B | V4a: Calendar, Reminders and Contacts connections. ConnectionsView and the connections work are on default. | 20 files |
| `claude/vibrant-pasteur-qroc3f` | none | 1 / 638 | 2026-10-09 | B | Guided Back Tap setup. BackTapSetupView.swift and BackTapSetup.swift are on default. | 8 files |
| `claude/affectionate-edison-ktc6i6` | none | 0 / 156 | 2026-10-11 | A | Fully merged. Last: Merge claude/loving-dirac-uuxoux into #36 (undo for voice-saved notes) | n/a |
| `claude/blissful-curie-ftam0y` | none | 0 / 418 | 2026-10-10 | A | Fully merged. Last: Sync Gmail/Todoist plan steps to the live voice agent (ADR-209) | n/a |
| `claude/blissful-einstein-5msya4` | none | 0 / 320 | 2026-10-11 | A | Fully merged. Last: Merge the default branch (PR #28, Whole Doddy = ADR-264); OpenAI te... | n/a |
| `claude/blissful-thompson-72xwl1` | none | 0 / 602 | 2026-10-10 | A | Fully merged. Last: Draft Render blueprint for the backend (not deployed) | n/a |
| `claude/brave-keller-f8h6uq` | none | 0 / 611 | 2026-10-09 | A | Fully merged. Last: Voice token server deployed to Vercel production (API key pending) | n/a |
| `claude/brave-wright-k4jnu3` | none | 0 / 518 | 2026-10-10 | A | Fully merged. Last: Fix review findings: filter no longer springs back, pin-limit alert... | n/a |
| `claude/busy-galileo-v68apl` | none | 0 / 593 | 2026-10-10 | A | Fully merged. Last: Blog: unpublish "Hello, Doddy", add illustrated Doddy banners | n/a |
| `claude/busy-wozniak-15yzp7` | none | 0 / 0 | 2026-10-11 | A | Fully merged. Last: Merge pull request #38 from Bienos/claude/zealous-lamport-hxt7lw-xcode | n/a |
| `claude/camera-shortcut-button` | none | 0 / 207 | 2026-10-11 | A | Fully merged. Last: Merge the default branch into the camera shortcut PR; renumber to A... | n/a |
| `claude/clever-gates-b0mkhs` | none | 0 / 432 | 2026-10-10 | A | Fully merged. Last: site/README: it is deployed (Vercel); touches site/ so the ignored-... | n/a |
| `claude/clever-ritchie-f7w234` | none | 0 / 561 | 2026-10-10 | A | Fully merged. Last: Social links: drop the @ from the visible labels | n/a |
| `claude/compassionate-darwin-6wi1ba` | none | 0 / 524 | 2026-10-10 | A | Fully merged. Last: docs: Ask Doddy gateway is deployed; record address and live checks | n/a |
| `claude/cool-euler-wu64g8` | none | 0 / 637 | 2026-10-09 | A | Fully merged. Last: Personality settings: humour, reply length, tone and mood for Doddy | n/a |
| `claude/cool-rubin-xywy2g` | none | 0 / 636 | 2026-10-09 | A | Fully merged. Last: Onboarding: fixes from code review | n/a |
| `claude/dazzling-pascal-mr4zjn` | none | 0 / 325 | 2026-10-11 | A | Fully merged. Last: Docs: messaging service on the new Render account is live | n/a |
| `claude/dazzling-pascal-mr4zjn-db-timeout` | none | 0 / 327 | 2026-10-11 | A | Fully merged. Last: Messaging server: fail fast with a clear log when the database is u... | n/a |
| `claude/determined-sagan-x34oz2` | none | 0 / 643 | 2026-10-09 | A | Fully merged. Last: Fix UI smoke test for the voice privacy row | n/a |
| `claude/eager-johnson-bu42em` | none | 0 / 204 | 2026-10-11 | A | Fully merged. Last: Merge remote-tracking branch 'origin/claude/loving-dirac-uuxoux' in... | n/a |
| `claude/elegant-dijkstra-0r1bg5` | none | 0 / 637 | 2026-10-10 | A | Fully merged. Last: Business: monetization model v2 audit, repricing and unit-economics... | n/a |
| `claude/elegant-knuth-hc1aql` | none | 0 / 392 | 2026-10-10 | A | Fully merged. Last: Backend: list emails and tasks as data in read results (from ADR-231) | n/a |
| `claude/eloquent-pasteur-7ruafk` | none | 0 / 636 | 2026-10-10 | A | Fully merged. Last: M2: typed AI questions through an OpenAI gateway (built and unit-te... | n/a |
| `claude/gallant-lamport-7x7k5w` | none | 0 / 407 | 2026-10-10 | A | Fully merged. Last: Focus timer, breathing and read-aloud with their islands (ADR-214 t... | n/a |
| `claude/inspiring-einstein-j3lvjc` | none | 0 / 623 | 2026-10-09 | A | Fully merged. Last: V3: Doddy in the Dynamic Island while you use other apps | n/a |
| `claude/inspiring-knuth-sgk8v0` | none | 0 / 454 | 2026-10-10 | A | Fully merged. Last: Web search: decode HTML entities in results; record the live Render... | n/a |
| `claude/keen-cray-g4g5vj` | none | 0 / 635 | 2026-10-09 | A | Fully merged. Last: Backend: one-time Composio setup script and cloud live-check runbook | n/a |
| `claude/lucid-sagan-mpwylm` | none | 0 / 423 | 2026-10-10 | A | Fully merged. Last: Merge claude/loving-dirac-uuxoux; renumber the audio-session decisi... | n/a |
| `claude/magical-newton-ip0bx2` | none | 0 / 556 | 2026-10-10 | A | Fully merged. Last: Voice agent: record live sync of calendar/reminder wording (ADR-129) | n/a |
| `claude/nice-albattani-t1yan6` | none | 0 / 622 | 2026-10-09 | A | Fully merged. Last: V3: island goes stale instead of lying when iOS stops Doddy in the... | n/a |
| `claude/serene-davinci-as4pyg` | none | 0 / 412 | 2026-10-10 | A | Fully merged. Last: Merge claude/loving-dirac-uuxoux; renumber the opening decision to... | n/a |
| `claude/serene-johnson-0jz6ao` | none | 0 / 500 | 2026-10-10 | A | Fully merged. Last: Site footer: show just "TikTok" and "Instagram", drop the doddy_mat... | n/a |
| `claude/stoic-lamport-6iz5dw` | none | 0 / 627 | 2026-10-09 | A | Fully merged. Last: Knowledge for the personal build: notes and recent conversations at... | n/a |
| `claude/stoic-pasteur-sxkce7` | none | 0 / 432 | 2026-10-10 | A | Fully merged. Last: Fix Linux app type-check after note reminders (ADR-198) | n/a |
| `claude/tender-lamport-08yl04` | none | 0 / 386 | 2026-10-10 | A | Fully merged. Last: Renumber the translator line's ADRs: 210-219 become 217-226; the tr... | n/a |
| `claude/wonderful-cray-s5r90b` | none | 0 / 425 | 2026-10-10 | A | Fully merged. Last: Dynamic Island go-live: intent process log, CI runner state, go-liv... | n/a |
| `claude/youthful-fermi-qn62y0` | none | 0 / 409 | 2026-10-10 | A | Fully merged. Last: Set the Google Analytics measurement ID (ADR-211) | n/a |
| `claude/zealous-lamport-hxt7lw` | none | 0 / 78 | 2026-10-11 | A | Fully merged. Last: Merge the other default-branch merge of #37 | n/a |
| `claude/zealous-lamport-hxt7lw-xcode` | none | 0 / 1 | 2026-10-11 | A | Fully merged. Last: Merge claude/loving-dirac-uuxoux into #38 (Xcode-side review fixes) | n/a |
| `codex/doddy2-native-baseline` | none | 0 / 621 | 2026-10-10 | A | Fully merged. Last: Build approved Doddy memory journey and native verification baseline | n/a |

## Recommendations

### A: fully merged (delete)

- All 38 branches have no commits outside default. Delete them.
- `claude/busy-wozniak-15yzp7` is the branch checked out in the local working tree. It equals default. Delete the remote copy only when that session is done.
- `claude/zealous-lamport-hxt7lw-xcode` is PR #38, already merged. It is 1 commit behind (the merge commit).

### B: superseded (close and delete)

- Do not merge any of these. Most are Oct 8 to Oct 10 work that landed on default through other branches, under other ADR numbers.
- Merging them would add duplicate `DECISIONS.md` rows with numbers default already uses (see below).
- Two need a short owner check before deletion:
  - `claude/friendly-sagan-6odwsl` holds a 401-file video asset library that is not on default. The owner's 2026-10-11 rule names only the numbered video pack (`UploadedDoddy_*`, `WholeDoddy_*`), so it is likely not needed.
  - `claude/lucid-rubin-h8mfmr` switches tokens to brand v1.3. Current rules keep v1.3 as reference only. Close it unless the owner approves v1.3.
- None of these has an open PR.

### C: small and clean (review, then merge)

1. `claude/sleepy-gates-f9najr` first. Default still has the compile error it fixes: `SharedListsController` builds `SharedListMerge.Result(...)`, but the struct has no public init. The commit says the DoddyCore tests passed on Linux; the iOS app was not built.
2. `claude/sleepy-bell-795a0u`. Two label strings. It drops a space after the comma (`Label("TikTok",systemImage:`); fix that when merging.
3. `claude/fervent-hamilton-cv19sj`. One prompt file. Merge only if the Watch/iPad/Mac prompt is still wanted.
- None of these has an open PR. Each needs one.

### D: needs real work

- **admiring-curie stack (PRs #43, #46, #48, #51, #53, #56, #57, #58).** All eight branches conflict with default. Pick one route:
  - Merge the stack in order after rebasing: #46, then #48, then #56; #43, then #57; #51, #53 and #58 on their own.
  - Or open one PR from `claude/admiring-curie-bsuwv9-all`, which already contains all eight. It conflicts in 6 files, not in `DECISIONS.md`. Then close the eight PRs.
  - Either way, two other branches also claim ADR-324; agree which feature keeps it and renumber the rest. Common conflicts: `DECISIONS.md`, `MAC_VERIFICATION_CHECKLIST_2026-10-10.md`, `LaunchSmokeTests.swift`, `HomeView.swift`, `Localizable.xcstrings`, `l10n/pl.json`.
- **`claude/peaceful-hopper-v3gx75` (PR #44).** The largest branch (75 files). Resolve 7 conflicts. It also changes a tracked `tools/__pycache__/*.pyc` that default deleted; drop that file.
- **`claude/hopeful-fermat-1a63x0`.** Resolve 4 conflicts. Add `DECISIONS.md` rows for the features its code cites as ADR-341 to 344, using free numbers. It contains `claude/lucid-johnson-pmwwg4`; delete that branch once this one lands.
- **`claude/epic-gauss-md6x9b`.** Renumber ADR-337 to 343 (337 to 340 are taken on default). Resolve conflicts in `WidgetSync.swift` and `WidgetSnapshot.swift`.
- **`claude/cool-archimedes-9l8l1h`.** Only `DECISIONS.md` conflicts. ADR-324 is also claimed by Quick start and unlock as you go; renumber if it does not keep it. Its migrations v11 to v13 are the next free numbers; no other branch adds migrations. It starts a learning-loop milestone (M6), so it needs explicit milestone approval before merging.
- **`claude/lucid-johnson-pmwwg4`.** Handle through `claude/hopeful-fermat-1a63x0`.
- Suggested order: C branches, then the admiring-curie work, then #44, then hopeful-fermat, epic-gauss and cool-archimedes. Rebase each on the new default before the next.

## ADR number collisions

Default's highest ADR row in `DECISIONS.md` is 340. Numbers 319 to 322 and 324 to 329 have no row on default. The next free number at the end is 341.

### With default

| Branch | Adds | Collides with default |
|---|---|---|
| `claude/admiring-bohr-0xn7fa` | 038, 039, 040, 041 | 038, 039, 040, 041 |
| `claude/busy-hawking-20w5ql` | 033, 034, 035, 036, 037, 038 | 033, 034, 035, 036, 037, 038 |
| `claude/busy-mendel-cckm8b` | 038, 039, 040, 041, 042, 043, 044, 045, 046, 047, 048 | 038, 039, 040, 041, 042, 043, 044, 045, 046, 047, 048 |
| `claude/confident-planck-0gf6qo` | 038, 039, 040, 041, 042, 043, 044, 045, 046, 047, 048, 049, 050, 051, 052, 053, 054, 055 | 038, 039, 040, 041, 042, 043, 044, 045, 046, 047, 048, 049, 050, 051, 052, 053, 054, 055 |
| `claude/epic-gauss-md6x9b` | 337, 338, 339, 340, 341, 342, 343 | 337, 338, 339, 340 |
| `claude/friendly-sagan-6odwsl` | 038, 039, 040 | 038, 039, 040 |
| `claude/kind-davinci-kfndaz` | 038, 039 | 038, 039 |
| `claude/nifty-euler-w6vgdb` | 038, 039, 040, 041, 042 | 038, 039, 040, 041, 042 |
| `claude/upbeat-brown-c4svzf` | 038, 039, 040, 041, 042, 043, 044, 045, 046, 047, 048, 049, 050, 051, 052, 053, 054, 055, 056, 057 | 038, 039, 040, 041, 042, 043, 044, 045, 046, 047, 048, 049, 050, 051, 052, 053, 054, 055, 056, 057 |
| `claude/vibrant-pasteur-qroc3f` | 038, 039 | 038, 039 |

- All the old (B) collisions are numbers default gave to different decisions. They go away when those branches are closed.
- `claude/epic-gauss-md6x9b` is the only live branch that collides with default (337 to 340: iPad, car rules, quick actions, Outlook).
- Edits to existing rows (not collisions): ADR-306 in the admiring-curie branches, ADR-036 in admiring-bohr, ADR-028 in nifty-euler, ADR-018 in lucid-rubin.

### Between unmerged branches

- **ADR-324** is claimed three times: Quick start (`admiring-curie-bsuwv9`, `-quick-access`, `-all`), learning loop (`cool-archimedes-9l8l1h`) and unlock as you go (`lucid-johnson-pmwwg4`, `hopeful-fermat-1a63x0`).
- **ADR-341 to 343**: `epic-gauss-md6x9b` adds rows with these numbers; `hopeful-fermat-1a63x0` cites ADR-341 to 344 in code for other features.
- No clash: 319 to 322 and 360 to 362 (peaceful-hopper), 325 to 328 and 401 to 403 (admiring-curie).
- Fix: give one person the job of assigning numbers at merge time. Renumber in merge order.
