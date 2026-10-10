# Merge plan: this branch (PR #5) vs the parallel branch line
Date: 2026-10-10. Proposed first, then **applied the same day on this branch** (see "What was done" at the end).

## The situation
Both lines start from the same commit, `7073c98` "V1: talk to Doddy by voice". The repo's default branch, `claude/loving-dirac-uuxoux`, is still at that commit, and it is PR #5's base.

| | **This branch** `claude/elegant-knuth-hc1aql` (PR #5) | **Parallel line** (tip `claude/magical-newton-ip0bx2`) |
|---|---|---|
| Commits since V1 | 12 | 114 (from ~30 sessions) |
| Files changed | 102 | 419 |
| Live ElevenLabs agent | Uses its existing tools | **Defines** them: `voice-agent/` spec, 20 tools, synced to version `agtvrsn_5801…` |

The parallel line is itself **not consolidated**. Commits missing from its tip (checked with `git cherry`):
- `brave-wright` / `compassionate-darwin`: **iOS CI on a GitHub-hosted Mac** (ADR-123) and the agent language override.
- `blissful-curie`:
  - reminder dedupe and past-date refusal;
  - **"What Doddy did"** activity list;
  - **Pause all connections**;
  - **"What leaves this iPhone"** screen.
- `clever-ritchie`: TikTok/Instagram links in the site and app.
- **Possibly superseded, check before dropping:**
  - `busy-hawking` and `friendly-sagan`: older M2 gateway variants (Supabase and OpenAI);
  - `busy-mendel` and `vibrant-pasteur`: V2 Siri/Back Tap variants;
  - `upbeat-brown`: V4a Connections;
  - `eloquent-hawking`: explicit_voice notes.

## Feature by feature
| Feature | This branch | Parallel line | Keep |
|---|---|---|---|
| M1 local memory | base | base + profile/onboarding migration, `DoddyDatabase` | **Parallel** |
| AI answers (M2) | — | OpenAI gateway on Vercel (`gateway/`), citations verified | **Parallel** |
| Voice token | `/v1/voice/token` in `server/`, anonymous device token | `server/voice-token` on **Vercel production**, tester access codes | **Parallel** (it's live) |
| Apple Reminders (M4) | `outbox_actions`, marker reconcile, review sheet, list screen | Connections switch, content-key dedupe across agent retries, receipts, Calendar + Contacts too | **Parallel** (more complete). Drop mine |
| Calendar, Contacts, Timers, Maps, Shortcuts, Messages drafts | — | built (V1 Connections) | Parallel |
| Gmail / Drive / Notion / Todoist | — | `backend/` (Composio, Render free, SQLite that resets on deploy) | Parallel |
| Siri & Shortcuts, Control Center, Back Tap, Dynamic Island, widgets | — | built | Parallel |
| Onboarding, profile, personality settings, Today | — | built | Parallel |
| Website + waitlist | — | `site/` (Vercel) | Parallel |
| **Push + SMS updates** (S1) | `server/` Postgres outbox, APNs, Twilio + Verify, consent, STOP | — | **Port from this branch** |
| **Phone calls + memory on calls** (S2) | Twilio ↔ ElevenLabs phone agent, PIN, encrypted memory copy, notes inbox | — | **Port** |
| **Daily news DM** (N1) | RSS + GNews + Claude Haiku digest | — | **Port** |
| Durable server database | Postgres (Render) | SQLite on Render free (resets) | **Port** (the parallel backend needs it too) |
| Login | none (anonymous device account) | invite/access codes; backend refuses "production + live" until real sign-in | **Owner decision**, see below |

## Why PR #5 shouldn't be merged as it is
A test merge of PR #5 into the parallel tip (2026-10-10, scratch worktree, discarded) gave **22 conflicting files**:
- the worst are `VoiceSessionController.swift` (6 hunks), `VoiceView.swift` (5), `SettingsView.swift` (4), the guard script (4), `AppEnvironment.swift` (3) and `VoiceTools.swift` (3);
- `render.yaml` and `M4_REMINDERS_STATUS.md` were created on both sides;
- `DECISIONS.md` has clashing ADR numbers (this branch 036–065, parallel up to 130).

There are also **hidden compile clashes** git doesn't flag: both lines define `DeviceCredentialStore`, `KeychainCredentialStore`, `URLSessionTransport`, `ReminderAction` and `ReminderDue` differently. And `server/` would hold both this branch's Node service and the parallel `server/voice-token/`.

Merging PR #5 into the default branch would also move the default branch further away from where the real work is.

## Proposed plan
**Step 0: owner decisions (blocking)**
1. **Which line is the base?** Recommendation: the **parallel line**. It is larger, it defines the live agent, and it has CI on a Mac.
2. **Login / identity for server features.** Push, SMS, calls and news need one stable identity per user. Options:
   - (a) this branch's anonymous device account. It's built and tested, and includes delete-everything.
   - (b) the parallel line's access codes. These are for testers only.
   - (c) Sign in with Apple. Not built.

   Recommendation: (a) now, (c) before public release.
3. **One server or several?** The parallel line runs three services (gateway and voice-token on Vercel, backend on Render with SQLite). Push, SMS, calls and news need a database that survives restarts, plus a background worker.
   - Recommendation: **one Render web + worker + Postgres**, eventually hosting the Composio backend too.
   - Short term: deploy this branch's server as a fourth service, `server/messaging`.

**Step 1: consolidate the parallel line**
In one session: merge `brave-wright` (CI), `blissful-curie` (4 features) and `clever-ritchie` (links) into the parallel tip, check the "possibly superseded" branches, and make it the repo's **default branch**.

**Step 2: retire PR #5 and port in small PRs onto the consolidated base**
Each item is its own PR: green on the Mac CI, ADRs renumbered from 131, no duplicate types.

| PR | Content | Main work |
|---|---|---|
| A | **Server foundation + push/SMS updates.** `server/` → `server/messaging/`; Settings → Notifications and texts | Reuse the parallel `DeviceCredentialStore` / Keychain instead of mine. Fit Settings into their layout. Combine the guard rules (networking allowed in both `Infrastructure/Server` and their gateway client). APNs entitlement + privacy manifest |
| B | **Daily news** (needs A) | Settings entry; Anthropic key on the server only |
| C | **Phone calls + memory on calls** (needs A) | Put the phone agent into their `voice-agent/` spec format, so the drift check covers it. Memory copy sync must use their `DoddyDatabase` |
| D | **Clean-up** | Drop this branch's M4, `VoiceAuthPolicy` and voice-token route (parallel versions win). Port only what theirs lacks after a check, e.g. the launch-time recovery of interrupted writes, if their M4 doesn't have it |

Then **close PR #5** with a link to PRs A–D.

**Effort, rough:**
- PR A: about a day of agent work. Mostly the app-side conflicts; the server and tests move almost unchanged.
- PRs B and C: half a day each.
- PR D: a few hours.

## What stays true whatever is chosen
- No change has been made to any other branch, the default branch or the live agent by this comparison.
- This branch's server tests (34) and core tests (61) pass on the branch. They will need re-running after each port, because the base types differ.

## What was done (2026-10-10, after the owner's answers)

**Owner decisions (Step 0):**
1. Base line: the owner wasn't sure ("idk"), so the recommendation was applied: **the parallel line is the base**.
2. Identity: **anonymous device accounts now, Sign in with Apple before public release** (recommended).
3. Servers: **one Render setup** (owner: "ok"); short term the messaging server is a separate service next to `backend/`.

**How, given that this session may push only to `claude/elegant-knuth-hc1aql`:** instead of
separate PRs A–D, everything happened on this branch as one merge plus one commit per port, so
**PR #5 now carries the combined line**. Merging PR #5 into the default branch
(`claude/loving-dirac-uuxoux`, still at V1) therefore also does Step 1's "make the parallel line
the default".

| Commit | What |
|---|---|
| merge `blissful-curie` (local) | Parallel tip + `compassionate-darwin` (CI on a Mac, social links) + `brave-wright` (Linux CI, language override) + `blissful-curie` (What Doddy did, Pause all, What leaves this iPhone). `blissful-curie`'s own reminder dedupe duplicated ADR-126; the main line's version was kept and "What Doddy did" adapted to it |
| merge `eager-johnson` (local) | Blog. Colliding ADR numbers 123–129 sorted out (main line keeps its numbers; others moved to 131–138; was/now table in `DECISIONS.md`) |
| Merge into PR #5's branch | Conflicts resolved toward the combined line; `server/` → `server/messaging/`; this branch's M4 and voice-token route dropped; its ADRs renumbered 036–065 → 139–168 |
| Port A | Notifications and texts (app side), capabilities, privacy copy and manifest, push entitlement, guard, CI with Postgres, `render.yaml` |
| Port B | Daily news (app side) |
| Port C | Phone calls and memory on calls (app side) |

Left out on purpose: `busy-galileo` (same social links as `clever-ritchie`), and the older variant
branches `busy-hawking`, `friendly-sagan`, `busy-mendel`, `vibrant-pasteur`, `upbeat-brown`,
`eloquent-hawking` (their features are on the main line in later form; `explicit_voice` is
already used for voice notes). Other sessions were still pushing while this was done.

**Second merge (2026-10-10, ~13:05 UTC, owner: "merge them"):** brought in what those branches
pushed after the first merge: `compassionate-darwin` (gateway hosting notes), `blissful-curie`
("What Doddy did" survives a crash), `brave-wright` (private conversations, notes that may
disagree) and `eager-johnson` (blog published on the site, which already contains `busy-galileo`).
Their new ADR numbers collided again (128, 131, 132; the blog moved to 131 on its branch): they
are now 169, 170, 171, and the blog stays 138. The was/now table in `DECISIONS.md` lists them.
**Third merge (2026-10-10, ~15:30 UTC, owner: "merge them"):**
- `brave-wright`: memories and capture work (profile export, read/delete remembered
  conversations, restore from export, Save/Find shortcuts and New note control, type filter,
  undo delete, duplicate warning, share, list order, pins, press-and-hold menu, Paste button).
  Its ADR-133–146 collided with this branch's numbers and are now **176–189**.
- `hopeful-fermat`: note reminders (local notifications about a saved note, separate from Apple
  Reminders) and the voice prompt's AI disclosure restored; ADR-173/174 → **190/191**. Its
  "cancel the reminder on delete" met `brave-wright`'s undo: the delete message now says undo
  brings the note back but not its reminder.
- `eager-johnson` / `busy-galileo` (blog: "Hello, Doddy" unpublished, banners) and
  `serene-johnson` (site footer labels).
- `confident-planck` started from V1, not this line. Only its **Doddy Constitution documents**
  were taken (`docs/trust/`, `config/doddy_rules.yaml`, cherry-picked). **Not taken:** its
  edits to `CLAUDE.md` / `AGENTS.md` (they change every future agent session's instructions:
  owner decision), and its code (an action ledger, simulated approvals and a third Apple
  Reminders implementation, which would replace ADR-126's working one).

To stop this repeating, new sessions should start from this branch (or the default branch once
PR #5 is merged) and take the next free ADR number from `DECISIONS.md` at the time they commit (192 after the third merge).

**Follow-ups:**
- ~~Phone agent: move its definition from `server/messaging/scripts/setup-phone-agent.mjs` into the
  `voice-agent/` spec format so the drift check covers it.~~ Done (ADR-172, `voice-agent/phone/`).
- The owner merges PR #5 once CI is green, then closes or deletes the merged parallel branches.
- Everything in the S1/S2/N1 status docs under "owner actions" is still open (Render, Twilio, APNs, keys).
